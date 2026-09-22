import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import '../models/meeting_model.dart';

class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  IOWebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _keepAliveTimer;

  final _transcriptController = StreamController<TranscriptEntry>.broadcast();
  Stream<TranscriptEntry> get transcriptStream => _transcriptController.stream;

  // Deepgram API
  static const String _deepgramApiKey =
      String.fromEnvironment('DEEPGRAM_API_KEY');
  static const String _deepgramUrl =
      'wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000&channels=1&diarize=true&punctuate=true&redact=pci&redact=ssn';

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) return;

    // 1. Establish WebSocket connection to Deepgram
    final ws = await WebSocket.connect(
      _deepgramUrl,
      headers: {'Authorization': 'Token $_deepgramApiKey'},
    );
    _channel = IOWebSocketChannel(ws);

    // 2. Listen to Deepgram for real-time JSON transcripts
    _channel!.stream.listen((message) {
      try {
        final data = jsonDecode(message);
        
        // Deepgram sends intermediate and final results. We only want final completed phrases.
        if (data['is_final'] == true) {
          final channel = data['channel'];
          if (channel != null) {
            final alts = channel['alternatives'] as List?;
            if (alts != null && alts.isNotEmpty) {
              final alt = alts[0];
              final text = alt['transcript'] as String;
              
              if (text.isNotEmpty) {
                // Diarization: get speaker ID from the first word
                int speakerId = 0;
                if (alt['words'] != null && alt['words'].isNotEmpty) {
                  speakerId = alt['words'][0]['speaker'] ?? 0;
                }
                
                _transcriptController.add(TranscriptEntry(
                  speaker: 'Speaker $speakerId',
                  text: text,
                  timestamp: DateTime.now(),
                ));
              }
            }
          }
        }
      } catch (e) {
        print('Deepgram JSON Parse Error: $e');
      }
    }, onError: (err) {
      print('Deepgram WebSocket Error: $err');
    }, onDone: () {
      print('Deepgram WebSocket Closed.');
    });

    // 3. Start streaming raw PCM 16-bit audio from microphone
    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    // 4. Blast raw mic bytes directly up to Deepgram
    _audioSub = audioStream.listen((data) {
      _channel?.sink.add(data);
    });
  }

  Future<void> pauseRecording() async {
    await _recorder.pause();
    // Deepgram kills WebSockets after 10-12s of no audio data.
    // We MUST send KeepAlive JSON messages every 5 seconds to hold the pipe open.
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _channel?.sink.add('{"type": "KeepAlive"}');
    });
  }

  Future<void> resumeRecording() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _recorder.resume();
  }

  Future<void> stopRecording() async {
    _keepAliveTimer?.cancel();
    
    // 1. Stop mic
    await _recorder.stop();
    await _audioSub?.cancel();

    // 2. Tell Deepgram we are done sending audio so it flushes the final text
    if (_channel != null) {
      _channel!.sink.add('{"type": "CloseStream"}');
      // Give it time to send the final transcript chunk before snapping the pipe shut
      await Future.delayed(const Duration(milliseconds: 1500));
      await _channel!.sink.close();
      _channel = null;
    }
  }
}
