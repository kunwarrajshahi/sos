import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';
import '../services/location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'contact_controller.dart';
import 'history_controller.dart';
import 'rescue_invite_controller.dart';
import 'sos_listener_controller.dart';
import 'sos_settings_controller.dart';

class SosController extends GetxController {
  static const int _sosFreshnessWindowMs = 15 * 60 * 1000;
  static const String _globalStatsDocPath = 'stats/global';
  static const Duration _smsSendGap = Duration(seconds: 3);
  static const Duration _smsRetryGap = Duration(seconds: 3);
  static const int _smsMaxAttemptsPerContact = 2;
  static const MethodChannel _smsChannel = MethodChannel('safe_route/sms');
  static const String _preferredSmsSubscriptionPrefsKey =
      'preferred_sms_subscription_id';

  var isLoading = false.obs;
  var isCountdown = false.obs;
  var countdownSeconds = 10.obs; // INCREASED TO 10 SECONDS
  var isSent = false.obs;
  var isActiveBroadcast = false.obs;
  var isCompletingRescue = false.obs;
  var isSendingEmergencyAlerts = false.obs;

  var isShakeSOSActive = false.obs;
  var smsStatusMessage = 'SOS idle'.obs;
  var smsRetryStatus = ''.obs;
  var smsSentCount = 0.obs;
  var smsFailedCount = 0.obs;
  var smsTotalCount = 0.obs;
  final RxnInt selectedSmsSubscriptionId = RxnInt();
  final availableSmsSubscriptions = <SmsSubscriptionInfo>[].obs;

  String generatedMessage = '';
  Timer? _timer;
  Timer? _fallbackCallTimer;

  @override
  void onInit() {
    super.onInit();
    _loadPrefs();
    FlutterBackgroundService().on('sos_triggered').listen((event) {
      if (!isCountdown.value && !isSent.value) {
        final executeAt = event?['executeAt'];
        if (executeAt is int) {
          final remainder =
              ((executeAt - DateTime.now().millisecondsSinceEpoch) / 1000)
                  .ceil();
          initiateSOSWorkflow(
            initialCountdown: remainder > 0 ? remainder : 3,
          );
        } else {
          initiateSOSWorkflow(initialCountdown: 3);
        }
      }
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    isShakeSOSActive.value = prefs.getBool('is_shake_active') ?? false;
    generatedMessage = prefs.getString('sos_msg') ?? '';
    selectedSmsSubscriptionId.value = prefs.getInt(
      _preferredSmsSubscriptionPrefsKey,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('active_sos')
            .doc(uid)
            .get();
        if (doc.exists &&
            doc.data()?['active'] == true &&
            doc.data()?['status'] != 'completed') {
          final data = doc.data();
          final startedAtMs = _extractSosTimestampMs(data);
          final isFresh = startedAtMs == null
              ? true
              : DateTime.now().millisecondsSinceEpoch - startedAtMs <=
                  _sosFreshnessWindowMs;

          if (isFresh) {
            isSent.value = true;
            isActiveBroadcast.value = true;
          } else {
            await FirebaseFirestore.instance
                .collection('active_sos')
                .doc(uid)
                .delete();
          }
        }
      } catch (e) {
        debugPrint("Failed to restore SOS state: \$e");
      }
    }

    bool isPending = prefs.getBool('is_sos_pending') ?? false;
    if (isPending) {
      int targetTime = prefs.getInt('sos_execute_at') ?? 0;
      int remainder =
          ((targetTime - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();

      if (remainder > 0 && remainder <= 10) {
        initiateSOSWorkflow(initialCountdown: remainder);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCancelDialogAggressive();
        });
      } else {
        await prefs.setBool('is_sos_pending', false);
      }
    }

    await refreshSmsSubscriptions();
  }

  void _showCancelDialogAggressive() {
    if (Get.isDialogOpen == true) return;
    Get.defaultDialog(
      title: "🚨 SOS COUNTDOWN 🚨",
      titleStyle: const TextStyle(
        color: Colors.redAccent,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      barrierDismissible: false,
      onWillPop: () async => false, // Prevent physical back buttons
      content: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Hardware Shake Detected!\nEmergency protocols triggering in:",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            Text(
              "${countdownSeconds.value}",
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      confirm: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: () {
          cancelSOS();
          if (Get.isDialogOpen == true) Get.back();
        },
        child: const Text(
          "CANCEL SOS",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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
    if (
        isLoading.value ||
        isSendingEmergencyAlerts.value ||
        isCountdown.value ||
        isActiveBroadcast.value) {
      Get.snackbar(
        "SOS In Progress",
        "Emergency processing is already running.",
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final settings = SosSettingsController.instanceOrCreate();
    countdownSeconds.value =
        initialCountdown ?? settings.activationDelaySeconds.value;
    isSent.value = false;

    if (countdownSeconds.value <= 0) {
      isCountdown.value = false;
      await executeSOS();
      return;
    }

    isCountdown.value = true;

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

  bool canTriggerSosNow() {
    return !(isLoading.value ||
        isSendingEmergencyAlerts.value ||
        isCountdown.value ||
        isActiveBroadcast.value);
  }

  Future<bool> triggerAutoRouteDeviationSOS({
    required double deviationMeters,
  }) async {
    if (!canTriggerSosNow()) {
      return false;
    }

    await HistoryController.instanceOrCreate().recordJourneyEvent(
      title: 'Auto SOS Triggered',
      subtitle:
          'Route deviation detected at ${deviationMeters.toStringAsFixed(0)}m',
      metadata: {
        'triggerSource': 'auto_route_deviation',
        'deviationMeters': deviationMeters,
      },
    );
    initiateSOSWorkflow(initialCountdown: 0);
    return true;
  }

  Future<void> cancelSOS() async {
    final settings = SosSettingsController.instanceOrCreate();
    _timer?.cancel();
    _fallbackCallTimer?.cancel();
    isCountdown.value = false;
    countdownSeconds.value = settings.activationDelaySeconds.value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_sos_pending', false);
  }

  Future<void> executeSOS() async {
    if (
        isLoading.value ||
        isActiveBroadcast.value) {
      return;
    }

    isCountdown.value = false;
    isLoading.value = true;
    _resetSmsStatus();

    try {
      final position = await LocationService.getCurrentPosition();
      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);

      final contactCtrl = Get.isRegistered<ContactController>()
          ? Get.find<ContactController>()
          : ContactController.instanceOrCreate();

      final contactsList = await _loadEmergencyContacts(contactCtrl);
      smsTotalCount.value = contactsList.length;

      // Trigger Heavy SOS Vibrations natively
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
      }

      // Broadcast SOS to nearby users via Firestore
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      try {
        await FirebaseFirestore.instance.collection('active_sos').doc(uid).set({
          'sessionId': uid,
          'uid': uid,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'victim': {
            'lat': position.latitude,
            'lng': position.longitude,
            'lastUpdated': FieldValue.serverTimestamp(),
            'lastUpdatedMs': nowMs,
          },
          'timestamp': FieldValue.serverTimestamp(),
          'startedAtMs': nowMs,
          'updatedAtMs': nowMs,
          'active': true,
          'status': 'active',
          'responders': [],
          'respondersMeta': {},
          'inviteTokens': {},
          'invitedHelpers': {},
          'responderCount': 0,
          'rescueState': 'waiting_for_responder',
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
        _fallbackCallTimer = Timer(
          const Duration(minutes: 5),
          () => _triggerFallbackCall(uid),
        );
      } catch (e) {
        debugPrint("Error broadcasting SOS: \$e");
      }

      generatedMessage = await _buildSosMessage(
        lat: lat,
        lng: lng,
        sessionId: uid,
      );
      await (await SharedPreferences.getInstance()).setString(
        'sos_msg',
        generatedMessage,
      );

      isLoading.value = false;
      isSent.value = true;
      isActiveBroadcast.value = true;
      await HistoryController.instanceOrCreate().recordSos(
        status: 'Sent',
        locationLabel: 'Emergency SOS dispatched',
      );

      unawaited(_dispatchEmergencySmsInBackground(
        contactsList: contactsList,
        contactCtrl: contactCtrl,
      ));
    } catch (e) {
      isLoading.value = false;
      smsStatusMessage.value = 'Emergency sending failed';
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

  Future<List<String>> _loadEmergencyContacts(
    ContactController contactCtrl,
  ) async {
    final contacts = <String>[];
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          for (var i = 1; i <= 4; i++) {
            final value = data['emergencyContact$i'];
            if (value != null && value.toString().trim().isNotEmpty) {
              contacts.add(value.toString().trim());
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Firestore fetch error: $e");
    }

    if (contacts.isEmpty) {
      contacts.addAll(contactCtrl.contacts.map((contact) => contact.trim()));
    }

    return contacts.toSet().where((contact) => contact.isNotEmpty).toList();
  }

  Future<String> _buildSosMessage({
    required String lat,
    required String lng,
    String? sessionId,
  }) async {
    final victimName = await _resolveVictimName();
    final timestampLabel = _formatSosTimestamp(DateTime.now());
    final batteryLevel = await _getBatteryLevel();
    String? joinLink;

    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        final uri = await RescueInviteController.instance
            .createActiveRescueInviteUri(sessionId: sessionId);
        joinLink = uri?.toString();
      } catch (e) {
        debugPrint('Failed to build rescue invite link for SMS: $e');
      }
    }

    final lines = <String>[
      'EMERGENCY',
      '$victimName needs help immediately.',
      if (timestampLabel != null) 'Time: $timestampLabel',
      if (batteryLevel != null) 'Battery: $batteryLevel%',
      'Location: https://maps.google.com/?q=$lat,$lng',
      if (joinLink != null && joinLink.isNotEmpty) 'Join Rescue: $joinLink',
    ];
    return lines.join('\n');
  }

  Future<void> _dispatchEmergencySmsInBackground({
    required List<String> contactsList,
    required ContactController contactCtrl,
  }) async {
    if (contactsList.isEmpty) {
      smsStatusMessage.value = 'No emergency contacts saved';
      Get.snackbar(
        "Warning",
        "No emergency contacts found.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final smsGranted = await contactCtrl.checkAndRequestSmsPermission();
    if (!smsGranted) {
      smsStatusMessage.value = 'SMS permission denied';
      Get.snackbar(
        "SMS Permission Needed",
        "Emergency SMS could not be sent because SMS permission was not granted.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black87,
        colorText: Colors.redAccent,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    isSendingEmergencyAlerts.value = true;
    smsStatusMessage.value = 'Sending emergency alerts...';
    await refreshSmsSubscriptions();

    Get.snackbar(
      "Sending SOS...",
      "Automatically notifying emergency contacts...",
      snackPosition: SnackPosition.TOP,
    );

    try {
      final dispatchResult = await _sendAutomaticSmsAlerts(contactsList);
      final failedCount = dispatchResult.failedNumbers.length;
      final sentCount = dispatchResult.sentCount;

      if (failedCount == 0) {
        smsStatusMessage.value = 'Emergency alerts sent successfully';
        Get.snackbar(
          "SOS sent successfully",
          "Messages sent to all $sentCount emergency contacts.",
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else if (sentCount > 0) {
        smsStatusMessage.value = 'Emergency alerts sent with partial failures';
        Get.snackbar(
          "SOS sent with issues",
          "Sent to $sentCount contact(s). Failed for $failedCount contact(s).",
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      } else {
        smsStatusMessage.value = 'All emergency alert sends failed';
        Get.snackbar(
          "SMS Failed",
          "Unable to send SOS SMS right now. Rescue broadcast will continue.",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      isSendingEmergencyAlerts.value = false;
    }
  }

  Future<String> _resolveVictimName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'A SafeRoute user';
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final name = data?['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    } catch (e) {
      debugPrint('Failed to resolve SOS victim name: $e');
    }

    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    return 'A SafeRoute user';
  }

  String? _formatSosTimestamp(DateTime timestamp) {
    try {
      final hour12 = timestamp.hour == 0
          ? 12
          : (timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour);
      final suffix = timestamp.hour >= 12 ? 'PM' : 'AM';
      return '${timestamp.year.toString().padLeft(4, '0')}-'
          '${timestamp.month.toString().padLeft(2, '0')}-'
          '${timestamp.day.toString().padLeft(2, '0')} '
          '${hour12.toString().padLeft(2, '0')}:'
          '${timestamp.minute.toString().padLeft(2, '0')} '
          '$suffix';
    } catch (_) {
      return null;
    }
  }

  Future<int?> _getBatteryLevel() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final level = await _smsChannel.invokeMethod<int>('getBatteryLevel');
      if (level != null && level >= 0 && level <= 100) {
        return level;
      }
    } catch (e) {
      debugPrint('Failed to get battery level for SMS: $e');
    }
    return null;
  }

  Future<_SmsDispatchResult> _sendAutomaticSmsAlerts(
    List<String> contactsList,
  ) async {
    final failedNumbers = <String>[];
    var sentCount = 0;

    for (var index = 0; index < contactsList.length; index++) {
      final number = contactsList[index];
      smsStatusMessage.value =
          'Sending emergency alerts... ${index + 1}/${contactsList.length}';
      smsRetryStatus.value = 'Sending to $number';
      final didSend = await sendSOSMessage(number);
      if (didSend) {
        sentCount++;
        smsSentCount.value = sentCount;
        smsRetryStatus.value = 'Delivered to $number';
      } else {
        failedNumbers.add(number);
        smsFailedCount.value = failedNumbers.length;
        smsRetryStatus.value = 'Failed for $number';
      }

      if (index < contactsList.length - 1) {
        smsRetryStatus.value = 'Waiting before next contact...';
        await Future<void>.delayed(_smsSendGap);
      }
    }

    if (contactsList.isEmpty) {
      smsRetryStatus.value = '';
    }

    return _SmsDispatchResult(
      sentCount: sentCount,
      failedNumbers: failedNumbers,
    );
  }

  Future<bool> sendSOSMessage(String phoneNumber) async {
    if (generatedMessage.isEmpty) {
      return false;
    }

    for (var attempt = 1; attempt <= _smsMaxAttemptsPerContact; attempt++) {
      try {
        final result = await _sendDirectSmsNative(phoneNumber, generatedMessage);
        if (result.success) {
          return true;
        }

        debugPrint(
          "Native SMS send failed for $phoneNumber on attempt $attempt: ${result.errorMessage}",
        );
      } catch (e) {
        debugPrint(
          "Error sending SMS to $phoneNumber on attempt $attempt: $e",
        );
      }

      if (attempt < _smsMaxAttemptsPerContact) {
        smsRetryStatus.value =
            'Retrying $phoneNumber (${attempt + 1}/$_smsMaxAttemptsPerContact)...';
        await Future<void>.delayed(_smsRetryGap);
        continue;
      }
    }

    debugPrint("SMS permanently failed for $phoneNumber");
    return false;
  }

  Future<NativeSmsSendResult> _sendDirectSmsNative(
    String phoneNumber,
    String message,
  ) async {
    if (!Platform.isAndroid) {
      return const NativeSmsSendResult(
        success: false,
        errorMessage: 'Direct in-app SMS is only supported on Android.',
      );
    }

    try {
      final response = await _smsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'sendDirectSms',
        {
          'phoneNumber': phoneNumber,
          'message': message,
          'subscriptionId': selectedSmsSubscriptionId.value,
        },
      );
      final data = Map<String, dynamic>.from(response ?? const {});
      return NativeSmsSendResult(
        success: data['success'] == true,
        errorMessage: data['errorMessage']?.toString(),
      );
    } on PlatformException catch (e) {
      return NativeSmsSendResult(
        success: false,
        errorMessage: e.message ?? e.code,
      );
    } catch (e) {
      return NativeSmsSendResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refreshSmsSubscriptions() async {
    if (!Platform.isAndroid) {
      availableSmsSubscriptions.clear();
      selectedSmsSubscriptionId.value = null;
      return;
    }

    try {
      final response = await _smsChannel.invokeMethod<List<dynamic>>(
        'getSmsSubscriptions',
      );
      final subscriptions = (response ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => SmsSubscriptionInfo.fromMap(item))
          .toList();
      availableSmsSubscriptions.assignAll(subscriptions);

      final selectedId = selectedSmsSubscriptionId.value;
      final hasSelectedMatch = selectedId != null &&
          subscriptions.any((subscription) => subscription.subscriptionId == selectedId);
      if (!hasSelectedMatch) {
        SmsSubscriptionInfo? defaultSubscription;
        for (final subscription in subscriptions) {
          if (subscription.isDefault) {
            defaultSubscription = subscription;
            break;
          }
        }
        selectedSmsSubscriptionId.value = defaultSubscription?.subscriptionId;
      }
    } catch (e) {
      debugPrint('Failed to read SMS subscriptions: $e');
      availableSmsSubscriptions.clear();
    }
  }

  Future<void> showSmsSubscriptionPicker() async {
    await refreshSmsSubscriptions();
    if (availableSmsSubscriptions.length <= 1) {
      Get.snackbar(
        'Single SIM Active',
        'Your device is using the default SMS SIM.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final selectedId = await Get.dialog<int>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose SMS SIM'),
        content: SizedBox(
          width: double.maxFinite,
          child: Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              children: availableSmsSubscriptions
                  .map(
                    (subscription) => RadioListTile<int>(
                      value: subscription.subscriptionId,
                      groupValue: selectedSmsSubscriptionId.value,
                      onChanged: (value) => Get.back(result: value),
                      title: Text(subscription.displayName),
                      subtitle: Text(subscription.description),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );

    if (selectedId != null) {
      selectedSmsSubscriptionId.value = selectedId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_preferredSmsSubscriptionPrefsKey, selectedId);
      SmsSubscriptionInfo? selected;
      for (final subscription in availableSmsSubscriptions) {
        if (subscription.subscriptionId == selectedId) {
          selected = subscription;
          break;
        }
      }
      if (selected != null) {
        Get.snackbar(
          'SMS SIM Updated',
          'SafeRoute will use ${selected.displayName} for direct SMS.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  void _resetSmsStatus() {
    smsStatusMessage.value = 'Preparing emergency alerts...';
    smsRetryStatus.value = '';
    smsSentCount.value = 0;
    smsFailedCount.value = 0;
    smsTotalCount.value = 0;
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
        duration: const Duration(seconds: 2),
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
    if (isCompletingRescue.value) {
      return;
    }

    isCompletingRescue.value = true;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('No active user found.');
      }

      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final sessionRef =
          FirebaseFirestore.instance.collection('active_sos').doc(uid);
      final statsRef = FirebaseFirestore.instance.doc(_globalStatsDocPath);
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        if (!sessionSnapshot.exists) {
          throw Exception('SOS session not found.');
        }

        final sessionData = sessionSnapshot.data() ?? <String, dynamic>{};
        final status = sessionData['status']?.toString();
        if (status == 'completed') {
          throw Exception('This rescue has already been completed.');
        }
        if (sessionData['active'] != true || status != 'active') {
          throw Exception('Only an active SOS can be marked as safe.');
        }

        final victim = sessionData['victim'];
        final hasVictimData =
            (victim is Map &&
                victim['lat'] != null &&
                victim['lng'] != null) ||
            (sessionData['latitude'] != null && sessionData['longitude'] != null);
        if (!hasVictimData) {
          throw Exception('Victim location data is missing for this SOS session.');
        }

        final responders = List<String>.from(
          (sessionData['responders'] as List<dynamic>? ?? [])
              .map((e) => e.toString()),
        );

        transaction.update(sessionRef, {
          'active': false,
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'completedAtMs': nowMs,
          'completedByUid': uid,
          'updatedAtMs': nowMs,
        });

        transaction.set(statsRef, {
          'totalRescues': FieldValue.increment(1),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastUpdatedMs': nowMs,
        }, SetOptions(merge: true));

        transaction.set(userRef, {
          'successfulRescuesCount': FieldValue.increment(1),
        }, SetOptions(merge: true));

        for (final responderUid in responders) {
          final responderRef =
              FirebaseFirestore.instance.collection('users').doc(responderUid);
          transaction.set(responderRef, {
            'helpedRescuesCount': FieldValue.increment(1),
          }, SetOptions(merge: true));
        }
      });

      _fallbackCallTimer?.cancel();
      isSent.value = false;
      isActiveBroadcast.value = false;
      generatedMessage = '';
      SosListenerController.instance.clearActiveNavigation();
      await HistoryController.instanceOrCreate().recordSos(
        status: 'Completed',
        locationLabel: 'Rescue successfully completed',
      );

      Get.snackbar(
        "Rescue Completed",
        "Rescue completed successfully.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint("Error stopping SOS: \$e");
      Get.snackbar(
        "Error",
        "Failed to complete rescue. Please try again.",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    } finally {
      isCompletingRescue.value = false;
    }
  }

  Future<void> updateVictimLocation(Position position) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !isActiveBroadcast.value) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await FirebaseFirestore.instance.collection('active_sos').doc(uid).update({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'victim': {
          'lat': position.latitude,
          'lng': position.longitude,
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastUpdatedMs': nowMs,
        },
        'updatedAtMs': nowMs,
      });
    } catch (e) {
      debugPrint("Failed to update victim location: $e");
    }
  }

  Future<void> _triggerFallbackCall(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('active_sos')
          .doc(uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final responders = data['responders'] as List<dynamic>? ?? [];
        if (responders.isEmpty) {
          final contactCtrl = Get.isRegistered<ContactController>()
              ? Get.find<ContactController>()
              : ContactController.instanceOrCreate();
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

  int? _extractSosTimestampMs(Map<String, dynamic>? data) {
    if (data == null) return null;

    final startedAtMs = data['startedAtMs'];
    if (startedAtMs is int) return startedAtMs;

    final updatedAtMs = data['updatedAtMs'];
    if (updatedAtMs is int) return updatedAtMs;

    final timestamp = data['timestamp'];
    if (timestamp is Timestamp) {
      return timestamp.millisecondsSinceEpoch;
    }

    return null;
  }
}

class _SmsDispatchResult {
  const _SmsDispatchResult({
    required this.sentCount,
    required this.failedNumbers,
  });

  final int sentCount;
  final List<String> failedNumbers;
}

class NativeSmsSendResult {
  const NativeSmsSendResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

class SmsSubscriptionInfo {
  const SmsSubscriptionInfo({
    required this.subscriptionId,
    required this.displayName,
    required this.description,
    required this.isDefault,
  });

  factory SmsSubscriptionInfo.fromMap(Map<dynamic, dynamic> map) {
    final displayName = map['displayName']?.toString() ?? 'SIM';
    final carrierName = map['carrierName']?.toString() ?? '';
    final slotIndex = (map['simSlotIndex'] as num?)?.toInt();
    final suffix = slotIndex == null ? '' : ' • Slot ${slotIndex + 1}';
    final description = carrierName.isEmpty
        ? displayName + suffix
        : '$carrierName$suffix';

    return SmsSubscriptionInfo(
      subscriptionId: (map['subscriptionId'] as num).toInt(),
      displayName: displayName,
      description: description,
      isDefault: map['isDefault'] == true,
    );
  }

  final int subscriptionId;
  final String displayName;
  final String description;
  final bool isDefault;
}
