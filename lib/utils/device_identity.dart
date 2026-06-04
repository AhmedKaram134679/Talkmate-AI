import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  static const String _deviceIdKey = 'device_id';

  /// Returns a persistent unique ID for this device.
  /// Generates a new one and saves it if it doesn't exist.
  static Future<String> getId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);

    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
    }

    return id;
  }
}
