import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteSummary {
  const RouteSummary({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
}

class RoutingService {
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// Fetches a route between two points using the public OSRM API.
  /// Returns route geometry plus distance and duration metadata.
  static Future<RouteSummary> getRoute(
    LatLng start,
    LatLng end, {
    List<LatLng> viaPoints = const [],
  }) async {
    final routes = await getAlternativeRoutes(
      start,
      end,
      viaPoints: viaPoints,
      maxAlternatives: 1,
    );
    return routes.isNotEmpty
        ? routes.first
        : const RouteSummary(points: [], distanceMeters: 0, durationSeconds: 0);
  }

  static Future<List<RouteSummary>> getAlternativeRoutes(
    LatLng start,
    LatLng end, {
    List<LatLng> viaPoints = const [],
    int maxAlternatives = 3,
  }) async {
    final coordinates = <LatLng>[start, ...viaPoints, end];
    final coordinatesPath = coordinates
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$coordinatesPath',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'alternatives': 'true',
        'steps': 'false',
      },
    );

    try {
      final response = await http
          .get(uri, headers: const {'User-Agent': 'SafeRoute/1.0'})
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = (data['routes'] as List?) ?? const [];

        if (routes.isNotEmpty) {
          return routes
              .take(maxAlternatives)
              .map((route) {
                final routeMap = route as Map<String, dynamic>;
                final geometry = routeMap['geometry'] as Map<String, dynamic>?;
                final routeCoordinates =
                    (geometry?['coordinates'] as List?) ?? const [];
                final points = routeCoordinates
                    .map(
                      (coord) => LatLng(
                        (coord[1] as num).toDouble(),
                        (coord[0] as num).toDouble(),
                      ),
                    )
                    .toList();

                return RouteSummary(
                  points: points,
                  distanceMeters:
                      (routeMap['distance'] as num?)?.toDouble() ?? 0,
                  durationSeconds:
                      (routeMap['duration'] as num?)?.toDouble() ?? 0,
                );
              })
              .where((route) => route.points.isNotEmpty)
              .toList();
        }
      }
      return const <RouteSummary>[];
    } catch (e) {
      debugPrint("Error fetching route from OSRM: $e");
      return const <RouteSummary>[];
    }
  }
}
