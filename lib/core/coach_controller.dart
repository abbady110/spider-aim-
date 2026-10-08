import 'dart:async';
import 'package:flutter/widgets.dart';
import '../capture/capture_service.dart';
import '../device/device_service.dart';
import '../game_mode_guard/game_mode_guard.dart';
import '../game_mode_recognition/recognition_models.dart';
import '../overlay/overlay_service.dart';
import '../storage/coach_store.dart';
import 'calibration_workflow.dart';

class CoachController extends ChangeNotifier with WidgetsBindingObserver {
  CoachController({required this.store, DeviceService? deviceService,
    GameModeGuard? gameModeGuard, CaptureService? captureService,
    OverlayService? overlayService})
    : deviceService = deviceService ?? const DeviceService(),
      guard = gameModeGuard ?? GameModeGuard(),
      captureService = captureService ?? const CaptureService(),
      overlayService = overlayService ?? const OverlayService();
  final CoachStore store;
  final DeviceService deviceService;
  final GameModeGuard guard;
  final CaptureService captureService;
  final OverlayService overlayService;
  Map<String, dynamic> overlayCapabilities = const {'supported': false, 'permissionGranted': false};
  bool overlayVisible = false;
  VoidCallback? disposeOverlayBridge;
  RecognitionDecision get recognition => guard.recognition;
  bool get competitiveLatched => guard.competitiveLatched;
  bool captureRunning = false;
  Map<String, dynamic> captureCapabilities = const {'supported': false};
  GameMode? reviewMode;
  StreamSubscription<Map<String, dynamic>>? _captureSubscription;
  Timer? _verificationTimer;
  String? _captureSession;
  bool _captureStarting = false;
  bool _captureStreamHealthy = false;
  bool _disposed = false;
  bool ready = false;
  bool busy = false;
  String? error;
  DeviceSnapshot? device;
  StateMap _state = emptyState('UNKNOWN');
  StateMap get state => cloneState(_state);
  CalibrationWorkflow? _workflow;
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await refreshDevice();
      await refreshCaptureCapabilities();
      await refreshOverlayCapabilities();
    } catch (e) {
      error = e.toString();
    } finally {
      ready = true;
      notifyListeners();
    }
  }
  Future<void> refreshCaptureCapabilities() async {
    captureCapabilities = await captureService.capabilities();
    if (!_disposed) notifyListeners();
  }
  Future<void> refreshOverlayCapabilities() async {
    try {
      overlayCapabilities = await overlayService.capabilities();
      if (overlayCapabilities['permissionGranted'] != true && overlayVisible) {
        await hideOverlay();
      }
    } catch (e) {
      overlayCapabilities = {'supported': false, 'permissionGranted': false, 'reason': '$e'};
      overlayVisible = false;
      error = 'تعذر التحقق من إذن اللوحة العائمة: $e';
    }
    if (!_disposed) notifyListeners();
  }
  Future<void> requestOverlayPermission() async {
    await overlayService.requestPermission();
    await refreshOverlayCapabilities();
  }
  Future<void> showOverlay() async {
    await refreshOverlayCapabilities();
    if (!captureRunning || overlayCapabilities['supported'] != true ||
        overlayCapabilities['permissionGranted'] != true) {
      throw StateError('يلزم بدء الالتقاط ومنح إذن الظهور فوق التطبيقات الأخرى.');
    }
    final result = await overlayService.show();
    overlayVisible = result['visible'] == true;
    if (!_disposed) notifyListeners();
    if (!overlayVisible) {
      throw StateError('تعذر إظهار اللوحة العائمة: ${result['reason'] ?? 'UNKNOWN'}');
    }
  }
  Future<void> hideOverlay() async {
    overlayVisible = false;
    if (!_disposed) notifyListeners();
    await overlayService.hide();
  }
  Future<void> refreshDevice() async {
    final snapshot = await deviceService.read();
    if (device?.deviceId != snapshot.deviceId) {
      guard.invalidate();
    }
    device = snapshot;
    if (snapshot.supported) {
      await store.saveDevice(snapshot.deviceId, snapshot.toJson());
      _workflow = CalibrationWorkflow(store: store, guard: guard, deviceId: snapshot.deviceId);
      _state = await _workflow!.read();
    } else {
      _workflow = null;
      _state = emptyState(snapshot.deviceId);
      guard.invalidate();
    }
    notifyListeners();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (captureRunning) {
        // Returning to our UI is not evidence that PUBG is still foreground.
        // Revoke immediately, before the next native foreground poll arrives.
        guard.invalidateEvidence('عاد SPIDER AIM إلى المقدمة؛ يلزم تحقق جديد من PUBG.');
        notifyListeners();
      }
      // Usage Access is an OS settings screen. Returning must refresh its real
      // permission state, never assume it was granted from opening that screen.
      unawaited(refreshCaptureCapabilities());
      unawaited(refreshOverlayCapabilities());
    } else if (!captureRunning && !_captureStarting) {
      guard.invalidate();
      notifyListeners();
    }
    // Authorized Android foreground capture continues while PUBG is active.
    // The native verifier, not this app's lifecycle, confirms foreground PUBG.
  }
  Future<void> selectMode(GameMode mode) async {
    // Historical filtering only. This can neither begin capture nor unlock.
    reviewMode = mode;
    notifyListeners();
  }
  Future<void> requestUsageAccess() async {
    await captureService.requestUsageAccess();
    await refreshCaptureCapabilities();
  }
  Future<void> startAutomaticRecognition() async {
    if (_captureStarting || captureRunning) return;
    if (device?.supported != true) {
      throw StateError('التقاط الشاشة متاح فقط على جهاز فعلي مدعوم.');
    }
    _captureStarting = true;
    error = null;
    guard.invalidate();
    try {
      await refreshCaptureCapabilities();
      if (captureCapabilities['supported'] != true) {
        throw StateError('التقاط شاشة التطبيقات الأخرى المصرّح به غير متاح '
            'على هذه المنصة: ${captureCapabilities['reason']}');
      }
      await _captureSubscription?.cancel();
      _captureStreamHealthy = true;
      _captureSubscription = captureService.events.listen(_handleCaptureEvent,
        onError: (Object eventError) {
          _rejectCaptureEvent('فقد اتصال التقاط الشاشة: $eventError');
        }, onDone: () {
          _rejectCaptureEvent('انتهى اتصال التقاط الشاشة.');
        });
      final result = await captureService.start();
      final id = result['sessionId'];
      if (_disposed) {
        await captureService.stop();
        return;
      }
      if (!_captureStreamHealthy) {
        throw StateError('اتصال التقاط الشاشة غير موثوق؛ لا يمكن بدء التحقق.');
      }
      if (result['supported'] != true || result['started'] != true ||
          id is! String || id.isEmpty) {
        throw StateError('لم يبدأ التقاط الشاشة: ${result['reason'] ?? 'UNKNOWN'}');
      }
      _captureSession = id;
      guard.beginCaptureSession(id);
      captureRunning = true;
      // Re-evaluate freshness even if no native frame arrives. The timer never
      // generates evidence and does not operate on screen pixels.
      _verificationTimer?.cancel();
      _verificationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
    } catch (e) {
      _captureFailed(e.toString());
      await captureService.stop();
      await _captureSubscription?.cancel();
      _captureSubscription = null;
      rethrow;
    } finally {
      _captureStarting = false;
      if (!_disposed) notifyListeners();
    }
  }
  void _handleCaptureEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    final type = event['type'];
    if (_captureStarting && !captureRunning) {
      // Initial idle status is expected when subscribing. A terminal event,
      // however, invalidates the pending handshake even if start() has not yet
      // returned: a stale success response must not resurrect a dead service.
      if (type == 'stopped' || type == 'error') {
        _rejectCaptureEvent('فشل بدء الالتقاط: ${event['reason'] ?? 'UNKNOWN'}');
      } else if (!{'status', 'started', 'frame'}.contains(type)) {
        _rejectCaptureEvent('حدث التقاط غير صالح أثناء طلب الموافقة.');
      }
      return;
    }
    if (!captureRunning) return;
    if (event['sessionId'] != _captureSession) {
      _rejectCaptureEvent('حدث التقاط خارج الجلسة الحالية؛ أُغلق التحقق.');
      return;
    }
    switch (type) {
      case 'frame':
        guard.observeFrame(ScreenFrameEvidence.fromJson(event));
        notifyListeners();
      case 'stopped':
      case 'error':
        _rejectCaptureEvent('توقف التقاط الشاشة: ${event['reason'] ?? 'UNKNOWN'}');
      case 'status':
        if (event['started'] != true) _rejectCaptureEvent('التقاط الشاشة غير نشط.');
      case 'started':
        // Lifecycle messages never confer mode authorization.
        break;
      default:
        _rejectCaptureEvent('حدث التقاط غير معروف؛ لا يمكن الوثوق بالتحقق.');
    }
  }
  void _rejectCaptureEvent(String reason) {
    _captureFailed(reason);
    unawaited(captureService.stop().catchError((Object _) {}));
  }
  void _captureFailed(String reason) {
    _captureStreamHealthy = false;
    captureRunning = false;
    _captureSession = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
    guard.stopCaptureSession();
    error = reason;
    overlayVisible = false;
    unawaited(overlayService.hide().catchError((Object _) {}));
    if (!_disposed) notifyListeners();
  }
  Future<void> stopAutomaticRecognition() async {
    // Lock synchronously, before waiting on a platform response.
    _captureFailed('التقاط الشاشة متوقف؛ الوضع غير معروف ومقفول.');
    await captureService.stop();
    await _captureSubscription?.cancel();
    _captureSubscription = null;
  }
  Future<void> _run(Future<StateMap> Function(CalibrationWorkflow) action) async {
    if (busy) {
      throw StateError('انتظر اكتمال الحفظ الجاري.');
    }
    if (_workflow == null || device?.supported != true) {
      throw StateError('الجهاز غير مدعوم أو لم يكتمل اكتشافه.');
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      _state = await action(_workflow!);
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
  Future<void> saveBaseline(Map<String,double> settings) => _run((w)=>w.saveBaseline(settings));
  Future<void> addObservation(String kind, StateMap data) => _run((w)=>w.addObservation(kind,data));
  Future<void> propose({required String key,required double proposed,required String reason,
    required String evidence,required int sampleCount,required String expected,required String risk}) =>
    _run((w)=>w.propose(key:key,proposed:proposed,reason:reason,evidence:evidence,
      sampleCount:sampleCount,expected:expected,risk:risk));
  Future<void> approveForTest(String id) => _run((w)=>w.approveForTest(id));
  Future<void> recordTest(String id,Map<String,double> metrics,{required bool manualApplied}) =>
    _run((w)=>w.recordTest(id,metrics,manualApplied:manualApplied));
  Future<void> approveFinal(String id) => _run((w)=>w.approveFinal(id));
  Future<void> reject(String id) => _run((w)=>w.reject(id));
  Future<void> defer(String id) => _run((w)=>w.defer(id));
  Future<void> restore() => _run((w)=>w.restore());
  @override
  void dispose() {
    _disposed = true;
    disposeOverlayBridge?.call();
    disposeOverlayBridge = null;
    unawaited(overlayService.hide().catchError((Object _) {}));
    _verificationTimer?.cancel();
    unawaited(_captureSubscription?.cancel());
    unawaited(captureService.stop().catchError((Object _) {}));
    guard.stopCaptureSession();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
