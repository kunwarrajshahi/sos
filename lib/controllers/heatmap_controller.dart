import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HeatmapController extends GetxController {
  // Toggle visibility of the unsafe zones layer
  var isHeatmapVisible = true.obs;

  // The live tracking array representing synced Unsafe Zones natively
  var unsafeZones = <LatLng>[].obs;

  @override
  void onInit() {
    super.onInit();
    _listenToUnsafeZones();
  }

  void _listenToUnsafeZones() {
    // Graceful exception bounding allowing local compilation tests even if Firebase is disabled structurally
    try {
      FirebaseFirestore.instance
          .collection('unsafe_zones')
          .snapshots()
          .listen(
        (QuerySnapshot snapshot) {
          final List<LatLng> fetchedZones = [];
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['lat'] != null && data['lng'] != null) {
              fetchedZones.add(LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()));
            }
          }
          // Reactive assignment forcing GetX Obx instances to reload map vectors securely
          unsafeZones.assignAll(fetchedZones);
        },
        onError: (error) => debugPrint("Firestore Live Mapping Error: $error"),
      );
    } catch (e) {
      debugPrint("Firebase stream failed to bind completely: $e");
    }
  }

  // Action hook to toggle boolean states reactively across UI
  void toggleHeatmap() {
    isHeatmapVisible.value = !isHeatmapVisible.value;
  }

  // Package target coordinates into dynamic objects piping directly to centralized Cloud Firestore mechanisms
  Future<void> addUnsafeZone(LatLng point) async {
    try {
      await FirebaseFirestore.instance.collection('unsafe_zones').add({
        'lat': point.latitude,
        'lng': point.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Automatically turn on the Heatmap layer if it wasn't already to showcase the community updates
      if (!isHeatmapVisible.value) {
        isHeatmapVisible.value = true;
      }

      Get.snackbar(
        "Added", 
        "Unsafe zone shared with community",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.redAccent.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        icon: const Icon(Icons.warning, color: Colors.white)
      );
    } catch (e) {
      Get.snackbar(
        "Connection Terminated", 
        "Failed deploying cloud snapshot natively.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black87,
        colorText: Colors.redAccent,
      );
    }
  }
}
