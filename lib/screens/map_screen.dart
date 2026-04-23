import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../services/location_service.dart';
import '../controllers/sos_controller.dart';
import '../controllers/heatmap_controller.dart';
import '../services/routing_service.dart';
import '../controllers/sos_listener_controller.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final SosController _sosController = Get.put(SosController());
  final HeatmapController _heatmapController = Get.put(HeatmapController());
  
  Position? _currentPosition;
  String? _errorMessage;
  bool _isLoading = true;
  
  List<LatLng> _sosRouteLocations = [];
  Worker? _sosWorker;
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _startLocationTracking(); // Real-time continuous stream
    
    _sosWorker = ever(SosListenerController.instance.activeSosTarget, (LatLng? target) {
      if (target != null && _currentPosition != null) {
         _drawRouteTo(target);
      } else if (target == null) {
         setState(() {
           _sosRouteLocations.clear();
         });
      }
    });
  }

  @override
  void dispose() {
    _sosWorker?.dispose();
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  void _startLocationTracking() {
    final locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update position when moving 5 meters natively
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        
        // If we are navigating, silently redraw the dynamic shortcut route so it anchors to our live location!
        if (SosListenerController.instance.activeSosTarget.value != null) {
          _drawRouteTo(SosListenerController.instance.activeSosTarget.value!);
        }
      }
    });
  }

  Future<void> _drawRouteTo(LatLng target) async {
    if (_currentPosition == null) return;
    try {
      final route = await RoutingService.getRoute(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 
        target
      );
      if (mounted) {
        setState(() {
          _sosRouteLocations = route;
        });
      }
    } catch (e) {
      debugPrint("Error drawing route: \$e");
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final position = await LocationService.getCurrentPosition();
      bool isFirstLoad = _currentPosition == null;
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      
      if (!isFirstLoad) {
        _moveCameraTo(position);
      }
      
      if (SosListenerController.instance.activeSosTarget.value != null) {
        _drawRouteTo(SosListenerController.instance.activeSosTarget.value!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      _showErrorSnackBar(_errorMessage!);
    }
  }

  void _moveCameraTo(Position position) {
    _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: _fetchCurrentLocation,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddUnsafeZoneDialog(LatLng point) {
    var selectedReason = 'Poor lighting'.obs;
    final selectedStartTime = Rxn<TimeOfDay>();
    final selectedEndTime = Rxn<TimeOfDay>();

    String formatTime(TimeOfDay time) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    Get.defaultDialog(
      title: "Mark Unsafe Area",
      titleStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      content: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Do you want to mark this area as unsafe?", textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text("Select Reason (Optional):", style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: -4.0,
                children: [
                  ChoiceChip(
                    label: const Text("Poor lighting"),
                    selected: selectedReason.value == 'Poor lighting',
                    onSelected: (bool selected) { if (selected) selectedReason.value = 'Poor lighting'; },
                    selectedColor: Colors.redAccent.withOpacity(0.3),
                  ),
                  ChoiceChip(
                    label: const Text("Harassment"),
                    selected: selectedReason.value == 'Harassment',
                    onSelected: (bool selected) { if (selected) selectedReason.value = 'Harassment'; },
                    selectedColor: Colors.redAccent.withOpacity(0.3),
                  ),
                  ChoiceChip(
                    label: const Text("Isolated area"),
                    selected: selectedReason.value == 'Isolated area',
                    onSelected: (bool selected) { if (selected) selectedReason.value = 'Isolated area'; },
                    selectedColor: Colors.redAccent.withOpacity(0.3),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Unsafe Time (Optional):",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              selectedStartTime.value ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          selectedStartTime.value = picked;
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(
                        selectedStartTime.value == null
                            ? "From"
                            : "From ${formatTime(selectedStartTime.value!)}",
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedEndTime.value ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          selectedEndTime.value = picked;
                        }
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        selectedEndTime.value == null
                            ? "To"
                            : "To ${formatTime(selectedEndTime.value!)}",
                      ),
                    ),
                  ),
                ],
              ),
            ],
          )),
      textConfirm: "Confirm",
      textCancel: "Cancel",
      confirmTextColor: Colors.white,
      buttonColor: Colors.redAccent,
      onConfirm: () {
        Get.back(); // Dismiss dialog
        _heatmapController.addUnsafeZone(
          point,
          reason: selectedReason.value,
          timeStart: selectedStartTime.value == null
              ? null
              : formatTime(selectedStartTime.value!),
          timeEnd: selectedEndTime.value == null
              ? null
              : formatTime(selectedEndTime.value!),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeRoute', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          Obx(() => Row(
                children: [
                  const Tooltip(message: 'Shake to trigger SOS', child: Icon(Icons.vibration, size: 20)),
                  Switch(
                    value: _sosController.isShakeSOSActive.value,
                    onChanged: (val) => _sosController.toggleShakeSOS(val),
                    activeColor: Colors.deepPurpleAccent,
                  ),
                  const SizedBox(width: 8),
                  const Tooltip(message: 'Community Unsafe Zones', child: Icon(Icons.local_fire_department, size: 20, color: Colors.red)),
                  Switch(
                    value: _heatmapController.isHeatmapVisible.value,
                    onChanged: (val) => _heatmapController.toggleHeatmap(),
                    activeColor: Colors.redAccent,
                  ),
                ],
              )),
        ],
      ),
      body: Stack(
        children: [
          _currentPosition == null 
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage ?? "Location not available",
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _fetchCurrentLocation,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Retry"),
                        )
                      ],
                    ),
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    initialZoom: 15.0,
                    onLongPress: (tapPosition, point) => _showAddUnsafeZoneDialog(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.safe_route',
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_sosRouteLocations.isNotEmpty)
                          Polyline(
                            points: _sosRouteLocations,
                            color: Colors.blueAccent,
                            strokeWidth: 5.0,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          width: 80,
                          height: 80,
                          child: const Icon(
                            Icons.location_pin,
                            size: 40,
                            color: Colors.red,
                          ),
                        ),
                        if (SosListenerController.instance.activeSosTarget.value != null)
                          Marker(
                            point: SosListenerController.instance.activeSosTarget.value!,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.warning,
                              size: 40,
                              color: Colors.redAccent,
                            ),
                          ),
                      ],
                    ),
                    Obx(() {
                      if (_heatmapController.isHeatmapVisible.value) {
                        return CircleLayer(
                          circles: _heatmapController.unsafeZones.map((zone) {
                            return CircleMarker(
                              point: zone,
                              color: Colors.red.withOpacity(0.4),
                              borderColor: Colors.red,
                              borderStrokeWidth: 1,
                              useRadiusInMeter: true,
                              radius: 150, // Down-scaled to 150 meters per requirement
                            );
                          }).toList(),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
          
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
            
          // GetX Reactive Full-Screen Overlays
          Obx(() {
            if (_sosController.isCountdown.value) {
              return Container(
                color: Colors.black87, // Dramatic Dark Overlay
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 100),
                      const SizedBox(height: 24),
                      Text("Sending alert in ${_sosController.countdownSeconds.value}...", 
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 60),
                      SizedBox(
                        height: 50,
                        width: 200,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                          onPressed: () => _sosController.cancelSOS(),
                          icon: const Icon(Icons.cancel, size: 28),
                          label: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                        ),
                      )
                    ],
                  ),
                ),
              );
            }
            
            if (_sosController.isSent.value) {
               return Container(
                 color: Colors.black87,
                 child: Center(
                   child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                     margin: const EdgeInsets.symmetric(horizontal: 24),
                     decoration: BoxDecoration(
                       color: Colors.grey[900], 
                       borderRadius: BorderRadius.circular(20),
                       border: Border.all(color: Colors.redAccent, width: 2)
                     ),
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         const Text("🚨 SOS ALERT SENT", style: TextStyle(color: Colors.redAccent, fontSize: 26, fontWeight: FontWeight.bold)),
                         const SizedBox(height: 16),
                         const Text("Your exact location and emergency message are prepared.", 
                           style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                         const SizedBox(height: 36),
                         SizedBox(
                           width: double.infinity, 
                           height: 48,
                           child: ElevatedButton.icon(
                             onPressed: _sosController.copyMessage, 
                             icon: const Icon(Icons.copy), 
                             label: const Text("Copy Message", style: TextStyle(fontSize: 16)),
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800], foregroundColor: Colors.white),
                           )
                         ),
                         const SizedBox(height: 12),
                         SizedBox(
                           width: double.infinity, 
                           height: 48,
                           child: ElevatedButton.icon(
                             onPressed: _sosController.shareSOS, 
                             icon: const Icon(Icons.share), 
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), 
                             label: const Text("Share to Apps", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                           )
                         ),
                         const SizedBox(height: 16),
                         const SizedBox(height: 12),
                         SizedBox(
                           width: double.infinity, 
                           height: 48,
                           child: ElevatedButton.icon(
                             onPressed: _sosController.stopActiveSOS, 
                             icon: const Icon(Icons.verified_user), 
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), 
                             label: const Text("MARK AS SAFE (STOP SOS)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                           )
                         ),
                         const SizedBox(height: 16),
                         SizedBox(
                           width: double.infinity, 
                           child: TextButton(
                             onPressed: _sosController.closeAlert, 
                             child: const Text("Keep Running & Close Menu", style: TextStyle(color: Colors.white54, fontSize: 14))
                           )
                         ),
                       ]
                     )
                   )
                 )
               );
            }
            
            if (_sosController.isLoading.value) {
                return Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.red),
                        SizedBox(height: 16),
                        Text("Fetching GPS...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
      floatingActionButton: Obx(() => (_sosController.isCountdown.value || _sosController.isSent.value)
        ? const SizedBox.shrink() // Hide buttons during overlays
        : Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sosController.isActiveBroadcast.value)
                FloatingActionButton.extended(
                  heroTag: 'stopSosBtn',
                  onPressed: () => _sosController.stopActiveSOS(),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.greenAccent,
                  icon: const Icon(Icons.verified_user, size: 28),
                  label: const Text("I'M SAFE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                )
              else
                _PulsingSosButton(
                  onPressed: () => _sosController.initiateSOSWorkflow()
                ),
              const SizedBox(height: 16),
              if (_currentPosition != null && !_isLoading && !_sosController.isLoading.value)
                FloatingActionButton(
                  heroTag: 'locationBtn',
                  onPressed: () {
                    if (_currentPosition != null) {
                      _moveCameraTo(_currentPosition!);
                    }
                  },
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: const Icon(Icons.my_location),
                ),
            ],
          )
      ),
    );
  }
}

// Dedicated Widget handling local repetitive animation states cleanly
class _PulsingSosButton extends StatefulWidget {
  final VoidCallback onPressed;
  
  const _PulsingSosButton({required this.onPressed});

  @override
  _PulsingSosButtonState createState() => _PulsingSosButtonState();
}

class _PulsingSosButtonState extends State<_PulsingSosButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 1-second pulse bounding looping infinitely
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: FloatingActionButton(
        heroTag: 'sosBtnAnimated',
        onPressed: widget.onPressed,
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: const Icon(Icons.sos, size: 28, weight: 800),
      ),
    );
  }
}
