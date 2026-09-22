import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/actions_widget.dart';
import '../services/audio_recording_service.dart';
import '../services/llm_service.dart';
import '../services/pdf_generator.dart';
import '../services/google_calendar_service.dart';
import '../models/meeting_model.dart';

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});
  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen>
    with TickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isExtracting = false;
  bool _isProcessingCommand = false;
  bool _awaitingCommandSentence = false;
  String _commandBuffer = '';
  bool _calendarConnected = false; // true once OAuth token acquired

  final AudioRecordingService _recorder = AudioRecordingService();
  final LLMService _llm = LLMService();
  final GoogleCalendarService _calendarService = GoogleCalendarService();

  StreamSubscription<TranscriptEntry>? _sub;
  List<TranscriptEntry> _transcript = [];
  List<ActionItem> _actions = [];
  List<String> _decisions = [];
  ComplianceReport? _compliance;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _elapsed = '00:00';
  late AnimationController _pulseController;
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _pulseController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Recording Flow ────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _transcript.clear();
      _actions.clear();
      _decisions.clear();
      _elapsed = '00:00';
    });
    
    _stopwatch.reset();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() => _elapsed =
            '${_p(_stopwatch.elapsed.inMinutes)}:${_p(_stopwatch.elapsed.inSeconds % 60)}');
      }
    });

    await _recorder.startRecording();
    
    // Bind UI live to the WebSocket stream
    _sub = _recorder.transcriptStream.listen((entry) {
      if (mounted) {
        setState(() => _transcript.add(entry));
        
        final textLower = entry.text.toLowerCase();

        // ── Phase 1: Wake-Word detected in this sentence ──
        final _wakeWords = ['hey vertex', 'hey vortex', 'a vertex', 'eight vertex', 'hey vertices', 'hey cortex', 'hey vertix', 'hey vertext'];
        if (!_isProcessingCommand && _wakeWords.any((w) => textLower.contains(w))) {
          entry.isHighlighted = true;
          entry.comment = '⚡ Wake-Word Detected';
          print('[WakeWord] Phase 1 triggered! Entry text: "${entry.text}"');

          // Extract whatever was spoken AFTER the trigger phrase
          final idx = textLower.indexOf('hey vertex') + 'hey vertex'.length;
          final trailing = entry.text.substring(idx).trim();
          print('[WakeWord] Trailing text after trigger: "$trailing" (len=${trailing.length})');

          if (trailing.length > 4) {
            _commandBuffer = 'Hey Vertex, $trailing';
            print('[WakeWord] Full command in one sentence, firing: "$_commandBuffer"');
            _processWakeWordString(_commandBuffer);
            _commandBuffer = '';
            _awaitingCommandSentence = false;
          } else {
            _commandBuffer = 'Hey Vertex, ';
            _awaitingCommandSentence = true;
            print('[WakeWord] Command incomplete, waiting for next sentence...');
          }
        }
        // ── Phase 2: Command sentence arrived after the wake word ──
        else if (_awaitingCommandSentence && !_isProcessingCommand) {
          _commandBuffer += entry.text;
          print('[WakeWord] Phase 2 - full command: "$_commandBuffer"');
          _awaitingCommandSentence = false;
          _processWakeWordString(_commandBuffer);
          _commandBuffer = '';
        }

        // Auto-scroll UI as new words arrive
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  Future<void> _pauseRecording() async {
    await _recorder.pauseRecording();
    _stopwatch.stop();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecording() async {
    await _recorder.resumeRecording();
    _stopwatch.start();
    setState(() => _isPaused = false);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _stopwatch.stop();
    await _sub?.cancel();
    await _recorder.stopRecording();

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _isExtracting = true;
    });

    // Generate smart summary over the live text highlighting
    final results = await _llm.extractActionsFromTranscript(_transcript);

    if (mounted) {
      setState(() {
        _actions = results['actions'] as List<ActionItem>? ?? [];
        _decisions = results['summary'] as List<String>? ?? [];
        _compliance = results['compliance'] as ComplianceReport?;
        _isExtracting = false;
      });
      _tabController.animateTo(1);
    }
  }

  // ── Wake Word Assistant ──────────────────────────────────────────────────

  void _processWakeWordString(String text) async {
    if (_isProcessingCommand) return;
    setState(() {
      _isProcessingCommand = true;
      _awaitingCommandSentence = false;
    });
    
    _showSnack('Hey Vertex: hearing command...', duration: const Duration(seconds: 2));
    
    final intent = await _llm.parseWakeWordIntent(text);
    
    if (mounted) {
      
      final action = intent['action'] as String?;
      final title = intent['title'] as String?;
      final startTime = intent['start_time'] as String?;
      final endTime = intent['end_time'] as String?;
      
      if (action != null && action != 'unknown') {
        
        bool apiSuccess = false;
        if (action == 'calendar' && title != null && startTime != null && endTime != null) {
          apiSuccess = await _calendarService.scheduleEvent(title, startTime, endTime);
        }

        setState(() => _isProcessingCommand = false); // unlock AFTER processing

        showDialog(
           context: context,
           builder: (ctx) => AlertDialog(
             backgroundColor: Theme.of(context).colorScheme.primaryContainer,
             title: Row(
               children: [
                 Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary), 
                 const SizedBox(width: 8), 
                 const Text('iQOO Assistant Action')
               ],
             ),
             content: Column(
               mainAxisSize: MainAxisSize.min,
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                  Text('Intent matched: ${action.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (title != null) Text('Task: $title', style: const TextStyle(fontSize: 14)),
                  if (startTime != null) ...[
                    const SizedBox(height: 4),
                    Text('Start: $startTime', style: const TextStyle(fontSize: 14)),
                    Text('End: $endTime', style: const TextStyle(fontSize: 14)),
                  ],
                  const SizedBox(height: 16),
                  if (apiSuccess)
                    const Text('✅ Scheduled in Google Calendar locally.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13))
                  else
                    const Text('❌ API Error or Action Simulated.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13))
               ],
             ),
             actions: [
               TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Dismiss'))
             ],
           )
        );
      } else {
        setState(() => _isProcessingCommand = false);
      }
    }
  }

  // ── Interaction ────────────────────────────────────────────────────────────

  void _showHighlightDialog(TranscriptEntry entry) {
    if (_isExtracting || _actions.isNotEmpty) return; // Prevent edits after finalize

    final tc = TextEditingController(text: entry.comment);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.star, color: Colors.orange),
            SizedBox(width: 8),
            Text('Bookmark Moment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('"${entry.text}"',
                style: const TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            TextField(
              controller: tc,
              decoration: const InputDecoration(
                labelText: 'Add a comment for the AI (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                entry.isHighlighted = true;
                entry.comment = tc.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save Bookmark'),
          ),
        ],
      ),
    );
  }

  // ── PDF Share Helpers ─────────────────────────────────────────────────────

  MeetingModel _buildMeeting() => MeetingModel(
        title: 'Meeting - $_elapsed recorded',
        startTime: DateTime.now().subtract(_stopwatch.elapsed),
        transcript: _transcript,
        actionItems: _actions,
        decisions: _decisions,
        compliance: _compliance,
      );

  Future<void> _shareTranscriptPDF() async {
    try {
      final bytes = Uint8List.fromList(
          await PdfGenerator.generateTranscriptPDF(_buildMeeting()));
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'transcript_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      _showSnack('Share error: $e');
    }
  }

  Future<void> _shareSummaryPDF() async {
    try {
      final bytes = Uint8List.fromList(
          await PdfGenerator.generateSummaryPDF(_buildMeeting()));
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'summary_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      _showSnack('Share error: $e');
    }
  }

  void _showSnack(String msg, {Duration duration = const Duration(seconds: 4)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: duration));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  String _p(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
          title: Row(
            children: [
              const Text('Meeting Transcription'),
              if (_isRecording) ...[
                const SizedBox(width: 12),
                if (_isPaused)
                  const Icon(Icons.pause, size: 14, color: Colors.orange)
                else
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red
                            .withOpacity(0.4 + 0.6 * _pulseController.value),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Text(_elapsed, style: const TextStyle(fontSize: 13)),
              ],
              if (_isExtracting) ...[
                const SizedBox(width: 12),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 6),
                const Text('Analysing highlights…', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            // Google Calendar Connect Button
            IconButton(
              tooltip: _calendarConnected ? 'Google Calendar Connected' : 'Connect Google Calendar',
              icon: Icon(
                Icons.calendar_month,
                color: _calendarConnected ? Colors.greenAccent : Colors.white54,
              ),
              onPressed: () async {
                try {
                  _showSnack('Opening Google Sign-In...');
                  await _calendarService.authenticate();
                  if (mounted) {
                    setState(() => _calendarConnected = true);
                    _showSnack('✅ Google Calendar connected!');
                  }
                } catch (e) {
                  _showSnack('❌ Auth failed: $e');
                }
              },
            ),
            if (_transcript.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share_rounded),
                onSelected: (value) {
                  if (value == 'transcript') _shareTranscriptPDF();
                  if (value == 'summary') _shareSummaryPDF();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'transcript',
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, size: 20, color: cs.primary),
                        const SizedBox(width: 12),
                        const Text('Export Transcript'),
                      ],
                    ),
                  ),
                  if (_actions.isNotEmpty || _decisions.isNotEmpty)
                    PopupMenuItem(
                      value: 'summary',
                      child: Row(
                        children: [
                          Icon(Icons.summarize_outlined, size: 20, color: cs.secondary),
                          const SizedBox(width: 12),
                          const Text('Export Summary & Actions'),
                        ],
                      ),
                    ),
                ],
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.transcribe), text: 'Live Transcript'),
              Tab(
                icon: Icon(Icons.fact_check),
                text: 'Smart Summary',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // ── Live Interactive Transcript ──
            _transcript.isEmpty
                ? Center(
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, size: 48, color: cs.primary.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('Tap microphone to start live streaming',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 120, top: 12),
                    itemCount: _transcript.length,
                    itemBuilder: (context, index) {
                      final entry = _transcript[index];
                      final isHighlighted = entry.isHighlighted || entry.comment.isNotEmpty;

                      return InkWell(
                        onTap: () => _showHighlightDialog(entry),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.transparent,
                            border: isHighlighted
                                ? Border.all(color: Colors.orange.withOpacity(0.5))
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.speaker,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          color: cs.primary),
                                    ),
                                  ),
                                  if (isHighlighted)
                                    const Icon(Icons.star, size: 16, color: Colors.orange)
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(entry.text,
                                  style: const TextStyle(fontSize: 15, height: 1.4)),
                              if (entry.comment.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '💬 NOTE: ${entry.comment}',
                                    style: TextStyle(
                                        color: cs.secondary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                )
                            ],
                          ),
                        ),
                      );
                    },
                  ),

            // ── AI Smart Summary ──
            _actions.isEmpty && _decisions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 48, color: cs.secondary.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('End the meeting to generate a smart summary', style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
                    children: [
                      // Compliance Banner
                      if (_compliance != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _compliance!.status.contains('Safe') 
                                ? Colors.green.withOpacity(0.1) 
                                : _compliance!.status.contains('PII')
                                    ? Colors.orange.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _compliance!.status.contains('Safe') 
                                ? Colors.green 
                                : _compliance!.status.contains('PII')
                                    ? Colors.orange
                                    : Colors.red,
                              width: 1.5,
                            )
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _compliance!.status.contains('Safe') ? Icons.check_circle : Icons.warning_amber_rounded,
                                    color: _compliance!.status.contains('Safe') ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Compliance: ${_compliance!.status}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                                ],
                              ),
                              if (_compliance!.flags.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ..._compliance!.flags.map((f) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ', style: TextStyle(fontSize: 16, height: 1.2)),
                                      Expanded(child: Text(f, style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600))),
                                    ],
                                  ),
                                )),
                              ]
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Overview / Decisions
                      if (_decisions.isNotEmpty) ...[
                        Text('Meeting Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _decisions.map((s) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('• ', style: TextStyle(fontSize: 18, color: cs.primary, height: 1.1)),
                                      Expanded(child: Text(s, style: const TextStyle(fontSize: 15, height: 1.4))),
                                    ],
                                  ),
                                )).toList(),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      // Action Items
                      if (_actions.isNotEmpty) ...[
                        Text('Action Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.secondary)),
                        const SizedBox(height: 12),
                        ActionsWidget(actionItems: _actions),
                      ],
                      // Rerun Button
                      const SizedBox(height: 16),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            setState(() => _isExtracting = true);
                            final res = await _llm.extractActionsFromTranscript(_transcript);
                            if (mounted) {
                              setState(() {
                                _actions = res['actions'] as List<ActionItem>? ?? [];
                                _decisions = res['summary'] as List<String>? ?? [];
                                _compliance = res['compliance'] as ComplianceReport?;
                                _isExtracting = false;
                              });
                            }
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Regenerate Summary'),
                        ),
                      )
                    ],
                  ),
          ],
        ),

        // ── Single Main FAB ──
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _isExtracting
            ? const SizedBox()
            : _isRecording
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.extended(
                        onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                        backgroundColor: _isPaused ? cs.primary : Colors.orange,
                        icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                        label: Text(
                          _isPaused ? 'Resume' : 'Pause',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      FloatingActionButton.extended(
                        onPressed: _stopRecording,
                        backgroundColor: Colors.red,
                        icon: const Icon(Icons.stop),
                        label: const Text(
                          'End Meeting',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  )
                : FloatingActionButton.extended(
                    onPressed: _startRecording,
                    backgroundColor: cs.primary,
                    icon: const Icon(Icons.mic),
                    label: const Text(
                      'Start Meeting',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
    );
  }
}
