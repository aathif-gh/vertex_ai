import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/meeting_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LLMService
//
// Sends the full transcript to Groq's chat-completions endpoint (Mixtral-8x7b)
// and asks it to extract structured action items and key decisions.
//
// INTEGRATION POINT: Replace 'gsk_YOUR_KEY' with your actual Groq API key.
// Same key as TranscriptionService is fine — Groq supports both APIs under
// one key.
// ─────────────────────────────────────────────────────────────────────────────

const String _groqApiKey = String.fromEnvironment('GROQ_API_KEY');
const String _chatEndpoint =
    'https://api.groq.com/openai/v1/chat/completions';

class LLMService {
  final Dio _dio;

  LLMService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
              headers: {
                'Authorization': 'Bearer $_groqApiKey',
                'Content-Type': 'application/json',
              },
            ));

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Takes a list of [TranscriptEntry] objects, formats them into a prompt,
  /// and calls Groq Mixtral to extract action items and decisions.
  ///
  /// Returns a map with keys:
  ///   - `diarized_transcript` : List<TranscriptEntry>
  ///   - `actions`   : List<ActionItem>
  ///   - `summary` : List<String>
  Future<Map<String, dynamic>> extractActionsFromTranscript(
      List<TranscriptEntry> entries) async {
    if (entries.isEmpty) return {};

    final rawText = entries.map((e) => e.toFormattedString()).join('\n');

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _chatEndpoint,
        data: jsonEncode({
          'model': 'qwen/qwen3.8-27b',
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are an executive meeting assistant summarizing a diarized audio transcript. '
                  'If the transcript contains lines marked with [HIGHLIGHTED] or [COMMENT: xxx], these denote critical moments '
                  'bookmarked by the user live. You MUST prioritize and explicitly emphasize these moments in the summary. '
                  'Respond with valid JSON only.',
            },
            {
              'role': 'user',
              'content': '''Analyse the Diarized Meeting Transcript below. Return a JSON object matching this schema:
{
  "actions": [
    {"task": "string", "owner": "string", "deadline": "string"}
  ],
  "summary": ["string"],
  "compliance": {
    "risk_level": "string",
    "flags": ["string"]
  },
  "sensitive_phrases": ["string"]
}

Rules:
- "compliance.risk_level": MUST be exactly one of: "🔴 Confidential", "🟡 PII", or "🟢 Safe"
- "compliance.flags": Array of human-readable issues detected (e.g. "SOX Alert: Earnings mentioned", "HIPAA: Medical diagnosis"). If Safe, return [].
- "sensitive_phrases": List of exact verbatim words or short phrases from the transcript that are sensitive (e.g. specific names, dollar amounts, diagnoses, project codenames, emails). Return [] if Safe.
- "summary": 3-4 professional bullet points. DO NOT use [REDACTED] here — write naturally. The app will mask it automatically.
- "actions": Tasks assigned. If none, return [].

DIARIZED TRANSCRIPT:
$rawText''',
            },
          ],
        }),
      );

      var content = response.data?['choices']?[0]?['message']?['content']
          as String?;
      if (content == null || content.isEmpty) return {};

      // Open source models often wrap JSON in markdown blocks. Strip them.
      content = content.replaceAll(RegExp(r'^```json\s*', multiLine: true), '');
      content = content.replaceAll(RegExp(r'^```\s*', multiLine: true), '');
      content = content.trim();

      final decoded = jsonDecode(content) as Map<String, dynamic>;

      // 1. (Diarization is now handled natively by Deepgram off-cloud)

      // 1. Parse actions
      final rawActions = (decoded['actions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();
      List<ActionItem> actions = rawActions.map((j) => ActionItem.fromJson(j)).toList();

      // 2. Parse summary
      List<String> summary = (decoded['summary'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList();

      // 3. Parse compliance
      final comp = ComplianceReport.fromJson(decoded['compliance'] as Map<String, dynamic>?);

      // 4. Parse sensitive phrases for client-side masking
      final sensitivePhrases = (decoded['sensitive_phrases'] as List<dynamic>? ?? [])
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();

      // 5. Apply hybrid redaction to summary + action tasks:
      //    a) LLM-identified semantic phrases
      //    b) Regex patterns for predictable PII (email, phone, card numbers)
      summary = summary.map((s) => _redact(s, sensitivePhrases)).toList();
      actions = actions.map((a) {
        final masked = _redact(a.task, sensitivePhrases);
        return ActionItem(task: masked, assignee: a.assignee, deadline: a.deadline);
      }).toList();

      return {
        'actions': actions,
        'summary': summary,
        'compliance': comp,
      };
    } on DioException catch (e) {
      final groqError = e.response?.data?['error']?['message'] as String?;
      print('[LLMService] DioException: ${groqError ?? e.message}');
      return {};
    } catch (e) {
      print('[LLMService] Unexpected error: $e');
      return {};
    }
  }

  // ── 2. Wake-Word Fast Intent Parser ────────────────────────────────────────

  /// Takes a single spoken sentence that contains a wake-word ("Hey iQOO"),
  /// and rapidly parses the intent into actionable parameters.
  Future<Map<String, dynamic>> parseWakeWordIntent(String text) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _chatEndpoint,
        data: jsonEncode({
          'model': 'llama-3.1-8b-instant', // Use a smaller, faster model just for intent
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are an AI assistant intent parser. The user triggered a wake word (e.g. "Hey iQOO"). '
                  'Extract their command. Return ONLY valid JSON mathing this schema:\n'
                  '{"action": "calendar|reminder|email|unknown", "title": "string", "start_time": "ISO8601", "end_time": "ISO8601"}\n'
                  'CRITICAL: For calendar actions, start_time and end_time MUST be strictly ISO 8601 format relative to the current local time: 2026-09-18T16:15:00+05:30. Default meetings to 30 mins if length unspecified.'
            },
            {
              'role': 'user',
              'content': 'Parse this command: "$text"',
            },
          ],
        }),
      );

      var content = response.data?['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.isEmpty) return {};

      content = content.replaceAll(RegExp(r'^```json\s*', multiLine: true), '');
      content = content.replaceAll(RegExp(r'^```\s*', multiLine: true), '');
      
      return jsonDecode(content.trim()) as Map<String, dynamic>;
    } catch (e) {
      print('[LLMService] Intent Parse Error: $e');
      return {};
    }
  }

  // ── Hybrid Redaction Engine ──────────────────────────────────────────────
  //
  // Layer 1: LLM-identified semantic phrases (project names, salaries, diagnoses)
  // Layer 2: Regex — Emails, Indian/international phone numbers, credit card numbers
  //
  static String _redact(String text, List<String> phrases) {
    var result = text;

    // Layer 1: LLM semantic phrases (case-insensitive whole-word match)
    for (final phrase in phrases) {
      if (phrase.length < 3) continue; // skip tiny tokens
      final escaped = RegExp.escape(phrase);
      result = result.replaceAll(
        RegExp(r'\b' + escaped + r'\b', caseSensitive: false),
        '[REDACTED]',
      );
    }

    // Layer 2: Email addresses  → name@domain.tld
    result = result.replaceAll(
      RegExp(
          r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
          caseSensitive: false),
      '[REDACTED]',
    );

    // Layer 3: Phone numbers (10-digit Indian mobile, +91 prefix variants, US)
    result = result.replaceAll(
      RegExp(r'(\+91[\s\-]?)?[6-9]\d{9}|\b\d{10}\b|\(\d{3}\)[\s\-]?\d{3}[\s\-]?\d{4}'),
      '[REDACTED]',
    );

    // Layer 4: 16-digit card numbers (with optional spaces/dashes)
    result = result.replaceAll(
      RegExp(r'\b(?:\d[ -]?){16}\b'),
      '[REDACTED]',
    );

    return result;
  }

  // ── Legacy mock (so existing widgets compile without change) ───────────────

  /// Kept for backward compatibility with widgets that still call the old API.
  /// Returns a hard-coded list for testing without a Groq key.
  List<ActionItem> extractActionItems(List<String> _) => [
        ActionItem(
            task: 'Connect real Groq API key in transcription_service.dart',
            assignee: 'You',
            deadline: 'Before hackathon demo'),
      ];
}
