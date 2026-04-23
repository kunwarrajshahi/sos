import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class ContactController extends GetxController {
  var contacts = <String>[].obs;
  var isSmsPermissionGranted = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadContacts();
    // Delay to ensure UI is ready before prompting natively
    Future.delayed(const Duration(seconds: 2), () {
      checkAndRequestSmsPermission();
    });
  }

  Future<bool> checkAndRequestSmsPermission() async {
    // Check current status first
    PermissionStatus currentStatus = await Permission.sms.status;

    if (currentStatus.isGranted) {
      isSmsPermissionGranted.value = true;
      return true;
    }

    if (currentStatus.isPermanentlyDenied) {
      _showPermanentlyDeniedDialog();
      return false;
    }

    // Since Android 11+, we need user interaction to show the native permission dialog.
    // If not granted, we prompt the user with OUR dialog first.
    Get.defaultDialog(
      title: "Permission Required",
      middleText:
          "SMS permission is strictly needed to directly send emergency SOS alerts to your contacts. Please click 'Grant' to allow this permission.",
      textConfirm: "Grant",
      confirmTextColor: Colors.white,
      onConfirm: () async {
        Get.back(); // close our dialog

        // NOW we request the native permission (tied to user tap)
        Map<Permission, PermissionStatus> statuses = await [
          Permission.sms,
          Permission.phone,
        ].request();

        PermissionStatus newStatus =
            statuses[Permission.sms] ?? PermissionStatus.denied;
        isSmsPermissionGranted.value = newStatus.isGranted;

        if (newStatus.isPermanentlyDenied) {
          _showPermanentlyDeniedDialog();
        } else if (newStatus.isDenied) {
          Get.snackbar(
            "Permission Denied",
            "SOS directly via SMS will not work unless permitted.",
          );
        }
      },
      textCancel: "Cancel",
    );

    return false;
  }

  void _showPermanentlyDeniedDialog() {
    Get.defaultDialog(
      title: "Permission Required",
      middleText:
          "SMS permission is permanently denied. Please enable it in App Settings to use the SOS feature to send direct messages.",
      textConfirm: "Open Settings",
      onConfirm: () {
        openAppSettings();
        Get.back();
      },
      textCancel: "Cancel",
    );
  }

  Future<void> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    contacts.value = prefs.getStringList('emergency_contacts') ?? [];
  }

  Future<void> addContact(String phoneNumber) async {
    if (phoneNumber.isNotEmpty && !contacts.contains(phoneNumber)) {
      contacts.add(phoneNumber);
      await _saveContacts();
      Get.snackbar("Success", "Contact added successfully");
    }
  }

  Future<void> removeContact(String phoneNumber) async {
    contacts.remove(phoneNumber);
    await _saveContacts();
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emergency_contacts', contacts);
  }
}
