import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class RiskService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Map<String, Map<String, dynamic>> _cache = {};

  static const Duration _cacheDuration = Duration(minutes: 5);
  static const double _zoneSearchRadiusMeters = 1200;
  static const double _zoneNearbyRadiusMeters = 450;
  static const double _zoneActualRadiusMeters = 150;

  static String _getCacheKey(LatLng location) {
    return '${location.latitude.toStringAsFixed(3)},${location.longitude.toStringAsFixed(3)}';
  }

  static Future<double> calculateRiskScore(LatLng location) async {
    final cacheKey = _getCacheKey(location);
    final now = DateTime.now();

    final cached = _cache[cacheKey];
    if (cached != null) {
      final cachedTime = cached['timestamp'] as DateTime;
      if (now.difference(cachedTime) < _cacheDuration) {
        return cached['score'] as double;
      }
    }

    var score = 8.0;
    if (now.hour >= 20 || now.hour < 5) {
      score += 12.0;
    }

    final latDelta = _zoneSearchRadiusMeters / 111320;
    var nearestDangerDistance = double.infinity;
    var nearbyDangerCount = 0;
    var criticalDangerCount = 0;

    try {
      final unsafeSnapshot = await _firestore
          .collection('unsafe_zones')
          .where('lat', isGreaterThanOrEqualTo: location.latitude - latDelta)
          .where('lat', isLessThanOrEqualTo: location.latitude + latDelta)
          .get();

      for (final doc in unsafeSnapshot.docs) {
        final data = doc.data();
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) {
          continue;
        }

        final distance = Geolocator.distanceBetween(
          location.latitude,
          location.longitude,
          lat,
          lng,
        );

        if (distance < nearestDangerDistance) {
          nearestDangerDistance = distance;
        }
        if (distance <= _zoneNearbyRadiusMeters) {
          nearbyDangerCount++;
        }
        if (distance <= _zoneActualRadiusMeters) {
          criticalDangerCount++;
        }
      }
    } catch (e) {
      debugPrint('Error fetching unsafe_zones for risk score: $e');
    }

    if (!nearestDangerDistance.isInfinite) {
      final proximityWeight =
          (1 - (nearestDangerDistance / _zoneSearchRadiusMeters)).clamp(
            0.0,
            1.0,
          );
      score += proximityWeight * 42.0;
    }

    score += (nearbyDangerCount * 8).clamp(0, 24).toDouble();
    score += (criticalDangerCount * 12).clamp(0, 24).toDouble();

    try {
      final activeSosSnapshot = await _firestore
          .collection('active_sos')
          .where('active', isEqualTo: true)
          .get();

      var activeNearbyCount = 0;
      for (final doc in activeSosSnapshot.docs) {
        final data = doc.data();
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) {
          continue;
        }

        final distance = Geolocator.distanceBetween(
          location.latitude,
          location.longitude,
          lat,
          lng,
        );
        if (distance <= 800) {
          activeNearbyCount++;
        }
      }

      score += (activeNearbyCount * 5).clamp(0, 14).toDouble();
    } catch (e) {
      debugPrint('Error fetching active_sos for risk score: $e');
    }

    score = score.clamp(0.0, 100.0);

    _cache[cacheKey] = {'score': score, 'timestamp': now};

    return score;
  }
}
