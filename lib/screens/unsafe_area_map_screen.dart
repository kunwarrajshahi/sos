import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/unsafe_area_dialog.dart';

/// Map screen with long press to report unsafe areas
/// Long press karne se dialog khulta hai jahaan user:
/// - Reason select kar sakta hai (Harassment, Poor Lighting, etc.)
/// - Time entry kar sakta hai (kab area unsafe tha)
class UnsafeAreaMapScreen extends StatefulWidget {
  const UnsafeAreaMapScreen({super.key});

  @override
  State<UnsafeAreaMapScreen> createState() => _UnsafeAreaMapScreenState();
}

class _UnsafeAreaMapScreenState extends State<UnsafeAreaMapScreen> {
  late MapController mapController;
  final List<Marker> unsafeMarkers = [];

  @override
  void initState() {
    super.initState();
    mapController = MapController();
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  /// Long press handler - Dialog khone ka trigger
  void _onMapLongPress(dynamic tapPosition, LatLng point) {
    _showUnsafeAreaDialog(point.latitude, point.longitude);
  }

  /// Unsafe area dialog dikhana
  void _showUnsafeAreaDialog(double latitude, double longitude) {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: latitude,
        longitude: longitude,
        onConfirm: (data) {
          if (data.timeStart == null || data.timeEnd == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Area not marked: Timing data is required to maintain the red circle.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          // Marker add karna map pe
          _addMarkerToMap(data);

          // Success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Area Marked as Unsafe',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Reason: ${data.reason ?? "Not specified"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        if (data.timeStart != null)
                          Text(
                            'Time: ${data.timeStart} - ${data.timeEnd}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );

          // Debug: Print the data
          debugPrint('📍 Unsafe Area Reported:');
          debugPrint('Latitude: $latitude');
          debugPrint('Longitude: $longitude');
          debugPrint('Reason: ${data.reason}');
          debugPrint('Time: ${data.timeStart} - ${data.timeEnd}');
          debugPrint('Full Data: ${data.toJson()}');
        },
        onCancel: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Report cancelled')));
        },
      ),
    );
  }

  /// Map pe unsafe area marker add karna
  void _addMarkerToMap(UnsafeAreaData data) {
    final marker = Marker(
      point: LatLng(data.latitude, data.longitude),
      width: 40,
      height: 40,
      child: _buildUnsafeMarker(data),
    );

    setState(() {
      unsafeMarkers.add(marker);
    });
  }

  /// Unsafe area ke liye custom marker
  Widget _buildUnsafeMarker(UnsafeAreaData data) {
    IconData iconData;

    switch (data.reason) {
      case 'poor_lighting':
        iconData = Icons.light_mode;
        break;
      case 'harassment':
        iconData = Icons.security;
        break;
      case 'isolated_area':
        iconData = Icons.location_on;
        break;
      default:
        iconData = Icons.warning;
    }

    return GestureDetector(
      onTap: () => _showMarkerDetails(data),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(iconData, color: Colors.white, size: 20),
      ),
    );
  }

  /// Marker tap karne se details dikhana
  void _showMarkerDetails(UnsafeAreaData data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Unsafe Timing'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${data.timeStart} - ${data.timeEnd}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Reason', data.reason ?? 'Not specified'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Delete marker functionality
              setState(() {
                unsafeMarkers.removeWhere(
                  (m) =>
                      m.point.latitude == data.latitude &&
                      m.point.longitude == data.longitude,
                );
              });
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Unsafe Areas'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Chip(
                label: Text(
                  'Areas: ${unsafeMarkers.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: Colors.red,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map with long press gesture
          GestureDetector(
            onLongPressStart: (details) {
              // Long press ka location map se nikal na padega
              _showLongPressMenu(details.globalPosition);
            },
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                // Initial center (Delhi)
                initialCenter: const LatLng(28.6139, 77.2090),
                initialZoom: 13,
                // Long press handler directly
                onLongPress: _onMapLongPress,
              ),
              children: [
                // Map tiles
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'safe_route',
                ),
                // Unsafe area markers
                MarkerLayer(markers: unsafeMarkers),
              ],
            ),
          ),

          // Instructions overlay
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Map pe long press karo unsafe area mark karne ke liye',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Long press menu ke liye (optional)
  void _showLongPressMenu(Offset position) {
    // Yeh optional hai - already dialog map options mein khul raha hai
    // Agar alag se menu dikhana ho to is function ko use kar sakte ho
  }
}
