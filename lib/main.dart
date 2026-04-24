import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/auth_wrapper.dart';
import 'controllers/auth_controller.dart';
import 'controllers/rescue_invite_controller.dart';
import 'controllers/rescue_stats_controller.dart';
import 'controllers/sos_listener_controller.dart';
import 'services/background_shake_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: "AIzaSyAcMMheGmuREjLO5VKAieWN3iqYfQwdP94",
        appId: "1:771521687360:android:a9d36e102c6b33646a94a5",
        messagingSenderId: "771521687360",
        projectId: "saferoute-55bb6",
        storageBucket: "saferoute-55bb6.firebasestorage.app",
      ),
    );
  } catch (e) {
    debugPrint(
      "Firebase Initialization Failed natively. Ensure google-services.json is mapped: $e",
    );
  }

  await initializeBackgroundService();

  runApp(const SafeRouteApp());
}

class SafeRouteApp extends StatelessWidget {
  const SafeRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(AuthController());
    Get.put(SosListenerController());
    Get.put(RescueInviteController());
    Get.put(RescueStatsController());
    return GetMaterialApp(
      title: 'SafeRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      themeMode: ThemeMode.system,
      home: const AuthWrapper(),
    );
  }
}
