import 'package:flutter/services.dart';

/// Android MediaProjection bridge. No pixels or raw OCR text cross into Dart;
/// only bounded local evidence. iOS cross-app capture needs a provisioned
/// ReplayKit Broadcast Upload extension; without it this reports unsupported.
class CaptureService {
  const CaptureService({MethodChannel? methods, EventChannel? eventChannel})
    : _methods = methods ?? const MethodChannel('spider_aim/capture'),
      _events = eventChannel ?? const EventChannel('spider_aim/capture/events');

  final MethodChannel _methods;
  final EventChannel _events;

  Future<Map<String, dynamic>> capabilities() async {
    try {
      final result = await _methods.invokeMapMethod<String, dynamic>('capabilities');
      return result ?? {'supported': false, 'reason': 'capture_capabilities_unavailable'};
    } on MissingPluginException {
      return {'supported': false, 'reason': 'authorized_cross_app_capture_unavailable'};
    } on PlatformException catch (error) {
      return {'supported': false, 'reason': error.code};
    }
  }

  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  Future<Map<String, dynamic>> start() async {
    try {
      final result = await _methods.invokeMapMethod<String, dynamic>('start');
      return result ?? {'supported': false, 'started': false, 'reason': 'capture_not_started'};
    } on MissingPluginException {
      return {'supported': false, 'started': false,
        'reason': 'authorized_cross_app_capture_unavailable'};
    }
  }

  Future<void> stop() async {
    try {
      await _methods.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Unsupported platforms are already blocked by capabilities/start.
    }
  }

  Future<void> requestUsageAccess() async {
    await _methods.invokeMethod<void>('requestUsageAccess');
  }
}
