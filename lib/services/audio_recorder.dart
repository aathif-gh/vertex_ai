import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class AudioRecorder {
  late Record _record;
  String? _currentPath;

  AudioRecorder() {
    _record = Record();
  }

  // Request microphone permission
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // Start recording to file
  Future<String?> startRecording() async {
    try {
      if (await _record.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        _currentPath = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
        
        await _record.start(
          path: _currentPath,
          encoder: AudioEncoder.wav,
        );
        return _currentPath;
      }
    } catch (e) {
      print('Error starting recording: $e');
    }
    return null;
  }

  // Stop recording and return file path
  Future<String?> stopRecording() async {
    try {
      final path = await _record.stop();
      return path;
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }

  // Check if recording is active
  Future<bool> isRecording() async {
    return await _record.isRecording();
  }
}