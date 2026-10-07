import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/device/device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('spider_aim/device');
  const service = DeviceService();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native public report preserves unknown touch sampling and gyro stays off', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'read');
          return {
            'deviceId': 'local-installation-a',
            'name': 'Android tablet',
            'platform': 'android',
            'physicalDevice': true,
            'supported': true,
            'batteryPercent': 62,
            'charging': false,
            'thermal': 'NOMINAL',
            'touchSamplingRateHz': null,
            'gyroscopeEnabled': false,
            'gyroscopeAvailable': true,
          };
        });
    final snapshot = await service.read();
    expect(snapshot.supported, isTrue);
    expect(snapshot.batteryPercent, 62.0);
    expect(snapshot.details['touchSamplingRateHz'], isNull);
    expect(snapshot.details['gyroscopeEnabled'], isFalse);
    expect(snapshot.toJson()['deviceId'], 'local-installation-a');
  });

  test('missing native implementation blocks unknown and desktop devices', () async {
    final snapshot = await service.read();
    expect(snapshot.supported, isFalse);
    expect(snapshot.physicalDevice, isFalse);
    expect(snapshot.batteryPercent, isNull);
    expect(snapshot.thermal, 'UNKNOWN');
  });

  test('emulators and desktop reports cannot enable physical mobile support', () {
    for (final input in [
      {'platform': 'android', 'physicalDevice': false},
      {'platform': 'ios', 'physicalDevice': false},
      {'platform': 'windows', 'physicalDevice': true},
      {'platform': 'linux', 'physicalDevice': true},
      {'platform': 'android'},
    ]) {
      final snapshot = DeviceSnapshot.fromJson({
        'deviceId': 'test',
        'supported': true,
        ...input,
      });
      expect(snapshot.supported, isFalse);
    }
  });

  test('unavailable or invalid battery data must not turn into invented values', () {
    for (final input in [null, -1, 101, double.nan, double.infinity, '50']) {
      expect(DeviceSnapshot.fromJson({'batteryPercent': input}).batteryPercent, isNull);
    }
    expect(DeviceSnapshot.fromJson({'batteryPercent': 0}).batteryPercent, 0);
    expect(DeviceSnapshot.fromJson({'batteryPercent': 100}).batteryPercent, 100);
  });

  test('device identity is independent for phone and tablet installations', () {
    final phone = DeviceSnapshot.fromJson({'deviceId': 'phone-installation'});
    final tablet = DeviceSnapshot.fromJson({'deviceId': 'tablet-installation'});
    expect(phone.deviceId, isNot(tablet.deviceId));
    expect(DeviceSnapshot.fromJson(phone.toJson()).deviceId, phone.deviceId);
  });

  test('platform exceptions fail closed and keep unknown measurements', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'API_UNAVAILABLE');
        });
    final snapshot = await service.read();
    expect(snapshot.supported, isFalse);
    expect(snapshot.charging, isNull);
    expect(snapshot.details['error'], 'API_UNAVAILABLE');
  });

  test('malformed native data fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'not a map');
    final snapshot = await service.read();
    expect(snapshot.supported, isFalse);
  });
}
