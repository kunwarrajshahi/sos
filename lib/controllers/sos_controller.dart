import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/location_service.dart';
import 'package:telephony_fix/telephony.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'contact_controller.dart';
class SosController extends GetxController {
  final Telephony telephony = Telephony.instance;
  var isLoading = false.obs;
  var isCountdown = false.obs;
  var countdownSeconds = 10.obs; // INCREASED TO 10 SECONDS
  var isSent = false.obs;
  var isActiveBroadcast = false.obs;

  var isShakeSOSActive = false.obs;
  
  String generatedMessage = '';
  Timer? _timer;
  Timer? _fallbackCallTimer;

  @override
  void onInit() {
    super.onInit();
    _loadPrefs();
    FlutterBackgroundService().on('sos_triggered').listen((event) { 
      if (!isCountdown.value && !isSent.value) {
         initiateSOSWorkflow();
      }
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    isShakeSOSActive.value = prefs.getBool('is_shake_active') ?? false;
    generatedMessage = prefs.getString('sos_msg') ?? '';
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('active_sos').doc(uid).get();
        if (doc.exists && doc.data()?['active'] == true) {
           isSent.value = true;
           isActiveBroadcast.value = true;
        }
      } catch (e) {
        debugPrint("Failed to restore SOS state: \$e");
      }
    }
    
    bool isPending = prefs.getBool('is_sos_pending') ?? false;
    if (isPending) {
       int targetTime = prefs.getInt('sos_execute_at') ?? 0;
       int remainder = ((targetTime - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
       
       if (remainder > 0 && remainder <= 10) {
           initiateSOSWorkflow(initialCountdown: remainder);
           
           WidgetsBinding.instance.addPostFrameCallback((_) {
               _showCancelDialogAggressive();
           });
       } else {
           await prefs.setBool('is_sos_pending', false);
       }
    }
  }

  void _showCancelDialogAggressive() {
     if (Get.isDialogOpen == true) return;
     Get.defaultDialog(
        title: "🚨 SOS COUNTDOWN 🚨",
        titleStyle: const TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold),
        barrierDismissible: false,
        onWillPop: () async => false, // Prevent physical back buttons
        content: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Hardware Shake Detected!\nEmergency protocols triggering in:", textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Text("${countdownSeconds.value}", style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 20),
          ]
        )),
        confirm: ElevatedButton(
           style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)),
           onPressed: () {
              cancelSOS();
              if (Get.isDialogOpen == true) Get.back();
           },
           child: const Text("CANCEL SOS", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        )
     );
  }

  @override
  void onClose() {
    _timer?.cancel();
    _fallbackCallTimer?.cancel();
    super.onClose();
  }

  void toggleShakeSOS(bool value) async {
    isShakeSOSActive.value = value;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_shake_active', value);
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
       await prefs.setString('user_uid', uid);
    }
    
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    
    if (value) {
       if (await Permission.ignoreBatteryOptimizations.isDenied) {
         await Permission.ignoreBatteryOptimizations.request();
       }
       if (await Permission.systemAlertWindow.isDenied) {
         await Permission.systemAlertWindow.request();
       }
       if (!isRunning) {
         await service.startService();
       }
    } else {
       if (isRunning) {
         service.invoke("stopService");
       }
    }
  }

  void initiateSOSWorkflow({int? initialCountdown}) async {
    isCountdown.value = true;
    countdownSeconds.value = initialCountdown ?? 10;
    isSent.value = false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_sos_pending', true);
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds.value > 1) {
        countdownSeconds.value--;
      } else {
        timer.cancel();
        if (Get.isDialogOpen == true) Get.back();
        executeSOS();
      }
    });
  }

  Future<void> cancelSOS() async {
    _timer?.cancel();
    _fallbackCallTimer?.cancel();
    isCountdown.value = false;
    countdownSeconds.value = 10;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_sos_pending', false);
  }

  Future<void> executeSOS() async {
    isCountdown.value = false;
    isLoading.value = true;

    try {
      Position position = await LocationService.getCurrentPosition();
      String lat = position.latitude.toString();
      String lng = position.longitude.toString();
      
      generatedMessage = "I am in danger! My location:\nLatitude: $lat\nLongitude: $lng\nMap Link: https://www.google.com/maps/search/?api=1&query=$lat,$lng";
      await (await SharedPreferences.getInstance()).setString('sos_msg', generatedMessage);
      
      final contactCtrl = Get.isRegistered<ContactController>() 
          ? Get.find<ContactController>() 
          : Get.put(ContactController());
          
      List<String> contactsList = [];
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (doc.exists) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            if (data['emergencyContact1'] != null && data['emergencyContact1'].toString().isNotEmpty) {
               contactsList.add(data['emergencyContact1']);
            }
            if (data['emergencyContact2'] != null && data['emergencyContact2'].toString().isNotEmpty) {
               contactsList.add(data['emergencyContact2']);
            }
          }
        }
      } catch (e) {
        debugPrint("Firestore fetch error: \$e");
      }
      
      if (contactsList.isEmpty) {
        contactsList = List<String>.from(contactCtrl.contacts);
      }

      if (contactsList.isEmpty) {
        Get.snackbar("Warning", "No emergency contacts found.", 
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      } else {
        bool smsGranted = await contactCtrl.checkAndRequestSmsPermission();
        if (smsGranted) {
          Get.snackbar("Sending SOS...", "Dispatching SMS to contacts...",
            snackPosition: SnackPosition.TOP,
          );
          
          for (String number in contactsList) {
             sendSOSMessage(number);
          }
          
          Get.snackbar("SOS sent successfully", "Messages dispatched directly to contacts.",
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        } else {
          Get.snackbar(
            "SOS Failed", 
            "SMS Permission not granted.",
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.black87,
            colorText: Colors.redAccent,
            duration: const Duration(seconds: 4),
          );
        }
      }

      // Trigger Heavy SOS Vibrations natively
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
      }
      
      // Broadcast SOS to nearby users via Firestore
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        await FirebaseFirestore.instance.collection('active_sos').doc(uid).set({
          'uid': uid,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'active': true,
          'responders': [],
        });
        
        Get.snackbar(
          "Broadcast Active", 
          "SOS notification dispatched to nearby users.",
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.blueAccent,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
        
        _fallbackCallTimer?.cancel();
        _fallbackCallTimer = Timer(const Duration(minutes: 5), () => _triggerFallbackCall(uid));
      } catch (e) {
        debugPrint("Error broadcasting SOS: \$e");
      }
      
      isLoading.value = false;
      isSent.value = true; // Triggers UI to pop full screen alert overlay
      isActiveBroadcast.value = true;

    } catch (e) {
      isLoading.value = false;
      String errorMsg = e.toString().replaceFirst('Exception: ', '');
      Get.snackbar(
        "SOS Failed", 
        errorMsg,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black87,
        colorText: Colors.redAccent,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void sendSOSMessage(String phoneNumber) {
    if (generatedMessage.isNotEmpty) {
      telephony.sendSms(
        to: phoneNumber,
        message: generatedMessage,
      ).catchError((e) {
        debugPrint("Error sending SMS to $phoneNumber: $e");
      });
    }
  }

  Future<void> copyMessage() async {
    if (generatedMessage.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: generatedMessage));
      Get.snackbar(
        "Copied!", 
        "Emergency link stored to clipboard.", 
        snackPosition: SnackPosition.TOP, 
        backgroundColor: Colors.green.shade700, 
        colorText: Colors.white,
        duration: const Duration(seconds: 2)
      );
    }
  }

  Future<void> shareSOS() async {
    if (generatedMessage.isNotEmpty) {
      await Share.share(generatedMessage, subject: "URGENT SOS");
    }
  }

  void closeAlert() {
    isSent.value = false;
    generatedMessage = '';
  }

  Future<void> stopActiveSOS() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('active_sos').doc(uid).delete();
      }
      
      _fallbackCallTimer?.cancel();
      isSent.value = false;
      isActiveBroadcast.value = false;
      generatedMessage = '';
      
      Get.snackbar(
        "SOS Cancelled", 
        "Your emergency broadcast has been successfully stopped.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint("Error stopping SOS: \$e");
      Get.snackbar(
        "Error", 
        "Failed to stop SOS. Please try again.",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _triggerFallbackCall(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('active_sos').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final responders = data['responders'] as List<dynamic>? ?? [];
        if (responders.isEmpty) {
           final contactCtrl = Get.isRegistered<ContactController>() ? Get.find<ContactController>() : Get.put(ContactController());
           if (contactCtrl.contacts.isNotEmpty) {
             final number = contactCtrl.contacts.first;
             final Uri telUri = Uri(scheme: 'tel', path: number);
             if (await canLaunchUrl(telUri)) {
               await launchUrl(telUri);
             } else {
               debugPrint('Could not launch \$telUri');
             }
           }
        }
      }
    } catch (e) {
      debugPrint("Fallback Call Error: \$e");
    }
  }
}
