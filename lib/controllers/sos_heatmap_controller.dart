import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

class SosHeatPoint {
  const SosHeatPoint({
    required this.position,
    required this.weight,
    required this.count,
  });

  final LatLng position;
  final double weight;
  final int count;
}

class SosHeatmapController extends GetxController {
  static const int _maxRawDocs = 1200;
  static const int _lookbackDays = 45;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final RxBool isVisible = false.obs;
  final RxBool isLoading = false.obs;
  final RxList<SosHeatPoint> clusteredPoints = <SosHeatPoint>[].obs;

  void toggleVisibility(bool value) {
    isVisible.value = value;
  }

  Future<void> refreshForViewport({
    required LatLngBounds bounds,
    required double zoom,
  }) async {
    if (!isVisible.value) {
      clusteredPoints.clear();
      return;
    }

    isLoading.value = true;
    try {
      final docs = await _fetchVisibleSosHistory(bounds: bounds);
      final clustered = _clusterAndWeight(docs: docs, zoom: zoom);
      clusteredPoints.assignAll(clustered);
    } finally {
      isLoading.value = false;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchVisibleSosHistory({required LatLngBounds bounds}) async {
    final now = DateTime.now();
    final minTimestamp = Timestamp.fromDate(
      now.subtract(const Duration(days: _lookbackDays)),
    );

    final minLat = min(bounds.south, bounds.north);
    final maxLat = max(bounds.south, bounds.north);
    final minLng = min(bounds.west, bounds.east);
    final maxLng = max(bounds.west, bounds.east);

    final query = await _firestore
        .collection('sos_history')
        .where('timestamp', isGreaterThanOrEqualTo: minTimestamp)
        .where('lat', isGreaterThanOrEqualTo: minLat)
        .where('lat', isLessThanOrEqualTo: maxLat)
        .orderBy('timestamp', descending: true)
        .limit(_maxRawDocs)
        .get();

    return query.docs.where((doc) {
      final data = doc.data();
      final lng = (data['lng'] as num?)?.toDouble();
      return lng != null && lng >= minLng && lng <= maxLng;
    }).toList();
  }

  List<SosHeatPoint> _clusterAndWeight({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required double zoom,
  }) {
    if (docs.isEmpty) return const <SosHeatPoint>[];

    final now = DateTime.now();
    final cellSize = _cellSizeForZoom(zoom);
    final buckets = <String, _Bucket>{};

    for (final doc in docs) {
      final data = doc.data();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final ts = data['timestamp'];
      if (lat == null || lng == null || ts is! Timestamp) continue;

      final weight = _recencyWeight(now: now, timestamp: ts.toDate());
      if (weight <= 0) continue;

      final keyLat = (lat / cellSize).floor();
      final keyLng = (lng / cellSize).floor();
      final key = '$keyLat:$keyLng';

      final bucket = buckets.putIfAbsent(key, _Bucket.new);
      bucket.weightSum += weight;
      bucket.weightedLat += lat * weight;
      bucket.weightedLng += lng * weight;
      bucket.count += 1;
    }

    final points = buckets.values
        .where((bucket) => bucket.weightSum > 0)
        .map(
          (bucket) => SosHeatPoint(
            position: LatLng(
              bucket.weightedLat / bucket.weightSum,
              bucket.weightedLng / bucket.weightSum,
            ),
            weight: bucket.weightSum,
            count: bucket.count,
          ),
        )
        .toList();

    points.sort((a, b) => b.weight.compareTo(a.weight));
    return points;
  }

  double _recencyWeight({required DateTime now, required DateTime timestamp}) {
    final ageDays = now.difference(timestamp).inHours / 24.0;
    if (ageDays < 0) return 1.0;
    const halfLifeDays = 7.0;
    return pow(0.5, ageDays / halfLifeDays).toDouble();
  }

  double _cellSizeForZoom(double zoom) {
    if (zoom >= 16) return 0.0025;
    if (zoom >= 14) return 0.005;
    if (zoom >= 12) return 0.01;
    if (zoom >= 10) return 0.02;
    return 0.04;
  }

  List<CircleMarker> buildCircleMarkers() {
    if (!isVisible.value || clusteredPoints.isEmpty) return const [];

    final maxWeight = clusteredPoints
        .map((p) => p.weight)
        .fold<double>(0, max)
        .clamp(0.0001, double.infinity);

    return clusteredPoints.map((point) {
      final intensity = (point.weight / maxWeight).clamp(0.0, 1.0);
      return CircleMarker(
        point: point.position,
        useRadiusInMeter: true,
        radius: 120 + (intensity * 260),
        borderStrokeWidth: 1.1,
        borderColor: _colorForIntensity(intensity).withOpacity(0.9),
        color: _colorForIntensity(intensity).withOpacity(0.36),
      );
    }).toList();
  }

  Color _colorForIntensity(double intensity) {
    if (intensity >= 0.66) return Colors.red;
    if (intensity >= 0.33) return Colors.yellow.shade700;
    return Colors.green;
  }
}

class _Bucket {
  double weightSum = 0;
  double weightedLat = 0;
  double weightedLng = 0;
  int count = 0;
}
