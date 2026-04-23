import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  /// Fetches a route between two points using the public OSRM API.
  /// Returns a list of LatLng points representing the polyline.
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
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
          final geometry = routes[0]['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          return coordinates.map((coord) {
            // OSRM returns coordinates as [longitude, latitude]
            return LatLng(coord[1] as double, coord[0] as double);
          }).toList();
        }
      }
      return [];
    } catch (e) {
      print("Error fetching route from OSRM: $e");
      return [];
    }
  }
}
