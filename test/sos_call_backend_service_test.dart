import 'package:flutter_test/flutter_test.dart';
import 'package:safe_route/services/sos_call_backend_service.dart';

void main() {
  test('SosCallStatusPayload parses safe defaults', () {
    const payload = SosCallStatusPayload(
      sessionId: 'session-1',
      status: 'connected',
      statusText: 'Call connected',
      isCallActive: true,
      isSafe: false,
      canShowPostSafeActions: false,
      providerCallId: 'call-1',
      currentContact: '+911234567890',
    );

    expect(payload.sessionId, 'session-1');
    expect(payload.status, 'connected');
    expect(payload.isCallActive, isTrue);
    expect(payload.providerCallId, 'call-1');
  });

  test('SosCallStatusPayload.fromJson handles omitted optional fields', () {
    final payload = SosCallStatusPayload.fromJson({
      'sessionId': 'session-2',
      'status': 'safe',
      'statusText': 'SOS marked safe. Call controls unlocked.',
      'isCallActive': false,
      'isSafe': true,
      'canShowPostSafeActions': true,
    });

    expect(payload.sessionId, 'session-2');
    expect(payload.isSafe, isTrue);
    expect(payload.canShowPostSafeActions, isTrue);
    expect(payload.providerCallId, isNull);
  });
}
