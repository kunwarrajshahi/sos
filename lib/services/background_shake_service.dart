import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'safe_route_sos_channel', // id
    'SafeRoute SOS Service', // name
    description: 'Actively monitors hardware sensors for SOS shakes even when locked.',
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
    description: 'Alerts you instantly when a user triggers an emergency nearby.',
    importance: Importance.max,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(wakeChannel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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

  // Initialize Firebase in Background Isolate
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBs_iTv31hzGIMkJh3IhnrNyIS0iIi8F0E",
        appId: "1:737992185007:android:26b3a31588345bcc18b05a",
        messagingSenderId: "737992185007",
        projectId: "shee-a0c0b",
        storageBucket: "shee-a0c0b.firebasestorage.app",
      )
    );
  } catch (e) {
    debugPrint("Firebase already initialized or failed: \$e");
  }

  // --- NEARBY SOS LISTENER IN BACKGROUND ---
  final List<String> _notifiedSosList = [];

  FirebaseFirestore.instance
      .collection('active_sos')
      .where('active', isEqualTo: true)
      .snapshots()
      .listen((snapshot) async {
    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        final data = change.doc.data();
        if (data == null) continue;

        final uid = data['uid'] as String?;
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;

        if (uid == null || lat == null || lng == null) continue;

        final prefs = await SharedPreferences.getInstance();
        final currentUserId = prefs.getString('user_uid');
        if (currentUserId != null && uid == currentUserId) continue;

        if (_notifiedSosList.contains(uid)) continue;

        try {
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium)
          );
          
          double distanceInMeters = Geolocator.distanceBetween(
             position.latitude, position.longitude, lat, lng
          );

          if (distanceInMeters <= 5000) {
            _notifiedSosList.add(uid);
            
            final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
            await plugin.show(
              id: uid.hashCode, // Unique ID per user
              title: '🚨 NEARBY DANGER ALERT',
              body: 'Someone needs help \${(distanceInMeters / 1000).toStringAsFixed(1)}km away! Tap to navigate.',
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'sos_nearby_channel_v1',
                  'Nearby SOS Alerts',
                  channelDescription: 'Alerts you instantly when a user triggers an emergency nearby.',
                  importance: Importance.max,
                  priority: Priority.max,
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint("Background SOS Listener Error: \$e");
        }
      }
    }
  });

  List<DateTime> _recentShakes = [];
  bool _isCountdownActive = false;

  userAccelerometerEventStream().listen((UserAccelerometerEvent event) async {
    double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

    if (magnitude > 15.0) {
      final now = DateTime.now();
      _recentShakes.add(now);

      // Keep only shakes within the last 1.0 seconds
      _recentShakes.removeWhere((timestamp) => now.difference(timestamp).inMilliseconds > 1000);

      // Trigger if there are 3 shakes in exactly 1 second
      if (_recentShakes.length >= 3 && !_isCountdownActive) {
        _isCountdownActive = true;
        _recentShakes.clear();

        // Trigger Heavy Initial Vibration marking SOS detection
        bool? hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(pattern: [500, 500, 500]);
        }

        final prefs = await SharedPreferences.getInstance();
        final executeAt = DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch;
        await prefs.setInt('sos_execute_at', executeAt);
        await prefs.setBool('is_sos_pending', true);

        // Notify Foreground UI (if open)
        service.invoke('sos_triggered', {'executeAt': executeAt});

        // Natively force Android to wake screen and launch MainActivity bypassing Lock Screen
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
        
        const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
        const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
        await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

        await flutterLocalNotificationsPlugin.show(
          id: 777,
          title: '🚨 URGENT: SOS COUNTDOWN STARTED',
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
        
        // Force aggressive startup via Deep Link bypass using system broadcast
        try {
          await launchUrl(
            Uri.parse('saferoute://sos'),
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint("Deep link bypass failed: \$e");
        }

        // 10 Second Background Timer Failsafe
        Timer(const Duration(seconds: 10), () async {
          _isCountdownActive = false;
          // Re-check prefs. If user cancelled it from UI, 'is_sos_pending' will be false.
          await prefs.reload();
          bool isPending = prefs.getBool('is_sos_pending') ?? false;

          if (isPending) {
            // FIRE BACKGROUND ALARM 🚨
            await _executeBackgroundSOS();
            await prefs.setBool('is_sos_pending', false);
          }
        });
      }
    }
  });
}

Future<void> _executeBackgroundSOS() async {
  try {
    // Attempt aggressive vibration
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [1000, 1000, 1000, 1000]);
    }

    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('user_uid'); // Make sure we save this in Auth!
    
    if (uid == null || uid.isEmpty) return;

    // Fetch raw hardware GPS
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best)
    );

    await FirebaseFirestore.instance.collection('active_sos').doc(uid).set({
      'uid': uid,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'active': true,
      'responders': [],
    });
    
  } catch (e) {
    debugPrint("Background SOS Execution Error: \$e");
  }
}
