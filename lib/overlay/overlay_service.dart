import 'package:flutter/services.dart';

/// Transport for the optional native floating panel.
///
/// This bridge does not grant capture permission, classify the current game
/// mode, or authorize actions. The controller must enforce those policies for
/// every request, including requests made while the app is in the background.
class OverlayService {
  const OverlayService({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('spider_aim/overlay');

  final MethodChannel _channel;

  Future<Map<String, Object?>> capabilities() => _invokeResult('capabilities');

  /// Opens the platform's permission flow; its result is not capture consent.
  Future<Map<String, Object?>> requestPermission() =>
      _invokeResult('requestPermission');

  Future<Map<String, Object?>> show() => _invokeResult('show');

  Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // No native panel exists on an unsupported platform.
    }
  }

  Future<void> updateState(Map<String, Object?> state) async {
    try {
      await _channel.invokeMethod<void>('updateState', state);
    } on MissingPluginException {
      // Updating a nonexistent panel cannot authorize an action.
    }
  }

  /// Receives native requests as {'action': String, 'payload': Map}.
  ///
  /// Returning an error for malformed input prevents native UI commands from
  /// becoming implicit approvals. Errors from valid requests are propagated to
  /// the native caller, so the controller remains responsible for policy.
  void setRequestHandler(
    Future<Map<String, Object?>> Function(Map<String, Object?> request)? handler,
  ) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'request') {
        return <String, Object?>{
          'ok': false,
          'error': 'unsupported_overlay_method',
        };
      }
      final arguments = call.arguments;
      if (arguments is! Map || arguments.keys.any((key) => key is! String)) {
        return _invalidRequest;
      }
      final action = arguments['action'];
      final payload = arguments['payload'];
      if (action is! String ||
          action.trim().isEmpty ||
          payload is! Map ||
          payload.keys.any((key) => key is! String)) {
        return _invalidRequest;
      }
      return handler(<String, Object?>{
        'action': action,
        'payload': Map<String, Object?>.from(payload),
      });
    });
  }

  void registerRequestHandler(
    Future<Map<String, Object?>> Function(Map<String, Object?> request) handler,
  ) => setRequestHandler(handler);

  void removeRequestHandler() => setRequestHandler(null);

  Future<Map<String, Object?>> _invokeResult(String method) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(method) ??
          <String, Object?>{
            'supported': false,
            'reason': 'overlay_response_unavailable',
          };
    } on MissingPluginException {
      return <String, Object?>{
        'supported': false,
        'reason': 'overlay_unavailable_on_platform',
      };
    }
  }

  static const _invalidRequest = <String, Object?>{
    'ok': false,
    'error': 'invalid_overlay_request',
  };
}
