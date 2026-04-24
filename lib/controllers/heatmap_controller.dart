import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'history_controller.dart';

class UnsafeZone {
  const UnsafeZone({
    required this.id,
    required this.point,
    required this.reason,
    required this.timeStart,
    required this.timeEnd,
    this.areaName,
  });

  final String id;
  final LatLng point;
  final String? reason;
  final String timeStart;
  final String timeEnd;
  final String? areaName;
}

class HeatmapController extends GetxController {
  // Toggle visibility of the unsafe zones layer
  var isHeatmapVisible = true.obs;

  // The live tracking array representing synced Unsafe Zones natively
  var unsafeZones = <UnsafeZone>[].obs;

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
          final List<UnsafeZone> fetchedZones = [];
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final timeStart = _readString(data['time_start']);
            final timeEnd = _readString(data['time_end']);
            if (data['lat'] != null &&
                data['lng'] != null &&
                _hasValidTimeRange(timeStart, timeEnd)) {
              fetchedZones.add(
                UnsafeZone(
                  id: doc.id,
                  point: LatLng(
                    (data['lat'] as num).toDouble(),
                    (data['lng'] as num).toDouble(),
                  ),
                  reason: _readString(data['reason']),
                  timeStart: timeStart!,
                  timeEnd: timeEnd!,
                  areaName: _readString(data['area_name']) ?? _readString(data['name']),
                ),
              );
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

  String? _readString(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _hasValidTimeRange(String? timeStart, String? timeEnd) {
    return timeStart != null &&
        timeEnd != null &&
        TimeOfDayFormatUtil.tryParse(timeStart) != null &&
        TimeOfDayFormatUtil.tryParse(timeEnd) != null;
  }

  // Action hook to toggle boolean states reactively across UI
  void toggleHeatmap() {
    isHeatmapVisible.value = !isHeatmapVisible.value;
  }

  // Package target coordinates into dynamic objects piping directly to centralized Cloud Firestore mechanisms
  Future<void> addUnsafeZone(
    LatLng point, {
    String? reason,
    String? timeStart,
    String? timeEnd,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('unsafe_zones').add({
        'lat': point.latitude,
        'lng': point.longitude,
        'reason': reason,
        'time_start': timeStart,
        'time_end': timeEnd,
        'name': null,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await HistoryController.instanceOrCreate().recordUnsafeZone(
        reason: reason,
        timeStart: timeStart,
        timeEnd: timeEnd,
      );

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

class TimeOfDayFormatUtil {
  static TimeOfDay? tryParse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }
}
