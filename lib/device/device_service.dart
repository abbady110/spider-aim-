import 'dart:convert';

import 'package:flutter/services.dart';

/// A point-in-time report from public platform APIs. Null means unavailable.
/// Refresh rates describe the display, never PUBG's frame rate. The local UUID
/// identifies an installation and is not a hardware/advertising identifier.
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.deviceId,
    required this.name,
    required this.supported,
    required this.physicalDevice,
    required this.batteryPercent,
    required this.charging,
    required this.thermal,
    required this.details,
  });

  final String deviceId;
  final String name;
  final bool supported;
  final bool physicalDevice;
  final double? batteryPercent;
  final bool? charging;
  final String thermal;
  final Map<String, Object?> details;

  factory DeviceSnapshot.fromJson(Map<String, Object?> json) {
    final platform = json['platform'];
    final physical = json['physicalDevice'] == true;
    final mobile = platform == 'android' || platform == 'ios';
    final battery = json['batteryPercent'];
    final value = battery is num ? battery.toDouble() : null;
    final id = json['deviceId'];
    final validId = id is String && id.isNotEmpty;
    return DeviceSnapshot(
      deviceId: validId ? id : 'UNKNOWN',
      name: json['name'] is String ? json['name']! as String : 'غير معروف',
      supported: json['supported'] == true && mobile && physical && validId,
      physicalDevice: physical,
      batteryPercent: value != null && value.isFinite && value >= 0 && value <= 100
          ? value
          : null,
      charging: json['charging'] is bool ? json['charging']! as bool : null,
      thermal: json['thermal'] is String ? json['thermal']! as String : 'UNKNOWN',
      details: Map<String, Object?>.unmodifiable(json),
    );
  }

  Map<String, Object?> toJson() => {
    ...details,
    'deviceId': deviceId,
    'name': name,
    'supported': supported,
    'physicalDevice': physicalDevice,
    'batteryPercent': batteryPercent,
    'charging': charging,
    'thermal': thermal,
  };

  String encode() => jsonEncode(toJson());
}

class DeviceService {
  const DeviceService({MethodChannel channel = const MethodChannel('spider_aim/device')})
    : _channel = channel;

  final MethodChannel _channel;

  /// No permissions or gyroscope subscriptions are requested by this call.
  /// Absence/failure of the native implementation must never unlock support.
  Future<DeviceSnapshot> read() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('read');
      return DeviceSnapshot.fromJson(result ?? const {});
    } on MissingPluginException {
      return DeviceSnapshot.fromJson(const {'availability': 'UNSUPPORTED_PLATFORM'});
    } on PlatformException catch (error) {
      return DeviceSnapshot.fromJson({'availability': 'UNKNOWN', 'error': error.code});
    } on FormatException {
      return DeviceSnapshot.fromJson(const {'availability': 'INVALID_DEVICE_REPORT'});
    } on TypeError {
      return DeviceSnapshot.fromJson(const {'availability': 'INVALID_DEVICE_REPORT'});
    }
  }
}
