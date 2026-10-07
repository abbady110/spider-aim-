import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/core/coach_controller.dart';
import 'package:spider_aim/device/device_service.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/storage/coach_store.dart';
import 'package:spider_aim/ui/app.dart';
import 'package:spider_aim/ui/forms.dart';

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

Future<CoachController> _controller({bool supported = true}) async {
  final controller = CoachController(store: MemoryCoachStore(), deviceService: _Device(supported: supported));
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
    final controller = CoachController(store: MemoryCoachStore(), deviceService: const _FailingDevice());
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

  testWidgets('Ranked disables observation and proposal actions', (tester) async {
    _phone(tester);
    final controller = await _controller();
    await controller.selectMode(GameMode.rankedBlocked);
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
    expect(controller.state['observations'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual declaration enables offline review only; background locks again', (tester) async {
    _phone(tester);
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(SpiderAimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأمان'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('نتائج Warehouse'));
    await tester.tap(find.text('نتائج Warehouse'));
    await tester.pumpAndSettle();
    expect(controller.guard.allowed, isTrue);
    expect(controller.guard.liveAllowed, isFalse);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(controller.guard.mode, GameMode.unknownBlocked);
    expect(controller.guard.allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('baseline form has empty sensitivity and rejects missing values', (tester) async {
    final controller = await _controller();
    await controller.selectMode(GameMode.training);
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

  testWidgets('zero ADS baseline never crashes or generates an ADS suggestion', (tester) async {
    _phone(tester);
    final controller = await _controller();
    await controller.selectMode(GameMode.training);
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
    await controller.selectMode(GameMode.warehouse);
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
