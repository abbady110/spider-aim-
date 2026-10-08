import 'package:flutter/material.dart';
import 'core/coach_controller.dart';
import 'storage/sqlite_coach_store.dart';
import 'overlay/overlay_bridge.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await SqliteCoachStore.open();
    final controller = CoachController(store: store);
    await controller.initialize();
    final overlayBridge = OverlayBridge(controller);
    overlayBridge.attach();
    controller.disposeOverlayBridge = overlayBridge.dispose;
    runApp(SpiderAimApp(controller: controller));
  } catch (_) {
    // Never fall back to a volatile store after a database/open failure.
    runApp(const MaterialApp(home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SafeArea(child: Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('تعذر فتح قاعدة البيانات المحلية. أُوقف التطبيق لحماية النسخ المحفوظة. أعد التشغيل؛ لا تمسح بيانات التطبيق.'),
      )))),
    )));
  }
}
