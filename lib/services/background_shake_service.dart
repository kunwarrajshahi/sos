import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

const double _strongShakeMagnitudeThreshold = 18.5;
const double _axisDirectionThreshold = 11.0;
const int _requiredStrongOscillations = 3;
const int _shakeSequenceWindowMs = 1800;
const int _minShakeGapMs = 120;
const int _maxShakeGapMs = 700;
const int _sosCooldownMs = 10000;
const int _cancelCountdownSeconds = 3;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'safe_route_sos_channel',
    'SafeRoute SOS Service',
    description:
        'Actively monitors hardware sensors for SOS shakes even when locked.',
    importance: Importance.high,
  );

  const AndroidNotificationChannel wakeChannel = AndroidNotificationChannel(
    'sos_wake_channel_v1',
    'SOS Critical Wake Lock',
    description: 'Wakes the screen when shaking is detected natively',
    importance: Importance.max,
  );

  const AndroidNotificationChannel nearbyChannel = AndroidNotificationChannel(
    'sos_nearby_channel_v1',
    'Nearby SOS Alerts',
    description:
        'Alerts you instantly when a user triggers an emergency nearby.',
    importance: Importance.max,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(wakeChannel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(nearbyChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'safe_route_sos_channel',
      initialNotificationTitle: 'SafeRoute Active',
      initialNotificationContent: 'Monitoring hardware shakes for emergencies.',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBs_iTv31hzGIMkJh3IhnrNyIS0iIi8F0E",
        appId: "1:737992185007:android:26b3a31588345bcc18b05a",
        messagingSenderId: "737992185007",
        projectId: "shee-a0c0b",
        storageBucket: "shee-a0c0b.firebasestorage.app",
      ),
    );
  } catch (e) {
    debugPrint("Firebase already initialized or failed: $e");
  }

  final List<String> notifiedSosList = [];

  FirebaseFirestore.instance
      .collection('active_sos')
      .where('active', isEqualTo: true)
      .snapshots()
      .listen((snapshot) async {
        for (var change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) {
            continue;
          }

          final data = change.doc.data();
          if (data == null) {
            continue;
          }

          final uid = data['uid'] as String?;
          final lat = data['latitude'] as double?;
          final lng = data['longitude'] as double?;

          if (uid == null || lat == null || lng == null) {
            continue;
          }

          final prefs = await SharedPreferences.getInstance();
          final currentUserId = prefs.getString('user_uid');
          if (currentUserId != null && uid == currentUserId) {
            continue;
          }

          if (notifiedSosList.contains(uid)) {
            continue;
          }

          try {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
              ),
            );

            final distanceInMeters = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              lat,
              lng,
            );

            if (distanceInMeters <= 5000) {
              notifiedSosList.add(uid);

              final plugin = FlutterLocalNotificationsPlugin();
              await plugin.show(
                id: uid.hashCode,
                title: 'ðŸš¨ NEARBY DANGER ALERT',
                body:
                    'Someone needs help ${(distanceInMeters / 1000).toStringAsFixed(1)}km away! Tap to navigate.',
                notificationDetails: const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'sos_nearby_channel_v1',
                    'Nearby SOS Alerts',
                    channelDescription:
                        'Alerts you instantly when a user triggers an emergency nearby.',
                    importance: Importance.max,
                    priority: Priority.max,
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint("Background SOS Listener Error: $e");
          }
        }
      });

  final detector = _EmergencyShakeDetector();
  bool isCountdownActive = false;
  StreamSubscription<UserAccelerometerEvent>? accelerometerSubscription;

  service.on('stopService').listen((event) {
    accelerometerSubscription?.cancel();
    detector.reset();
    service.stopSelf();
  });

  accelerometerSubscription = userAccelerometerEventStream().listen((
    UserAccelerometerEvent event,
  ) async {
    if (isCountdownActive) {
      return;
    }

    final detected = detector.register(event, DateTime.now());
    if (!detected) {
      return;
    }

    isCountdownActive = true;

    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [300, 180, 300]);
    }

    final prefs = await SharedPreferences.getInstance();
    final executeAt = DateTime.now()
        .add(const Duration(seconds: _cancelCountdownSeconds))
        .millisecondsSinceEpoch;
    await prefs.setInt('sos_execute_at', executeAt);
    await prefs.setBool('is_sos_pending', true);

    service.invoke('sos_triggered', {'executeAt': executeAt});

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );

    await flutterLocalNotificationsPlugin.show(
      id: 777,
      title: 'ðŸš¨ URGENT: SOS COUNTDOWN STARTED',
      body: 'Tap to open and cancel if this was a mistake.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'sos_wake_channel_v1',
          'SOS Critical Wake Lock',
          channelDescription: 'Wakes the screen when shaking is detected natively',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          ongoing: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );

    try {
      await launchUrl(
        Uri.parse('saferoute://sos'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint("Deep link bypass failed: $e");
    }

    Timer(const Duration(seconds: _cancelCountdownSeconds), () async {
      isCountdownActive = false;
      detector.markTriggerHandled(DateTime.now());

      await prefs.reload();
      final isPending = prefs.getBool('is_sos_pending') ?? false;

      if (isPending) {
        await _executeBackgroundSOS();
        await prefs.setBool('is_sos_pending', false);
      }
    });
  });
}

Future<void> _executeBackgroundSOS() async {
  try {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [1000, 1000, 1000, 1000]);
    }

    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_uid');
    if (uid == null || uid.isEmpty) {
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );

    await FirebaseFirestore.instance.collection('active_sos').doc(uid).set({
      'sessionId': uid,
      'uid': uid,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'victim': {
        'lat': position.latitude,
        'lng': position.longitude,
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastUpdatedMs': DateTime.now().millisecondsSinceEpoch,
      },
      'timestamp': FieldValue.serverTimestamp(),
      'startedAtMs': DateTime.now().millisecondsSinceEpoch,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'active': true,
      'status': 'active',
      'responders': [],
      'respondersMeta': {},
      'inviteTokens': {},
      'invitedHelpers': {},
      'responderCount': 0,
      'rescueState': 'waiting_for_responder',
    });
  } catch (e) {
    debugPrint("Background SOS Execution Error: $e");
  }
}

class _EmergencyShakeDetector {
  final List<DateTime> _shakeMoments = [];
  int _lastAxisDirection = 0;
  DateTime? _lastShakeAt;
  DateTime? _cooldownUntil;

  bool register(UserAccelerometerEvent event, DateTime now) {
    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) {
      return false;
    }

    final magnitude = sqrt(
      pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
    );
    if (magnitude < _strongShakeMagnitudeThreshold) {
      _prune(now);
      return false;
    }

    final dominantAxisValue = _dominantAxisValue(event);
    if (dominantAxisValue.abs() < _axisDirectionThreshold) {
      return false;
    }

    final direction = dominantAxisValue.isNegative ? -1 : 1;
    if (_lastAxisDirection != 0 && direction == _lastAxisDirection) {
      return false;
    }

    if (_lastShakeAt != null) {
      final gapMs = now.difference(_lastShakeAt!).inMilliseconds;
      if (gapMs < _minShakeGapMs) {
        return false;
      }
      if (gapMs > _maxShakeGapMs) {
        reset();
      }
    }

    _lastAxisDirection = direction;
    _lastShakeAt = now;
    _shakeMoments.add(now);
    _prune(now);

    if (_shakeMoments.length >= _requiredStrongOscillations) {
      final sequenceDuration =
          _shakeMoments.last.difference(_shakeMoments.first).inMilliseconds;
      if (sequenceDuration <= _shakeSequenceWindowMs) {
        return true;
      }
      _shakeMoments.removeAt(0);
    }

    return false;
  }

  void markTriggerHandled(DateTime now) {
    _cooldownUntil = now.add(const Duration(milliseconds: _sosCooldownMs));
    reset(keepCooldown: true);
  }

  void reset({bool keepCooldown = false}) {
    _shakeMoments.clear();
    _lastAxisDirection = 0;
    _lastShakeAt = null;
    if (!keepCooldown) {
      _cooldownUntil = null;
    }
  }

  void _prune(DateTime now) {
    _shakeMoments.removeWhere(
      (timestamp) =>
          now.difference(timestamp).inMilliseconds > _shakeSequenceWindowMs,
    );
  }

  double _dominantAxisValue(UserAccelerometerEvent event) {
    final values = [event.x, event.y, event.z];
    values.sort((a, b) => b.abs().compareTo(a.abs()));
    return values.first;
  }
}
