import 'dart:math';

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

  /// Generates the 256-bit AES key for a transfer.
  ///
  /// This key is the only thing protecting the file contents: it travels to
  /// the receiver in the link fragment and is never sent to the server. It used
  /// to be a SHA-256 hash of the device UUID, a clock-derived "temperature"
  /// and the timestamp, so anybody who knew the UUID and the approximate send
  /// time could rebuild the key (POTENTIAL_ISSUES #26). It is now drawn from a
  /// cryptographically secure random source.
  ///
  /// The format is unchanged - 32 lowercase hex characters used as raw UTF-8
  /// by the AES-256 cipher - so the app and the website stay compatible.
  static Future<String> generateKey() async {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
