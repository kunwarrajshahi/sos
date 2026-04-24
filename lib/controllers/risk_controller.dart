import 'dart:async';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/risk_service.dart';

class RiskController extends GetxController {
  static RiskController get instance {
    if (Get.isRegistered<RiskController>()) {
      return Get.find<RiskController>();
    }
    return Get.put(RiskController());
  }

  // Reactive risk score 0 to 100
  var currentRiskScore = Rxn<double>();
  Timer? _pollingTimer;

  void startPolling(Position initialPosition) {
    if (_pollingTimer != null) return; // Already running

    // Immediate first calculation
    _calculateRisk(LatLng(initialPosition.latitude, initialPosition.longitude));

    // Poll every 10 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
       try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        _calculateRisk(LatLng(pos.latitude, pos.longitude));
       } catch (e) {
         // Silently handle generic location retrieval errors during background polling
       }
    });
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _calculateRisk(LatLng location) async {
    double score = await RiskService.calculateRiskScore(location);
    currentRiskScore.value = score;
  }

  @override
  void onClose() {
    stopPolling();
    super.onClose();
  }
}
