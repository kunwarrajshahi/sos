import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SosSettingsController extends GetxController {
  static SosSettingsController instanceOrCreate() {
    if (Get.isRegistered<SosSettingsController>()) {
      return Get.find<SosSettingsController>();
    }
    return Get.put(SosSettingsController());
  }

  static const String _prefsKey = 'sos_activation_delay_seconds';
  final RxInt activationDelaySeconds = 10.obs;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    activationDelaySeconds.value = prefs.getInt(_prefsKey) ?? 10;
  }

  Future<void> setActivationDelay(int seconds) async {
    activationDelaySeconds.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, seconds);
  }
}
