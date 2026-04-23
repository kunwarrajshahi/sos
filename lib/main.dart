import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/auth_wrapper.dart';
import 'controllers/auth_controller.dart';
import 'controllers/sos_listener_controller.dart';
import 'services/background_shake_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
options:FirebaseOptions(
  apiKey: "AIzaSyBs_iTv31hzGIMkJh3IhnrNyIS0iIi8F0E",
  appId: "1:737992185007:android:26b3a31588345bcc18b05a",
  messagingSenderId: "737992185007",
  projectId: "shee-a0c0b",
  storageBucket: "shee-a0c0b.firebasestorage.app",
)
    );
  } catch (e) {
    debugPrint("Firebase Initialization Failed natively. Ensure google-services.json is mapped: $e");
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
    return GetMaterialApp(
      title: 'SafeRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const AuthWrapper(),
    );
  }
}
