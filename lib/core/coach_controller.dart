import 'package:flutter/widgets.dart';
import '../device/device_service.dart';
import '../game_mode_guard/game_mode_guard.dart';
import '../storage/coach_store.dart';
import 'calibration_workflow.dart';

class CoachController extends ChangeNotifier with WidgetsBindingObserver {
  CoachController({required this.store, DeviceService? deviceService, GameModeGuard? gameModeGuard})
    : deviceService = deviceService ?? const DeviceService(), guard = gameModeGuard ?? GameModeGuard();
  final CoachStore store;
  final DeviceService deviceService;
  final GameModeGuard guard;
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
    } catch (e) {
      error = e.toString();
    } finally {
      ready = true;
      notifyListeners();
    }
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
    if (state != AppLifecycleState.resumed) {
      guard.invalidate();
      notifyListeners();
    }
  }
  Future<void> selectMode(GameMode mode) async {
    if (device?.supported != true) {
      throw StateError('يتطلب هاتفًا أو جهازًا لوحيًا فعليًا مدعومًا.');
    }
    guard.declareOfflineMode(mode);
    notifyListeners();
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
