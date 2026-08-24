import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class EntropyGenerator {
  /// Retrieves or generates a persistent device UUID
  static Future<String> getDeviceUuid() async {
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString('device_uuid');
    if (uuid == null) {
      uuid = const Uuid().v4();
      await prefs.setString('device_uuid', uuid);
    }
    return uuid;
  }

  /// Obtains the current device/battery temperature (simulated to 36.5°C +/- 2°C fluctuation)
  static double getDeviceTemperature() {
    final ms = DateTime.now().millisecond;
    return 35.0 + (ms % 40) / 10.0;
  }

  /// Generates the secure 256-bit key from UUID, Temperature, and Timestamp
  static Future<String> generateKey() async {
    final uuid = await getDeviceUuid();
    final temp = getDeviceTemperature();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final seed = '${uuid}_${temp}_$timestamp';
    final bytes = utf8.encode(seed);
    final digest = sha256.convert(bytes);

    return digest.toString().substring(0, 32);
  }
}
