import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_device.dart';

class InventoryStore {
  static const _key = 'camera_ip_search_inventory_v1';

  Future<List<CameraDevice>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>()
          .map(CameraDevice.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(Iterable<CameraDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }
}
