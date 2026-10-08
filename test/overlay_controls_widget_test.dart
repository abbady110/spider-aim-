import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/capture/capture_service.dart';
import 'package:spider_aim/core/coach_controller.dart';
import 'package:spider_aim/device/device_service.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/overlay/overlay_service.dart';
import 'package:spider_aim/storage/coach_store.dart';
import 'package:spider_aim/ui/recognition_panel.dart';

/// These tests exercise UI wiring, not native permission dialogs or transport.
class _InertCapture extends CaptureService {
  const _InertCapture();

  @override
  Future<void> stop() async {}
}

class _InertOverlay extends OverlayService {
  const _InertOverlay();

  @override
  Future<void> hide() async {}

  @override
  Future<void> updateState(Map<String, Object?> state) async {}

  @override
  void setRequestHandler(
    Future<Map<String, Object?>> Function(Map<String, Object?> request)? handler,
  ) {}
}

class _UiController extends CoachController {
  _UiController({
    bool captureActive = false,
    bool overlaySupported = true,
    bool permissionGranted = false,
  }) : super(
    store: MemoryCoachStore(),
    captureService: const _InertCapture(),
    overlayService: const _InertOverlay(),
  ) {
    ready = true;
    device = const DeviceSnapshot(
      deviceId: 'overlay-widget-phone',
      name: 'Physical Android phone fixture',
      supported: true,
      physicalDevice: true,
      batteryPercent: 80,
      charging: false,
      thermal: 'nominal',
      details: {'platform': 'android'},
    );
    captureRunning = captureActive;
    captureCapabilities = {'supported': true, 'usageAccessGranted': true};
    overlayCapabilities = {
      'supported': overlaySupported,
      'permissionGranted': permissionGranted,
    };
  }

  int captureRequests = 0;
  int permissionRequests = 0;
  int showRequests = 0;
  int hideRequests = 0;

  @override
  Future<void> startAutomaticRecognition() async {
    captureRequests++;
    captureRunning = true;
    notifyListeners();
  }

  @override
  Future<void> requestOverlayPermission() async {
    permissionRequests++;
    // Opening OS settings is not evidence that permission was granted.
    notifyListeners();
  }

  @override
  Future<void> showOverlay() async {
    showRequests++;
    overlayVisible = true;
    notifyListeners();
  }

  @override
  Future<void> hideOverlay() async {
    hideRequests++;
    overlayVisible = false;
    notifyListeners();
  }
}

ButtonStyleButton _button(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key)));

Future<void> _mount(WidgetTester tester, _UiController controller) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => RecognitionPanel(
            controller: controller,
            showControls: true,
          ),
        ),
      )),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('overlay denial does not disable independent screen capture consent', (tester) async {
    final controller = _UiController();
    await _mount(tester, controller);
    expect(_button(tester, 'recognition-start').onPressed, isNotNull);
    expect(_button(tester, 'overlay-request-permission').onPressed, isNotNull);
    expect(_button(tester, 'overlay-show').onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('recognition-start')));
    await tester.tap(find.byKey(const Key('recognition-start')));
    await tester.pumpAndSettle();
    expect(controller.captureRequests, 1);
    expect(controller.permissionRequests, 0);
    expect(controller.captureRunning, isTrue);
    expect(_button(tester, 'overlay-show').onPressed, isNull);
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final state in [
    (name: 'capture stopped', capture: false, permission: true, supported: true),
    (name: 'permission missing', capture: true, permission: false, supported: true),
    (name: 'platform unsupported', capture: true, permission: true, supported: false),
  ]) {
    testWidgets('floating panel cannot be shown when ${state.name}', (tester) async {
      final controller = _UiController(
        captureActive: state.capture,
        permissionGranted: state.permission,
        overlaySupported: state.supported,
      );
      await _mount(tester, controller);
      expect(_button(tester, 'overlay-show').onPressed, isNull);
      expect(controller.showRequests, 0);
      expect(controller.guard.allowed, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('UNKNOWN can show and hide the permitted panel without unlocking calibration', (tester) async {
    final controller = _UiController(captureActive: true, permissionGranted: true);
    await _mount(tester, controller);
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(_button(tester, 'overlay-show').onPressed, isNotNull);
    expect(find.byKey(const Key('overlay-hide')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('overlay-show')));
    await tester.tap(find.byKey(const Key('overlay-show')));
    await tester.pumpAndSettle();
    expect(controller.showRequests, 1);
    expect(controller.overlayVisible, isTrue);
    expect(controller.guard.allowed, isFalse);
    expect(_button(tester, 'overlay-show').onPressed, isNull);
    expect(_button(tester, 'overlay-hide').onPressed, isNotNull);
    await tester.ensureVisible(find.byKey(const Key('overlay-hide')));
    await tester.tap(find.byKey(const Key('overlay-hide')));
    await tester.pumpAndSettle();
    expect(controller.hideRequests, 1);
    expect(controller.overlayVisible, isFalse);
    expect(find.byKey(const Key('overlay-hide')), findsNothing);
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlay permission button requests permission without assuming consent', (tester) async {
    final controller = _UiController();
    await _mount(tester, controller);
    await tester.ensureVisible(find.byKey(const Key('overlay-request-permission')));
    await tester.tap(find.byKey(const Key('overlay-request-permission')));
    await tester.pumpAndSettle();
    expect(controller.permissionRequests, 1);
    expect(controller.overlayCapabilities['permissionGranted'], isFalse);
    expect(controller.captureRequests, 0);
    expect(controller.showRequests, 0);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture and overlay controls precede recognition evidence on a phone', (tester) async {
    final controller = _UiController();
    await _mount(tester, controller);
    final capture = find.byKey(const Key('recognition-start'));
    final overlay = find.byKey(const Key('overlay-request-permission'));
    final detectedMode = find.byKey(const Key('recognition-mode-code'));
    expect(capture.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(capture).dy, lessThan(tester.getTopLeft(overlay).dy));
    expect(tester.getTopLeft(overlay).dy, lessThan(tester.getTopLeft(detectedMode).dy));
    expect(tester.takeException(), isNull);
  });
}
