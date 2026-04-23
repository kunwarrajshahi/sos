import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../screens/map_screen.dart';

class SosListenerController extends GetxController {
  static SosListenerController instance = Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  StreamSubscription? _sosSubscription;
  final Set<String> _processedSos = {};
  
  // Expose an active target for MapScreen to automatically draw a route towards
  var activeSosTarget = Rx<LatLng?>(null);

  @override
  void onInit() {
    super.onInit();
    _startListening();
  }

  @override
  void onClose() {
    _sosSubscription?.cancel();
    super.onClose();
  }

  void _startListening() {
    _sosSubscription = _firestore
        .collection('active_sos')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          _handleIncomingSos(change.doc);
        }
      }
    });
  }

  Future<void> _handleIncomingSos(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;

    final uid = data['uid'] as String?;
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    
    // Ignore invalid data or our own SOS broadcasts
    if (uid == null || lat == null || lng == null) return;
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId != null && uid == currentUserId) return;
    
    final responders = data['responders'] as List<dynamic>? ?? [];
    if (responders.length >= 3 && currentUserId != null && !responders.contains(currentUserId)) {
       return; // Cap reached, ignore SOS
    }
    
    // If we have already notified the user about this specific SOS, skip it
    if (_processedSos.contains(uid)) return;

    try {
      Position myPosition = await LocationService.getCurrentPosition();
      
      double distanceInMeters = Geolocator.distanceBetween(
        myPosition.latitude, myPosition.longitude,
        lat, lng
      );

      // If within 5km radius
      if (distanceInMeters <= 5000) {
        _processedSos.add(uid);
        _showIncomingSosAlert(uid, LatLng(lat, lng), distanceInMeters);
      }
    } catch (e) {
      debugPrint("Error processing incoming SOS: \$e");
    }
  }

  void _showIncomingSosAlert(String sosUid, LatLng target, double distance) {
    String formattedDistance = (distance / 1000).toStringAsFixed(1);
    
    Get.defaultDialog(
      title: "🚨 URGENT: SOS NEARBY",
      titleStyle: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 22),
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Someone triggered an SOS $formattedDistance km away from your location!",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.warning, color: Colors.redAccent, size: 64),
        ]
      ),
      textConfirm: "Navigate to Help",
      confirmTextColor: Colors.white,
      buttonColor: Colors.redAccent,
      onConfirm: () {
        Get.back(); // close dialog
        _navigateToSos(sosUid, target);
      },
      textCancel: "Ignore",
      cancelTextColor: Colors.grey,
    );
  }

  Future<void> _navigateToSos(String sosUid, LatLng target) async {
    activeSosTarget.value = target;
    
    if (_auth.currentUser != null) {
      try {
        await _firestore.collection('active_sos').doc(sosUid).update({
          'responders': FieldValue.arrayUnion([_auth.currentUser!.uid])
        });
      } catch(e) {
        debugPrint("Error updating responders: \$e");
      }
    }
    
    // Redirect user to the MapScreen if they aren't there already
    if (Get.currentRoute != '/MapScreen') {
      Get.offAll(() => const MapScreen());
    }
  }
}
