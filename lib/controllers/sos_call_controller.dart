import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/sos_call_backend_service.dart';
import 'sos_controller.dart';

class SosCallController extends GetxController {
  SosCallController({SosCallBackendService? backendService})
    : _backendService = backendService ?? SosCallBackendService();

  static const String _activeCallSessionPrefsKey = 'active_sos_call_session_id';
  static const Duration _pollInterval = Duration(seconds: 5);
  static const Duration _voiceRetryBaseDelay = Duration(seconds: 3);
  static const int _maxVoiceStartAttempts = 3;
  static const MethodChannel _nativeChannel = MethodChannel('safe_route/sms');

  static SosCallController get instance => Get.find<SosCallController>();

  final SosCallBackendService _backendService;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final callStatus = 'idle'.obs;
  final callStatusText = ''.obs;
  final activeSessionId = RxnString();
  final showPostSafeActions = false.obs;
  final isCallActive = false.obs;
  final isStartingCall = false.obs;
  final isEndingCall = false.obs;
  final lastCallError = ''.obs;

  Timer? _pollTimer;
  StreamSubscription<User?>? _authSubscription;
  int _dialerFallbackIndex = 0;

  @override
  void onInit() {
    super.onInit();
    _restorePersistedState();
    _authSubscription = _auth.userChanges().listen((user) {
      if (user == null) {
        _clearCallState();
      } else {
        unawaited(restoreActiveSessionIfNeeded());
      }
    });
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    _authSubscription?.cancel();
    super.onClose();
  }

  Future<void> startParallelCallingForSos({
    required String sessionId,
    required List<String> emergencyContacts,
    required double latitude,
    required double longitude,
  }) async {
    if (isStartingCall.value) {
      return;
    }
    if (activeSessionId.value == sessionId &&
        (isCallActive.value ||
            callStatus.value == 'calling' ||
            callStatus.value == 'ringing' ||
            callStatus.value == 'connected' ||
            callStatus.value == 'retrying')) {
      return;
    }

    final sanitizedContacts = emergencyContacts
        .map((contact) => contact.trim())
        .where((contact) => contact.isNotEmpty)
        .toList();

    isStartingCall.value = true;
    activeSessionId.value = sessionId;
    await _persistActiveSession(sessionId);
    callStatus.value = 'initializing';
    callStatusText.value = 'Initializing call...';
    debugPrint('[SosCall] Starting voice flow for session $sessionId');

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user available for SOS calling.');
      }

      if (sanitizedContacts.isEmpty) {
        callStatus.value = 'retrying';
        callStatusText.value = 'Trying alternative communication methods...';
        debugPrint('[SosCall] No emergency contacts available for voice flow.');
        return;
      }

      final profile = await _loadVictimProfile(user.uid);

      for (var attempt = 1; attempt <= _maxVoiceStartAttempts; attempt++) {
        try {
          callStatus.value = attempt == 1 ? 'calling' : 'retrying';
          callStatusText.value = attempt == 1
              ? 'Calling emergency contacts...'
              : 'Call failed, retrying...';

          if (!_backendService.isConfigured) {
            throw Exception('Voice backend base URL is not configured.');
          }

          final payload = await _backendService.startCall(
            sessionId: sessionId,
            userId: user.uid,
            victimName: profile.name,
            victimPhone: profile.phone,
            emergencyContacts: sanitizedContacts,
            latitude: latitude,
            longitude: longitude,
          );
          _applyPayload(payload);
          if (_shouldFallbackToDialer(payload)) {
            debugPrint(
              '[SosCall] Backend returned terminal call state ${payload.status}. Triggering dialer fallback.',
            );
            await _launchDialerFallback(
              emergencyContacts: sanitizedContacts,
              reason: 'backend returned terminal status ${payload.status}',
            );
            return;
          }
          _startPolling(sessionId);
          debugPrint('[SosCall] Voice call started: ${payload.status}');
          return;
        } catch (e) {
          lastCallError.value = 'voice_start_failed';
          debugPrint(
            '[SosCall] Voice start attempt $attempt failed: ${_safeLogMessage(e)}',
          );
          if (attempt < _maxVoiceStartAttempts) {
            await Future<void>.delayed(
              Duration(
                seconds: _voiceRetryBaseDelay.inSeconds * (1 << (attempt - 1)),
              ),
            );
          }
        }
      }

      await _launchDialerFallback(
        emergencyContacts: sanitizedContacts,
        reason: 'voice backend start retries exhausted',
      );
    } catch (e) {
      lastCallError.value = 'voice_flow_failed';
      callStatus.value = 'retrying';
      callStatusText.value = 'Trying alternative communication methods...';
      debugPrint('[SosCall] Failed to start voice call: ${_safeLogMessage(e)}');
      await _launchDialerFallback(
        emergencyContacts: sanitizedContacts,
        reason: 'voice flow exception',
      );
    } finally {
      isStartingCall.value = false;
    }
  }

  Future<void> restoreActiveSessionIfNeeded({String? sessionId}) async {
    if (!_backendService.isConfigured) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      final payload = sessionId != null
          ? await _backendService.getCallStatus(sessionId: sessionId)
          : await _backendService.getActiveCall(userId: user.uid);
      if (payload == null || payload.sessionId.isEmpty) {
        _clearCallState();
        return;
      }
      _applyPayload(payload);
      _startPolling(payload.sessionId);
      debugPrint(
        '[SosCall] Restored active voice session ${payload.sessionId}',
      );
    } catch (e) {
      debugPrint(
        '[SosCall] Could not restore active voice session: ${_safeLogMessage(e)}',
      );
    }
  }

  Future<void> refreshStatus() async {
    final sessionId = activeSessionId.value;
    if (sessionId == null ||
        sessionId.isEmpty ||
        !_backendService.isConfigured) {
      return;
    }

    try {
      final payload = await _backendService.getCallStatus(sessionId: sessionId);
      _applyPayload(payload);
      if (_shouldFallbackToDialer(payload)) {
        await _launchDialerFallback(
          emergencyContacts: await _loadEmergencyContacts(),
          reason: 'backend polling returned terminal status ${payload.status}',
        );
        return;
      }
      debugPrint('[SosCall] Polled voice state: ${payload.status}');
    } catch (e) {
      lastCallError.value = 'voice_poll_failed';
      callStatusText.value = 'Connecting to emergency contacts...';
      debugPrint('[SosCall] Poll failed: ${_safeLogMessage(e)}');
    }
  }

  Future<void> handleSafeConfirmed({required String sessionId}) async {
    if (!_backendService.isConfigured) {
      return;
    }

    try {
      final payload = await _backendService.markSafe(sessionId: sessionId);
      _applyPayload(payload);
      debugPrint('[SosCall] Safe confirmed for session $sessionId');
    } catch (e) {
      debugPrint(
        '[SosCall] Failed to mark call flow safe: ${_safeLogMessage(e)}',
      );
    }
  }

  Future<void> endActiveCallAfterSafe() async {
    final sessionId = activeSessionId.value;
    if (sessionId == null ||
        sessionId.isEmpty ||
        !_backendService.isConfigured) {
      showPostSafeActions.value = false;
      return;
    }

    isEndingCall.value = true;
    try {
      final payload = await _backendService.endCall(sessionId: sessionId);
      _applyPayload(payload);
      showPostSafeActions.value = false;
      debugPrint('[SosCall] Ended active voice call for session $sessionId');
    } catch (e) {
      lastCallError.value = 'voice_end_failed';
      debugPrint('[SosCall] Failed to end active call: ${_safeLogMessage(e)}');
    } finally {
      isEndingCall.value = false;
    }
  }

  void dismissPostSafeActions() {
    showPostSafeActions.value = false;
  }

  Future<void> notifyContactsSafe() async {
    final sosController = Get.isRegistered<SosController>()
        ? Get.find<SosController>()
        : null;
    await sosController?.shareSafeStatus();
  }

  Future<void> syncLocation({
    required String sessionId,
    required double latitude,
    required double longitude,
  }) async {
    if (!_backendService.isConfigured) {
      return;
    }

    try {
      await _backendService.syncLocation(
        sessionId: sessionId,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      debugPrint('[SosCall] Location sync failed: ${_safeLogMessage(e)}');
    }
  }

  void _startPolling(String sessionId) {
    activeSessionId.value = sessionId;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(refreshStatus());
    });
  }

  void _applyPayload(SosCallStatusPayload payload) {
    final shouldClearSession =
        !payload.isCallActive &&
        !payload.canShowPostSafeActions &&
        (payload.status == 'resolved' ||
            payload.status == 'ended' ||
            payload.status == 'idle');

    activeSessionId.value = shouldClearSession ? null : payload.sessionId;
    callStatus.value = payload.status;
    callStatusText.value = payload.statusText.isEmpty
        ? 'Connecting to emergency contacts...'
        : payload.statusText;
    isCallActive.value = payload.isCallActive;
    showPostSafeActions.value = payload.canShowPostSafeActions;
    lastCallError.value = '';
    unawaited(
      _persistActiveSession(shouldClearSession ? null : payload.sessionId),
    );

    if (!payload.isCallActive &&
        (payload.status == 'resolved' ||
            payload.status == 'safe' ||
            payload.status == 'ended' ||
            payload.status == 'idle')) {
      _pollTimer?.cancel();
    }
  }

  Future<void> _launchDialerFallback({
    required List<String> emergencyContacts,
    required String reason,
  }) async {
    final contacts = emergencyContacts
        .map((contact) => contact.trim())
        .where((contact) => contact.isNotEmpty)
        .toList();
    if (contacts.isEmpty) {
      callStatus.value = 'retrying';
      callStatusText.value = 'Trying alternative communication methods...';
      return;
    }

    for (var offset = 0; offset < contacts.length; offset++) {
      final index = (_dialerFallbackIndex + offset) % contacts.length;
      final number = contacts[index];
      final uri = Uri(scheme: 'tel', path: number);

      try {
        callStatus.value = 'dialer_fallback';
        callStatusText.value = 'Calling via device network...';

        if (Platform.isAndroid) {
          final response = await _nativeChannel
              .invokeMethod<Map<dynamic, dynamic>>('launchEmergencyCall', {
                'phoneNumber': number,
              });
          final payload = Map<String, dynamic>.from(response ?? const {});
          if (payload['success'] == true) {
            _dialerFallbackIndex = index + 1;
            debugPrint(
              '[SosCall] Android fallback call launched for $number after $reason. '
              'Mode=${payload['usedActionCall'] == true ? 'ACTION_CALL' : 'ACTION_DIAL'}.',
            );
            return;
          }
        } else if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _dialerFallbackIndex = index + 1;
          debugPrint(
            '[SosCall] Dialer fallback launched for $number after $reason.',
          );
          return;
        }
      } catch (e) {
        debugPrint(
          '[SosCall] Dialer fallback failed for $number: ${_safeLogMessage(e)}',
        );
      }
    }

    callStatus.value = 'retrying';
    callStatusText.value = 'Trying alternative communication methods...';
  }

  Future<_VictimCallProfile> _loadVictimProfile(String uid) async {
    String? phone;
    String name = 'A SafeRoute user';

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      final resolvedName = data?['name']?.toString().trim();
      final resolvedPhone = data?['phone']?.toString().trim();
      if (resolvedName != null && resolvedName.isNotEmpty) {
        name = resolvedName;
      }
      if (resolvedPhone != null && resolvedPhone.isNotEmpty) {
        phone = resolvedPhone;
      }
    } catch (e) {
      debugPrint(
        '[SosCall] Failed to load victim profile: ${_safeLogMessage(e)}',
      );
    }

    final currentUser = _auth.currentUser;
    final displayName = currentUser?.displayName?.trim();
    if (name == 'A SafeRoute user' &&
        displayName != null &&
        displayName.isNotEmpty) {
      name = displayName;
    }

    return _VictimCallProfile(name: name, phone: phone);
  }

  Future<void> _persistActiveSession(String? sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sessionId == null || sessionId.isEmpty) {
      await prefs.remove(_activeCallSessionPrefsKey);
    } else {
      await prefs.setString(_activeCallSessionPrefsKey, sessionId);
    }
  }

  Future<void> _restorePersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_activeCallSessionPrefsKey);
    if (sessionId == null || sessionId.isEmpty) {
      return;
    }
    activeSessionId.value = sessionId;
    callStatusText.value = 'Restoring call status...';
    unawaited(restoreActiveSessionIfNeeded(sessionId: sessionId));
  }

  void _clearCallState() {
    _pollTimer?.cancel();
    activeSessionId.value = null;
    callStatus.value = 'idle';
    callStatusText.value = '';
    isCallActive.value = false;
    showPostSafeActions.value = false;
    lastCallError.value = '';
    unawaited(_persistActiveSession(null));
  }

  String _safeLogMessage(Object error) {
    final message = error.toString();
    return message.length > 220 ? '${message.substring(0, 220)}...' : message;
  }

  bool _shouldFallbackToDialer(SosCallStatusPayload payload) {
    return !payload.isSafe &&
        !payload.isCallActive &&
        !payload.canShowPostSafeActions &&
        (payload.status == 'failed' || payload.status == 'ended');
  }

  Future<List<String>> _loadEmergencyContacts() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const <String>[];
    }

    final contacts = <String>{};
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? const <String, dynamic>{};
      for (var index = 1; index <= 4; index++) {
        final value = data['emergencyContact$index']?.toString().trim();
        if (value != null && value.isNotEmpty) {
          contacts.add(value);
        }
      }
    } catch (e) {
      debugPrint(
        '[SosCall] Failed to load emergency contacts for dialer fallback: ${_safeLogMessage(e)}',
      );
    }

    return contacts.toList();
  }
}

class _VictimCallProfile {
  const _VictimCallProfile({required this.name, required this.phone});

  final String name;
  final String? phone;
}
