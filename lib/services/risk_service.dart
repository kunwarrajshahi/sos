import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class RiskService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache structure: "lat,lng" -> { 'score': score, 'timestamp': Time }
  static final Map<String, Map<String, dynamic>> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Rounds location to roughly 100m buckets (approx 3 decimal places for lat/lng)
  static String _getCacheKey(LatLng location) {
    return '${location.latitude.toStringAsFixed(3)},${location.longitude.toStringAsFixed(3)}';
  }

  /// Calculates a risk score between 0 and 100 based on time, proximity to unsafe areas, and SOS history
  static Future<double> calculateRiskScore(LatLng location) async {
    final cacheKey = _getCacheKey(location);
    final now = DateTime.now();

    // Cache hit check
    if (_cache.containsKey(cacheKey)) {
      final cachedTime = _cache[cacheKey]!['timestamp'] as DateTime;
      if (now.difference(cachedTime) < _cacheDuration) {
        return _cache[cacheKey]!['score'] as double;
      }
    }

    double maxScore = 100.0;
    double score = 20.0; // Base score

    // Time check: between 8PM (20:00) and 5AM (05:00) → +20
    if (now.hour >= 20 || now.hour < 5) {
      score += 20.0;
    }

    // Nearby unsafe zones check -> +30 if within 200m
    // Quick approx bounding box degree delta for latitude (1 deg = ~111km)
    double latDelta200m = 200 / 111320; 
    
    try {
      final unsafeSnapshot = await _firestore
          .collection('unsafe_areas')
          .where('lat', isGreaterThanOrEqualTo: location.latitude - latDelta200m)
          .where('lat', isLessThanOrEqualTo: location.latitude + latDelta200m)
          .get();

      bool nearUnsafeZone = false;
      for (var doc in unsafeSnapshot.docs) {
        final data = doc.data();
        if (data['lat'] != null && data['lng'] != null) {
          double dist = Geolocator.distanceBetween(
              location.latitude, location.longitude, 
              (data['lat'] as num).toDouble(), 
              (data['lng'] as num).toDouble());
              
          if (dist <= 200) {
            nearUnsafeZone = true;
            break; // Max penalty for unsafe areas applied, skip remaining checks
          }
        }
      }
      
      if (nearUnsafeZone) {
        score += 30.0;
      }
    } catch (e) {
      debugPrint("Error fetching unsafe_areas for risk score: $e");
    }

    // Past SOS density check -> +30 if at least 1 SOS found in 500m radius
    double latDelta500m = 500 / 111320;
    try {
      final sosSnapshot = await _firestore
          .collection('sos_history')
          .where('lat', isGreaterThanOrEqualTo: location.latitude - latDelta500m)
          .where('lat', isLessThanOrEqualTo: location.latitude + latDelta500m)
          .get();

      int sosCount = 0;
      for (var doc in sosSnapshot.docs) {
        final data = doc.data();
         if (data['lat'] != null && data['lng'] != null) {
          double dist = Geolocator.distanceBetween(
              location.latitude, location.longitude, 
              (data['lat'] as num).toDouble(), 
              (data['lng'] as num).toDouble());
              
          if (dist <= 500) {
            sosCount++;
          }
        }
      }

      if (sosCount > 0) { // Threshold is explicitly 0 so > 0 is true.
        score += 30.0;
      }
    } catch (e) {
      debugPrint("Error fetching sos_history for risk score: $e");
    }

    // Normalize final score to not exceed 100
    if (score > maxScore) {
      score = maxScore;
    }

    // Update Cache
    _cache[cacheKey] = {
      'score': score,
      'timestamp': now,
    };

    return score;
  }
}
