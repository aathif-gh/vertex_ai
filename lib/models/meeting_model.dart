// ─── TranscriptEntry ──────────────────────────────────────────────────────────
/// A single line of meeting transcript (speaker + spoken text + timestamp).
class TranscriptEntry {
  final String speaker;
  String text;
  final DateTime timestamp;
  bool isHighlighted;
  String comment;

  TranscriptEntry({
    required this.speaker,
    required this.text,
    required this.timestamp,
    this.isHighlighted = false,
    this.comment = '',
  });

  /// Human-readable line used in prompts and PDFs.
  String toFormattedString() {
    final base = '[${_hm(timestamp)}] $speaker: $text';
    if (isHighlighted || comment.isNotEmpty) {
      final tags = [
        if (isHighlighted) 'HIGHLIGHTED',
        if (comment.isNotEmpty) 'COMMENT: $comment'
      ];
      return '$base [${tags.join(" | ")}]';
    }
    return base;
  }

  static String _hm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// Keep legacy name so existing widgets compile without change.
typedef TranscriptItem = TranscriptEntry;

// ─── ActionItem ───────────────────────────────────────────────────────────────
class ActionItem {
  final String task;
  final String assignee;
  final String deadline; // e.g. "EOD tomorrow", "Friday", ""
  bool isCompleted;

  ActionItem({
    required this.task,
    required this.assignee,
    this.deadline = '',
    this.isCompleted = false,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        task: json['task'] as String? ?? '',
        assignee: json['owner'] as String? ?? 'Unassigned',
        deadline: json['deadline'] as String? ?? '',
      );
}

// ─── ComplianceReport ────────────────────────────────────────────────────────
class ComplianceReport {
  final String status;
  final List<String> flags;

  ComplianceReport({
    required this.status,
    this.flags = const [],
  });

  factory ComplianceReport.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ComplianceReport(status: '🟢 Safe');
    return ComplianceReport(
      status: json['risk_level'] as String? ?? '🟢 Safe',
      flags: (json['flags'] as List<dynamic>? ?? []).whereType<String>().toList(),
    );
  }
}

// ─── MeetingModel ─────────────────────────────────────────────────────────────
class MeetingModel {
  final String title;
  final DateTime startTime;
  final List<TranscriptEntry> transcript;
  final List<ActionItem> actionItems;
  final List<String> decisions;
  final ComplianceReport? compliance;

  MeetingModel({
    required this.title,
    required this.startTime,
    this.transcript = const [],
    this.actionItems = const [],
    this.decisions = const [],
    this.compliance,
  });
}
