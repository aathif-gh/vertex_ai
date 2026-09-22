import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/meeting_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PdfGenerator  –  creates two distinct PDF report types
//   1. generateTranscriptPDF  → full speaker-diarized transcript
//   2. generateSummaryPDF     → meeting summary + action items
// ─────────────────────────────────────────────────────────────────────────────

// Otter.ai-inspired palette
const _kBlue = PdfColor.fromInt(0xFF2563EB);
const _kBlueLight = PdfColor.fromInt(0xFFDBEAFE);
const _kSlate = PdfColor.fromInt(0xFF1E293B);
const _kGrey = PdfColor.fromInt(0xFF64748B);
const _kGreen = PdfColor.fromInt(0xFF16A34A);
const _kGreenLight = PdfColor.fromInt(0xFFDCFCE7);
const _kRed = PdfColor.fromInt(0xFFDC2626);

abstract class PdfGenerator {
  // ── 1. Transcript PDF ──────────────────────────────────────────────────────

  static Future<List<int>> generateTranscriptPDF(MeetingModel meeting) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate =
        '${now.year}-${_p(now.month)}-${_p(now.day)}  ${_p(now.hour)}:${_p(now.minute)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _pageHeader(
          'Meeting Transcript',
          formattedDate,
          meeting.title,
          meeting.compliance,
        ),
        footer: (context) => _pageFooter(context),
        build: (context) => [
          ...meeting.transcript.asMap().entries.map((entry) {
            final t = entry.value;
            final prevSpeaker = entry.key > 0
                ? meeting.transcript[entry.key - 1].speaker
                : null;
            final isNewSpeaker = t.speaker != prevSpeaker;

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (isNewSpeaker) ...[
                  pw.SizedBox(height: 14),
                  pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: _kBlueLight,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Text(
                          _s(t.speaker),
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: _kBlue,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        _formatTime(t.timestamp),
                        style: pw.TextStyle(color: _kGrey, fontSize: 9),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                ],
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 4, bottom: 2),
                  child: pw.Text(
                    _s(t.text),
                    style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );

    return pdf.save();
  }

  // ── 2. Summary & Actions PDF ──────────────────────────────────────────────

  static Future<List<int>> generateSummaryPDF(MeetingModel meeting) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate =
        '${now.year}-${_p(now.month)}-${_p(now.day)}  ${_p(now.hour)}:${_p(now.minute)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _pageHeader(
          'Meeting Summary & Action Items',
          formattedDate,
          meeting.title,
          meeting.compliance,
        ),
        footer: (context) => _pageFooter(context),
        build: (context) => [
          // ── Summary section ──
          if (meeting.decisions.isNotEmpty) ...[
            _sectionTitle('Meeting Summary', _kBlue),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: _kBlueLight,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _kBlue, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: meeting.decisions.asMap().entries.map((e) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 6,
                          height: 6,
                          margin: const pw.EdgeInsets.only(top: 3, right: 8),
                          decoration: const pw.BoxDecoration(
                            color: _kBlue,
                            shape: pw.BoxShape.circle,
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            _s(e.value),
                            style: const pw.TextStyle(
                                fontSize: 11, lineSpacing: 3),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            pw.SizedBox(height: 24),
          ],

          // ── Action items section ──
          if (meeting.actionItems.isNotEmpty) ...[
            _sectionTitle('Action Items', _kGreen),
            pw.SizedBox(height: 8),
            ...meeting.actionItems.asMap().entries.map((e) {
              final item = e.value;
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _kGreenLight,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _kGreen, width: 0.4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _s(item.task),
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      children: [
                        _pill('To: ${_s(item.assignee)}', _kBlue, _kBlueLight),
                        if (item.deadline.isNotEmpty) ...[
                          pw.SizedBox(width: 8),
                          _pill('Due: ${_s(item.deadline)}', _kRed,
                              PdfColor.fromInt(0xFFFEE2E2)),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  static pw.Widget _pageHeader(String title, String date, String subtitle, ComplianceReport? compliance) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _s(title),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: _kSlate,
              ),
            ),
            pw.Text(_s(date),
                style: pw.TextStyle(fontSize: 9, color: _kGrey)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(_s(subtitle),
            style: pw.TextStyle(fontSize: 11, color: _kGrey)),
        
        if (compliance != null && compliance.status != '🟢 Safe') ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: compliance.status.contains('PII') ? PdfColor.fromInt(0xFFFEF3C7) : PdfColor.fromInt(0xFFFEE2E2),
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(
                color: compliance.status.contains('PII') ? PdfColor.fromInt(0xFFF59E0B) : _kRed,
                width: 1,
              ),
            ),
            child: pw.Text('Compliance Risk: ${_s(compliance.status)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kSlate)),
          ),
          if (compliance.flags.isNotEmpty) ...[
             pw.SizedBox(height: 4),
             ...compliance.flags.map((f) => pw.Text('- ${_s(f)}', style: pw.TextStyle(fontSize: 9, color: _kSlate))),
          ]
        ],

        pw.SizedBox(height: 8),
        pw.Divider(color: _kBlue, thickness: 1.5),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _pageFooter(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: _kGrey, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by Meeting Transcription - iQOO Hackathon',
                style: pw.TextStyle(fontSize: 8, color: _kGrey)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _kGrey)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _sectionTitle(String title, PdfColor color) {
    return pw.Row(
      children: [
        pw.Container(
          width: 3,
          height: 18,
          color: color,
          margin: const pw.EdgeInsets.only(right: 8),
        ),
        pw.Text(
          _s(title),
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _pill(String text, PdfColor fg, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(_s(text),
          style: pw.TextStyle(fontSize: 9, color: fg,
              fontWeight: pw.FontWeight.bold)),
    );
  }

  static String _formatTime(DateTime dt) =>
      '${_p(dt.hour)}:${_p(dt.minute)}';

  static String _p(int n) => n.toString().padLeft(2, '0');

  // Regex string sanitizer: strips ALL non-ASCII characters to prevent font renderer crashes
  static String _s(String text) => text.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
}
