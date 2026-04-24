import 'dart:convert';
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
  /// Fetches a route between two points using the public OSRM API.
  /// Returns route geometry plus distance and duration metadata.
  static Future<RouteSummary> getRoute(LatLng start, LatLng end) async {
    final String url = 
      'http://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        
        if (routes.isNotEmpty) {
          final route = routes[0] as Map<String, dynamic>;
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;
          final points = coordinates.map((coord) {
            // OSRM returns coordinates as [longitude, latitude]
            return LatLng(coord[1] as double, coord[0] as double);
          }).toList();

          return RouteSummary(
            points: points,
            distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
            durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0,
          );
        }
      }
      return const RouteSummary(
        points: [],
        distanceMeters: 0,
        durationSeconds: 0,
      );
    } catch (e) {
      print("Error fetching route from OSRM: $e");
      return const RouteSummary(
        points: [],
        distanceMeters: 0,
        durationSeconds: 0,
      );
    }
  }
}
