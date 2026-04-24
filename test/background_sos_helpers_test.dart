import 'package:flutter_test/flutter_test.dart';
import 'package:safe_route/services/background_shake_service.dart';

void main() {
  group('Voice SOS helpers', () {
    test('matches emergency phrases reliably', () {
      expect(matchesEmergencyVoicePhrase('help me please'), isTrue);
      expect(matchesEmergencyVoicePhrase('SAVE ME now'), isTrue);
      expect(matchesEmergencyVoicePhrase('this is an sos'), isTrue);
      expect(matchesEmergencyVoicePhrase('medical emergency'), isTrue);
      expect(matchesEmergencyVoicePhrase('just checking directions'), isFalse);
    });

    test('builds m4a recording file name with session id', () {
      final fileName = buildSosRecordingFileName(
        'session123',
        4,
        DateTime(2026, 4, 25, 1, 45, 30),
      );

      expect(
        fileName,
        startsWith('sos_audio_session123_part_4_20260425_014530'),
      );
      expect(fileName, endsWith('.m4a'));
    });
  });
}
