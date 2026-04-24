import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class RescueStatsController extends GetxController {
  static RescueStatsController get instance => Get.find<RescueStatsController>();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final totalRescues = 0.obs;
  final personalHelpedRescues = 0.obs;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _globalSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
  StreamSubscription<User?>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    _listenToGlobalStats();
    _authSubscription = _auth.userChanges().listen((_) {
      _listenToPersonalStats();
    });
    _listenToPersonalStats();
  }

  @override
  void onClose() {
    _globalSubscription?.cancel();
    _userSubscription?.cancel();
    _authSubscription?.cancel();
    super.onClose();
  }

  void _listenToGlobalStats() {
    _globalSubscription?.cancel();
    _globalSubscription = _firestore
        .collection('stats')
        .doc('global')
        .snapshots()
        .listen((snapshot) {
      totalRescues.value =
          (snapshot.data()?['totalRescues'] as num?)?.toInt() ?? 0;
    });
  }

  void _listenToPersonalStats() {
    _userSubscription?.cancel();
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      personalHelpedRescues.value = 0;
      return;
    }

    _userSubscription = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      personalHelpedRescues.value =
          (snapshot.data()?['helpedRescuesCount'] as num?)?.toInt() ?? 0;
    });
  }

  String get totalRescuesLabel {
    final total = totalRescues.value;
    if (total >= 100) {
      return 'Trusted by $total+ successful rescues';
    }
    return '$total+ Rescues Completed';
  }
}
