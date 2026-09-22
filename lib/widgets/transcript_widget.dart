import 'package:flutter/material.dart';
import '../models/meeting_model.dart';
import 'package:intl/intl.dart';

class TranscriptWidget extends StatelessWidget {
  final List<TranscriptItem> transcripts;

  const TranscriptWidget({super.key, required this.transcripts});

  @override
  Widget build(BuildContext context) {
    if (transcripts.isEmpty) {
      return const Center(child: Text('Press record to start transcription.'));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: transcripts.length,
      itemBuilder: (context, index) {
        final item = transcripts[index];
        final timeString = DateFormat('hh:mm a').format(item.timestamp);
        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(item.speaker.isNotEmpty ? item.speaker[0] : '?'),
            ),
            title: Text(item.speaker.isNotEmpty ? item.speaker : 'Incoming Speech...', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(item.text),
            ),
            trailing: Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        );
      },
    );
  }
}
