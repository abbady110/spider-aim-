import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/capture/capture_service.dart';
import 'package:spider_aim/core/coach_controller.dart';
import 'package:spider_aim/device/device_service.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/storage/coach_store.dart';
import 'package:spider_aim/ui/app.dart';
import 'package:spider_aim/ui/forms.dart';

import 'support/recognized_guard.dart';

class _Device extends DeviceService {
  const _Device({this.supported = true});
  final bool supported;
  @override
  Future<DeviceSnapshot> read() async => DeviceSnapshot(
    deviceId: 'widget-phone', name: 'Test physical phone', supported: supported,
    physicalDevice: supported, batteryPercent: 78, charging: false,
    thermal: 'nominal', details: const {'platform': 'android', 'touchSamplingRateHz': null},
  );
}

class _FailingDevice extends DeviceService {
  const _FailingDevice();
  @override
  Future<DeviceSnapshot> read() async => throw StateError('Device report unavailable');
}

/// Widget tests must not wait on real platform messages inside fake async.
class _UnavailableCapture extends CaptureService {
  const _UnavailableCapture();

  @override
  Future<Map<String, dynamic>> capabilities() async => {'supported': false};

  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();

  @override
  Future<Map<String, dynamic>> start() async => {'supported': false, 'started': false};

  @override
  Future<void> stop() async {}

  @override
  Future<void> requestUsageAccess() async {}
}

class _CaptureEventStream extends Stream<Map<String, dynamic>> {
  _CaptureEventStream(this.inner);
  final Stream<Map<String, dynamic>> inner;

  @override
  StreamSubscription<Map<String, dynamic>> listen(
    void Function(Map<String, dynamic>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _CaptureSubscription(inner.listen(
    onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError,
  ));
}

class _CaptureSubscription implements StreamSubscription<Map<String, dynamic>> {
  _CaptureSubscription(this.inner);
  final StreamSubscription<Map<String, dynamic>> inner;

  @override
  Future<void> cancel() {
    // Broadcast mock listeners are removed synchronously. A fresh acknowledgement
    // belongs to this widget's fake zone; the SDK's shared completed cancellation
    // future can belong to the outer zone and stall an awaited widget action.
    // This adapter is test-only; production still awaits native stream cleanup.
    unawaited(inner.cancel());
    return Future<void>.value();
  }

  @override
  void onData(void Function(Map<String, dynamic>)? handleData) => inner.onData(handleData);
  @override
  void onError(Function? handleError) => inner.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => inner.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => inner.pause(resumeSignal);
  @override
  void resume() => inner.resume();
  @override
  bool get isPaused => inner.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => inner.asFuture<E>(futureValue);
}

class _Capture extends CaptureService {
  _Capture({this.supported = true, this.consentGranted = true});
  final bool supported;
  final bool consentGranted;
  final frames = StreamController<Map<String, dynamic>>.broadcast();
  int startRequests = 0;
  int stopRequests = 0;

  @override
  Stream<Map<String, dynamic>> get events => _CaptureEventStream(frames.stream);

  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'supported': supported, 'usageAccessGranted': true, 'platform': 'android',
  };

  @override
  Future<Map<String, dynamic>> start() async {
    startRequests++;
    return {
      'supported': supported, 'started': consentGranted,
      if (consentGranted) 'sessionId': 'widget-capture',
      if (!consentGranted) 'reason': 'screen_consent_denied',
    };
  }

  @override
  Future<void> stop() async { stopRequests++; }

  @override
  Future<void> requestUsageAccess() async {}

  void emitWarehouseEvidence() {
    for (var index = 0; index < 4; index++) {
      frames.add({
        'type': 'frame',
        'sessionId': 'widget-capture',
        'sequence': index + 1,
        'frameFingerprint': 'synthetic-widget-pixels-$index',
        'timestampMs': recognitionFixtureTime
            .subtract(Duration(seconds: 7 - index * 2)).millisecondsSinceEpoch,
        'captureAuthorized': true,
        'foregroundPackage': 'com.tencent.ig',
        'foregroundVerified': true,
        'cues': safeScreenCues(GameMode.warehouseSafe).map((cue) => {
          'id': cue.id, 'confidence': cue.confidence, 'region': cue.region,
        }).toList(),
      });
    }
  }
}

class _PendingCapture extends _Capture {
  final startCalled = Completer<void>();
  final startReply = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> start() {
    startRequests++;
    startCalled.complete();
    return startReply.future;
  }

  void completeStarted() => startReply.complete({
    'supported': true, 'started': true, 'sessionId': 'widget-capture',
  });
}

Future<CoachController> _controller({bool supported = true, CaptureService? capture}) async {
  final controller = CoachController(
    store: MemoryCoachStore(),
    deviceService: _Device(supported: supported),
    gameModeGuard: GameModeGuard(now: () => recognitionFixtureTime),
    captureService: capture ?? const _UnavailableCapture(),
  );
  await controller.initialize();
  return controller;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('phone starts RTL with unknown mode and no invented aim score', (tester) async {
    _phone(tester);
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.byType(Scaffold))), TextDirection.rtl);
    expect(find.text('كل تحسّن يبدأ بثبات.'), findsOneWidget);
    expect(find.text('NON-GYRO · TOUCH ONLY'), findsWidgets);
    expect(find.text('غير متاح'), findsWidgets);
    expect(controller.guard.allowed, isFalse);
    expect(controller.recognition.confidence, 0);
    expect(controller.recognition.frameCount, 0);
    expect(find.text('UNKNOWN_BLOCKED'), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const Key('recognition-confidence'))).data, '0%');
    expect(find.text('97%'), findsNothing);
    expect(find.text('31'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emulator or unsupported platform cannot enter coaching shell', (tester) async {
    _phone(tester);
    final controller = await _controller(supported: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('جهاز غير مدعوم'), findsOneWidget);
    expect(find.text('كل تحسّن يبدأ بثبات.'), findsNothing);
    expect(controller.guard.allowed, isFalse);
  });

  testWidgets('failed device initialization remains blocked', (tester) async {
    _phone(tester);
    final controller = CoachController(
      store: MemoryCoachStore(), deviceService: const _FailingDevice(),
      captureService: const _UnavailableCapture(),
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('جهاز غير مدعوم'), findsOneWidget);
    expect(find.text('كل تحسّن يبدأ بثبات.'), findsNothing);
    expect(controller.device, isNull);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detected Battle Royale disables observation and proposal actions', (tester) async {
    _phone(tester);
    final controller = await _controller();
    observeCompetitiveSession(controller.guard);
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المعايرة'));
    await tester.pumpAndSettle();
    final sample = tester.widget<ButtonStyleButton>(find.ancestor(
      of: find.text('تسجيل عينة اختبار فعلية'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ));
    final proposal = tester.widget<ButtonStyleButton>(find.ancestor(
      of: find.text('اقتراح خطوة صغيرة من الدليل'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ));
    expect(sample.onPressed, isNull);
    expect(proposal.onPressed, isNull);
    expect(controller.guard.mode, GameMode.competitiveBlocked);
    expect(controller.state['observations'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical mode choices never unlock an unknown live session', (tester) async {
    _phone(tester);
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأمان'));
    await tester.pumpAndSettle();
    for (final label in ['سجل Training', 'سجل Warehouse', 'سجل Unranked', 'سجل Arena']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(controller.guard.mode, GameMode.unknownBlocked, reason: label);
      expect(controller.guard.allowed, isFalse, reason: label);
      expect(controller.guard.liveAllowed, isFalse, reason: label);
    }
    expect(controller.state['observations'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical Warehouse cannot clear a detected competitive latch', (tester) async {
    _phone(tester);
    final controller = await _controller();
    observeCompetitiveSession(controller.guard);
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأمان'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('سجل Warehouse'));
    await tester.tap(find.text('سجل Warehouse'));
    await tester.pumpAndSettle();
    expect(controller.guard.mode, GameMode.competitiveBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(controller.recognition.evidence, contains('مرحلة الطائرة'));
    expect(find.text('COMPETITIVE_BLOCKED'), findsWidgets);
    expect(find.byKey(const Key('recognition-br-latch')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recognition panel shows measured evidence and loses permission on invalidation', (tester) async {
    _phone(tester);
    final controller = await _controller();
    observeSafeSession(controller.guard, mode: GameMode.warehouseSafe, confidence: .98);
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.guard.allowed, isTrue);
    expect(controller.recognition.confidence, closeTo(.98, .0001));
    expect(controller.recognition.frameCount, 4);
    expect(tester.widget<Text>(find.byKey(const Key('recognition-mode-code'))).data, 'WAREHOUSE_SAFE');
    expect(tester.widget<Text>(find.byKey(const Key('recognition-confidence'))).data, '98%');
    expect(tester.widget<Text>(find.byKey(const Key('recognition-frame-count'))).data, '4');
    expect(find.text('WAREHOUSE_SAFE'), findsWidgets);
    expect(find.textContaining('تسمية Warehouse من الشاشة'), findsWidgets);
    expect(find.textContaining('واجهة نقاط الفريقين'), findsWidgets);
    controller.guard.invalidate();
    await controller.selectMode(GameMode.warehouseSafe);
    await tester.pumpAndSettle();
    expect(controller.guard.allowed, isFalse);
    expect(find.text('UNKNOWN_BLOCKED'), findsWidgets);
    expect(find.text('WAREHOUSE_SAFE'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('recognition-confidence'))).data, '0%');
    expect(tester.widget<Text>(find.byKey(const Key('recognition-frame-count'))).data, '0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen consent starts locked until evidence and stopping capture relocks', (tester) async {
    _phone(tester);
    final capture = _Capture();
    final controller = await _controller(capture: capture);
    addTearDown(() async {
      controller.dispose();
      await capture.frames.close();
    });
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأمان'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('بدء التعرف التلقائي'));
    await tester.tap(find.text('بدء التعرف التلقائي'));
    await tester.pumpAndSettle();
    expect(capture.startRequests, 1);
    expect(controller.captureRunning, isTrue);
    expect(controller.guard.allowed, isFalse);
    expect(controller.recognition.frameCount, 0);
    capture.emitWarehouseEvidence();
    await tester.pumpAndSettle();
    expect(controller.guard.mode, GameMode.warehouseSafe);
    expect(controller.guard.allowed, isTrue);
    expect(tester.widget<Text>(find.byKey(const Key('recognition-frame-count'))).data, '4');
    await tester.ensureVisible(find.text('إيقاف التقاط الشاشة'));
    await tester.tap(find.text('إيقاف التقاط الشاشة'));
    await tester.pumpAndSettle();
    expect(capture.stopRequests, 1);
    expect(controller.captureRunning, isFalse);
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported screen capture disables recognition start and remains locked', (tester) async {
    _phone(tester);
    final capture = _Capture(supported: false);
    final controller = await _controller(capture: capture);
    addTearDown(() async {
      controller.dispose();
      await capture.frames.close();
    });
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأمان'));
    await tester.pumpAndSettle();
    final start = find.ancestor(
      of: find.text('بدء التعرف التلقائي'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(start).onPressed, isNull);
    expect(capture.startRequests, 0);
    expect(controller.captureRunning, isFalse);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied system screen consent never opens calibration', (tester) async {
    _phone(tester);
    final capture = _Capture(consentGranted: false);
    final controller = await _controller(capture: capture);
    addTearDown(() async {
      controller.dispose();
      await capture.frames.close();
    });
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأمان'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('بدء التعرف التلقائي'));
    await tester.tap(find.text('بدء التعرف التلقائي'));
    await tester.pumpAndSettle();
    capture.emitWarehouseEvidence();
    await tester.pumpAndSettle();
    expect(capture.startRequests, 1);
    expect(controller.captureRunning, isFalse);
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(controller.recognition.frameCount, 0);
    expect(controller.error, contains('screen_consent_denied'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture stream failure immediately revokes recognized permission', (tester) async {
    _phone(tester);
    final capture = _Capture();
    final controller = await _controller(capture: capture);
    addTearDown(() async {
      controller.dispose();
      await capture.frames.close();
    });
    await controller.startAutomaticRecognition();
    capture.emitWarehouseEvidence();
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.guard.allowed, isTrue);
    capture.frames.addError(StateError('capture_stream_disconnected'));
    await tester.pumpAndSettle();
    expect(controller.captureRunning, isFalse);
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(find.text('UNKNOWN_BLOCKED'), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const Key('recognition-confidence'))).data, '0%');
    expect(tester.takeException(), isNull);
  });

  for (final malformed in <String, Map<String, dynamic>>{
    'missing event type': {'sessionId': 'widget-capture'},
    'unknown event type': {'type': 'unexpected', 'sessionId': 'widget-capture'},
    'mismatched session': {'type': 'status', 'started': true, 'sessionId': 'other-session'},
  }.entries) {
    testWidgets('${malformed.key} revokes an already verified capture session', (tester) async {
      _phone(tester);
      final capture = _Capture();
      final controller = await _controller(capture: capture);
      addTearDown(() async {
        controller.dispose();
        await capture.frames.close();
      });
      await controller.startAutomaticRecognition();
      capture.emitWarehouseEvidence();
      await tester.pumpWidget(SpiderAimApp(controller: controller));
      await tester.pumpAndSettle();
      expect(controller.guard.allowed, isTrue);
      capture.frames.add(malformed.value);
      await tester.pumpAndSettle();
      expect(controller.captureRunning, isFalse);
      expect(controller.guard.mode, GameMode.unknownBlocked);
      expect(controller.recognition.frameCount, 0);
      expect(capture.stopRequests, greaterThan(0));
      capture.emitWarehouseEvidence();
      await tester.pumpAndSettle();
      expect(controller.guard.allowed, isFalse);
      expect(find.text('UNKNOWN_BLOCKED'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final terminal in ['stopped', 'error']) {
    testWidgets('$terminal during consent cannot be resurrected by a late success response', (tester) async {
      _phone(tester);
      final capture = _PendingCapture();
      final controller = await _controller(capture: capture);
      addTearDown(() async {
        controller.dispose();
        await capture.frames.close();
      });
      await tester.pumpWidget(SpiderAimApp(controller: controller));
      final rejectedStart = expectLater(controller.startAutomaticRecognition(), throwsStateError);
      await capture.startCalled.future;
      capture.frames.add({
        'type': terminal, 'sessionId': 'widget-capture', 'reason': 'native_capture_terminated',
      });
      await tester.pump();
      capture.completeStarted();
      await rejectedStart;
      await tester.pumpAndSettle();
      capture.emitWarehouseEvidence();
      await tester.pumpAndSettle();
      expect(controller.captureRunning, isFalse);
      expect(controller.guard.mode, GameMode.unknownBlocked);
      expect(controller.guard.allowed, isFalse);
      expect(controller.recognition.frameCount, 0);
      expect(capture.stopRequests, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('initial idle status preserves consent request without granting calibration', (tester) async {
    _phone(tester);
    final capture = _PendingCapture();
    final controller = await _controller(capture: capture);
    addTearDown(() async {
      controller.dispose();
      await capture.frames.close();
    });
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    final pendingStart = controller.startAutomaticRecognition();
    await capture.startCalled.future;
    capture.frames.add({'type': 'status', 'started': false});
    await tester.pump();
    capture.completeStarted();
    await pendingStart;
    await tester.pumpAndSettle();
    expect(controller.captureRunning, isTrue);
    expect(controller.guard.allowed, isFalse);
    expect(controller.recognition.frameCount, 0);
    await controller.stopAutomaticRecognition();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final competitive in [false, true]) {
    testWidgets('returning to coach revokes safe proof and preserves competitive=$competitive', (tester) async {
      _phone(tester);
      final capture = _Capture();
      final controller = await _controller(capture: capture);
      addTearDown(() async {
        controller.dispose();
        await capture.frames.close();
      });
      await controller.startAutomaticRecognition();
      capture.emitWarehouseEvidence();
      await tester.pumpWidget(SpiderAimApp(controller: controller));
      await tester.pumpAndSettle();
      expect(controller.guard.allowed, isTrue);
      if (competitive) {
        capture.frames.add({
          'type': 'frame', 'sessionId': 'widget-capture', 'sequence': 5,
          'frameFingerprint': 'synthetic-flight-pixels',
          'timestampMs': recognitionFixtureTime.millisecondsSinceEpoch,
          'captureAuthorized': true, 'foregroundPackage': 'com.tencent.ig',
          'foregroundVerified': true,
          'cues': [{'id': 'airplane', 'confidence': .99, 'region': 'center'}],
        });
        await tester.pumpAndSettle();
      }
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.captureRunning, isTrue);
      expect(controller.guard.allowed, isFalse);
      expect(controller.guard.mode, competitive
          ? GameMode.competitiveBlocked : GameMode.unknownBlocked);
      expect(controller.competitiveLatched, competitive);
      await controller.stopAutomaticRecognition();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('baseline form has empty sensitivity and rejects missing values', (tester) async {
    final controller = await _controller();
    observeSafeSession(controller.guard, mode: GameMode.trainingSafe);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BaselineForm(controller: controller))));
    await tester.pumpAndSettle();
    for (final field in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.controller?.text, isEmpty);
    }
    await tester.ensureVisible(find.text('حفظ المرجع الحالي'));
    await tester.tap(find.text('حفظ المرجع الحالي'));
    await tester.pumpAndSettle();
    expect((controller.state['approved'] as Map)['settings'], isEmpty);
    expect(find.text('أدخل الملحقات أو None'), findsOneWidget);
  });

  testWidgets('open baseline form disables saving as soon as recognition is invalidated', (tester) async {
    _phone(tester);
    final controller = await _controller();
    observeSafeSession(controller.guard, mode: GameMode.trainingSafe);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BaselineForm(controller: controller))));
    await tester.pumpAndSettle();
    final save = find.ancestor(
      of: find.text('حفظ المرجع الحالي'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    await tester.ensureVisible(save);
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNotNull);
    controller.guard.invalidate();
    await controller.selectMode(GameMode.trainingSafe);
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNull);
    expect((controller.state['approved'] as Map)['settings'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero ADS baseline never crashes or generates an ADS suggestion', (tester) async {
    _phone(tester);
    final controller = await _controller();
    observeSafeSession(controller.guard, mode: GameMode.trainingSafe);
    await controller.saveBaseline({'M416|3x|Compensator|50::ads': 0});
    await controller.addObservation('aim', {
      'context': 'M416|3x|Compensator|50',
      'metrics': {'aimStability': 70},
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المعايرة'));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة الاقتراح قبل حفظه'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proposal screen never offers final approval before a passed test', (tester) async {
    _phone(tester);
    final controller = await _controller();
    observeSafeSession(controller.guard, mode: GameMode.warehouseSafe);
    await controller.saveBaseline({'M416|3x|Compensator|50::ads': 31});
    for (var i = 0; i < 5; i++) {
      await controller.addObservation('aim', {'context': 'M416|3x|Compensator|50', 'metrics': {
        'aimStability': 60, 'hitRate': 55, 'sprayGrouping': 10, 'trackingScore': 65,
        'overshootRate': 20, 'undershootRate': 10, 'acquisitionMs': 400,
        'adsStability': 65, 'movementRetention': 65, 'fpsStability': 95,
        'thermalImpact': 1, 'batteryDrain': 12,
      }});
    }
    await controller.propose(key: 'M416|3x|Compensator|50::ads', proposed: 30, reason: 'تجاوز الهدف بصورة متكررة', evidence: 'خمس عينات من الاختبار', sampleCount: 5, expected: 'تحسن ثبات التصويب', risk: 'قد يزيد زمن التقاط الهدف');
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المقترحات'));
    await tester.pumpAndSettle();
    expect(find.text('أوافق على الاعتماد النهائي'), findsNothing);
    await tester.ensureVisible(find.text('موافقة على التجربة + Backup'));
    await tester.tap(find.text('موافقة على التجربة + Backup'));
    await tester.pumpAndSettle();
    expect((controller.state['backups'] as List).length, 1);
    expect((controller.state['proposals'] as List).single['status'], 'TESTING');
    expect((controller.state['approved'] as Map)['settings'], {'M416|3x|Compensator|50::ads': 31.0});
    expect(find.text('أوافق على الاعتماد النهائي'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet navigation renders all pages without overflow or fake data', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    for (final destination in destinations) {
      final tile = find.widgetWithText(ListTile, destination.label);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: destination.label);
    }
  });
}
