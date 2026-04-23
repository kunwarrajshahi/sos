import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/map_screen.dart';
import '../screens/login_screen.dart';
import 'contact_controller.dart';

class AuthController extends GetxController {
  static AuthController instance = Get.find();
  
  late Rx<User?> _user;
  FirebaseAuth auth = FirebaseAuth.instance;
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  @override
  void onReady() {
    super.onReady();
    _user = Rx<User?>(auth.currentUser);
    _user.bindStream(auth.userChanges());
    ever(_user, _initialScreen);
  }

  // Navigate according to auth state changes seamlessly
  _initialScreen(User? user) {
    if (user == null) {
      Get.offAll(() => const LoginScreen());
    } else {
      _syncUserConstraints(user.uid);
      Get.offAll(() => const MapScreen());
    }
  }

  // Bind emergency contacts into SharedPreferences for native SOS execution
  Future<void> _syncUserConstraints(String uid) async {
    try {
      DocumentSnapshot doc = await firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<String> userContacts = [];
        if (data['emergencyContact1'] != null && data['emergencyContact1'].toString().isNotEmpty) {
           userContacts.add(data['emergencyContact1']);
        }
        if (data['emergencyContact2'] != null && data['emergencyContact2'].toString().isNotEmpty) {
           userContacts.add(data['emergencyContact2']);
        }
        
        // Push aggressively back into SharedPreferences 
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('emergency_contacts', userContacts);
        
        // Dynamically invoke ContactController if already alive
        if (Get.isRegistered<ContactController>()) {
           Get.find<ContactController>().loadContacts();
        }
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  Future<void> register(String name, String email, String password, String phone, String ec1, String ec2) async {
    try {
      UserCredential cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      // Immediately hydrate the Firestore blueprint for this UID
      await firestore.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'emergencyContact1': ec1,
        'emergencyContact2': ec2,
        'createdAt': FieldValue.serverTimestamp()
      });
      Get.snackbar(
        "Account Created", 
        "Welcome $name!", 
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white
      );
    } catch (e) {
      Get.snackbar(
        "Registration Failed", 
        e.toString().replaceFirst(RegExp(r'\[.*\] '), ''), 
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.redAccent,
        colorText: Colors.white
      );
    }
  }

  Future<void> login(String email, String password) async {
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      Get.snackbar(
        "Login Failed", 
        e.toString().replaceFirst(RegExp(r'\[.*\] '), ''), 
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.redAccent,
        colorText: Colors.white
      );
    }
  }

  Future<void> logout() async {
    await auth.signOut();
  }
}
