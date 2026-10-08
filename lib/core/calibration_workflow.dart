import '../game_mode_guard/game_mode_guard.dart';
import '../profiles/settings_policy.dart';
import '../storage/coach_store.dart';
import '../testing/comparison_policy.dart';

/// Durable coaching workflow gated by automatic screen-mode verification.
/// Metrics/settings remain manually entered; this class never writes to PUBG.
class CalibrationWorkflow {
  CalibrationWorkflow({required this.store, required this.guard, required this.deviceId,
    DateTime Function()? now}) : _now = now ?? DateTime.now;
  final CoachStore store;
  final GameModeGuard guard;
  final String deviceId;
  final DateTime Function() _now;
  int _sequence = 0;
  String get _timestamp => _now().toUtc().toIso8601String();
  String _id(String type) => '$deviceId-$type-${_now().microsecondsSinceEpoch}-${_sequence++}';
  Future<StateMap> read() => store.read(deviceId);
  Future<StateMap> _change(StateMutation f) {
    guard.requireAllowed();
    return store.transaction(deviceId, (s) {
      guard.requireAllowed();
      if (s['deviceId'] != deviceId) {
        throw StateError('Device mismatch');
      }
      f(s);
    }, authorizeCommit: guard.requireAllowed);
  }
  List<dynamic> _list(StateMap s, String key) => s[key] as List<dynamic>;
  StateMap _approved(StateMap s) => s['approved'] as StateMap;
  StateMap _proposal(StateMap s, String id) =>
    _list(s, 'proposals').cast<StateMap>().firstWhere((p) => p['id'] == id,
      orElse: () => throw StateError('الاقتراح غير موجود.'));
  void _transition(StateMap p, String status) {
    p['status'] = status;
    (p['history'] as List).add({'status': status, 'timestamp': _timestamp});
  }
  StateMap _backup(StateMap s, String reason) {
    final b = <String,dynamic>{'id': _id('backup'), 'timestamp': _timestamp,
      'deviceId': deviceId, 'snapshot': cloneState(_approved(s)), 'reason': reason,
      'policy': SettingsPolicy.nonGyro};
    _list(s, 'backups').add(b);
    return b;
  }
  int _nextVersion(StateMap s) => _list(s, 'versions').fold<int>(0,
    (max, v) => (v['number'] as int) > max ? v['number'] as int : max) + 1;

  /// Imports the user's existing settings, not a generated recommendation.
  /// Existing keys can only change through the trial/approval workflow.
  Future<StateMap> saveBaseline(Map<String,double> settings) => _change((s) {
    SettingsPolicy.validate(settings);
    if (settings.isEmpty) {
      throw ArgumentError('أدخل إعداداتك الحالية أولًا.');
    }
    if (s['testingId'] != null) {
      throw StateError('أنهِ النسخة التجريبية أولًا.');
    }
    final current = Map<String,dynamic>.from(_approved(s)['settings'] as Map);
    for (final entry in settings.entries) {
      if (current.containsKey(entry.key)) {
        throw StateError('الإعداد مسجل مسبقًا؛ تغييره يحتاج اقتراحًا واختبارًا.');
      }
    }
    final backup = current.isNotEmpty ? _backup(s, 'تسجيل إعدادات موجودة لسياق جديد') : null;
    current.addAll(settings);
    final v = <String,dynamic>{'number': _nextVersion(s), 'timestamp': _timestamp,
      'deviceId': deviceId, 'profile': SettingsPolicy.playerMode,
      'settings': current, 'policy': SettingsPolicy.nonGyro,
      'reason': 'نسخة من الإعدادات الحالية أدخلها المستخدم يدويًا',
      'proposedChanges': <String,dynamic>{}, 'testResults': null,
      'status': 'APPROVED_FINAL', 'finalDecision': 'EXISTING_USER_SETTINGS'};
    if (backup != null) {
      v['backupId'] = backup['id'];
    }
    _list(s, 'versions').add(cloneState(v));
    s['approved'] = v;
  });

  Future<StateMap> addObservation(String kind, StateMap data) => _change((s) {
    if (!{'aim','movement','throwables','death','battery','hit','landing'}.contains(kind)) {
      throw ArgumentError('نوع عينة غير معروف.');
    }
    if (kind == 'aim') {
      if (data['context'] is! String || data['metrics'] is! Map) {
        throw ArgumentError('عينة تصويب غير مكتملة.');
      }
      final metrics = Map<String,dynamic>.from(data['metrics'] as Map);
      for (final entry in metrics.entries) {
        if (!ComparisonPolicy.keys.contains(entry.key) || entry.value is! num ||
            !(entry.value as num).isFinite || (entry.value as num) < 0) {
          throw ArgumentError('قياس غير صالح.');
        }
      }
    }
    _list(s, 'observations').add({'id': _id('observation'), 'kind': kind,
      'data': cloneState(data), 'timestamp': _timestamp, 'mode': guard.mode.code,
      'source': 'MANUAL_METRICS_AUTOMATIC_MODE',
      'modeConfidence': guard.recognition.confidence,
      'modeEvidence': guard.recognition.evidence,
      'modeVerifiedAt': guard.recognition.lastVerified?.toIso8601String(),
      'captureSession': guard.recognition.sessionId,
      'approvedVersion': _approved(s)['number'],
      'testingId': s['testingId']});
  });

  Future<StateMap> propose({required String key, required double proposed,
    required String reason, required String evidence, required int sampleCount,
    required String expected, required String risk}) => _change((s) {
    SettingsPolicy.validate({key: proposed});
    if ([reason,evidence,expected,risk].any((v) => v.trim().isEmpty)) {
      throw ArgumentError('أكمل السبب والدليل والأثر والمخاطر.');
    }
    if (s['testingId'] != null) {
      throw StateError('أنه الاختبار الجاري أولًا.');
    }
    final settings = _approved(s)['settings'] as Map;
    final current = (settings[key] as num?)?.toDouble();
    if (current == null) {
      throw StateError('سجل القيمة الحالية لهذا الجهاز والسلاح أولًا.');
    }
    if (current == proposed) {
      throw ArgumentError('لا يوجد تغيير مقترح.');
    }
    // Decimal values exactly at the five-percent bound can differ by a few
    // binary floating-point ULPs (for example 31 -> 29.45).
    if ((proposed-current).abs() > (current.abs()*0.05).clamp(1,20) + 1e-9) {
      throw ArgumentError('ابدأ بخطوة صغيرة: 5٪ من القيمة الحالية بحد أدنى نقطة.');
    }
    final context = key.split('::').first;
    final samples = _list(s, 'observations').cast<StateMap>().where((o) =>
      o['kind'] == 'aim' && (o['data'] as Map)['context'] == context &&
      o['approvedVersion'] == _approved(s)['number'] && o['testingId'] == null).toList();
    if (samples.length < 5 || sampleCount < 5 || sampleCount != samples.length) {
      throw StateError('يلزم خمس عينات فعلية أو أكثر للسياق والإصدار الحالي؛ عدد الدليل لا يطابق السجل.');
    }
    final baseline = <String,double>{};
    for (final metric in ComparisonPolicy.keys) {
      final values = samples.map((o) => ((o['data'] as Map)['metrics'] as Map)[metric]).toList();
      if (values.any((v) => v is! num || !v.isFinite)) {
        throw StateError('الدليل غير مكتمل: $metric. لا نخترع قياسات مفقودة.');
      }
      baseline[metric] = values.cast<num>().fold<double>(0,(sum,v)=>sum+v)/values.length;
    }
    ComparisonPolicy.validate(baseline);
    final p = <String,dynamic>{'id': _id('proposal'), 'key': key, 'context': context,
      'current': current, 'proposed': proposed, 'delta': proposed-current,
      'reason': reason, 'evidence': evidence, 'sampleCount': samples.length,
      'sampleIds': samples.map((s)=>s['id']).toList(), 'expected': expected, 'risk': risk,
      'timestamp': _timestamp, 'deviceId': deviceId, 'baseVersion': _approved(s)['number'],
      'baseline': baseline, 'status': 'PROPOSED', 'history': <dynamic>[], 'test': null};
    _transition(p, 'PROPOSED');
    _list(s, 'proposals').add(p);
    _list(s, 'notifications').add({'id': p['id'], 'title': 'اقتراح يحتاج موافقتك',
      'body': '$reason\n$evidence\n$current → $proposed\n$expected', 'timestamp': _timestamp});
  });

  Future<StateMap> approveForTest(String id) => _change((s) {
    if (s['testingId'] != null) {
      throw StateError('يوجد اختبار جارٍ.');
    }
    final p = _proposal(s,id);
    if (!{'PROPOSED','DEFERRED','FAILED'}.contains(p['status'])) {
      throw StateError('لا يمكن بدء الاختبار من هذه الحالة.');
    }
    if (p['baseVersion'] != _approved(s)['number']) {
      throw StateError('تغير الإصدار المعتمد؛ اجمع قياسات واقتراحًا جديدًا.');
    }
    _transition(p,'APPROVED_FOR_TEST');
    final backup = _backup(s,'قبل تجربة ${p['key']}');
    p['backupId'] = backup['id'];
    _transition(p,'BACKED_UP');
    final candidate = cloneState(_approved(s));
    candidate['number'] = _nextVersion(s);
    candidate['timestamp'] = _timestamp;
    candidate['status'] = 'TESTING';
    candidate['proposalId'] = id;
    candidate['backupId'] = backup['id'];
    (candidate['settings'] as Map)[p['key']] = p['proposed'];
    candidate['reason'] = p['reason'];
    candidate['proposedChanges'] = {'key': p['key'], 'from': p['current'], 'to': p['proposed']};
    candidate['testResults'] = null;
    candidate['finalDecision'] = null;
    p['candidateVersion'] = candidate['number'];
    p['test'] = null;
    _list(s,'versions').add(candidate);
    _transition(p,'TESTING');
    s['testingId'] = id;
  });

  Future<StateMap> recordTest(String id, Map<String,double> metrics,
    {required bool manualApplied}) => _change((s) {
    if (!{GameMode.warehouseSafe,GameMode.arenaSafe,GameMode.safeUnranked}.contains(guard.mode)) {
      throw StateError('اختبار المقارنة يلزم Warehouse أو Unranked.');
    }
    final p = _proposal(s,id);
    if (s['testingId'] != id || !{'TESTING','FAILED','PASSED'}.contains(p['status'])) {
      throw StateError('لا يوجد اختبار نشط لهذا الاقتراح.');
    }
    if (!manualApplied) {
      throw StateError('أكد تطبيق القيمة يدويًا وإجراء الاختبار فعليًا.');
    }
    if (!_list(s,'backups').any((b)=>b['id']==p['backupId'])) {
      throw StateError('النسخة الاحتياطية مفقودة؛ لا يمكن المتابعة.');
    }
    final result = ComparisonPolicy.compare(
      (p['baseline'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())), metrics);
    p['test'] = {'metrics': metrics, 'mode': guard.mode.code, 'timestamp': _timestamp,
      'source': 'USER_REPORTED_AGGREGATE', 'manuallyApplied': true,
      'passed': result.passed, 'reasons': result.reasons,
      'context': p['context'], 'candidateVersion': p['candidateVersion']};
    _transition(p,result.passed ? 'PASSED' : 'FAILED');
    final v = _list(s,'versions').cast<StateMap>().firstWhere((v)=>v['number']==p['candidateVersion']);
    v['status'] = p['status'];
    v['testResults'] = cloneState(p['test'] as StateMap);
  });

  Future<StateMap> approveFinal(String id) => _change((s) {
    final p = _proposal(s,id);
    if (s['testingId'] != id || p['status'] != 'PASSED' ||
        p['test'] == null || (p['test'] as Map)['passed'] != true) {
      throw StateError('يمنع الاعتماد قبل نجاح اختبار المقارنة.');
    }
    if (p['baseVersion'] != _approved(s)['number']) {
      throw StateError('تغير الإصدار الأساسي.');
    }
    if (!_list(s,'backups').any((b)=>b['id']==p['backupId'])) {
      throw StateError('النسخة الاحتياطية مفقودة.');
    }
    final v = _list(s,'versions').cast<StateMap>().firstWhere((v)=>v['number']==p['candidateVersion']);
    v['status'] = 'APPROVED_FINAL';
    v['finalDecision'] = {'decision':'APPROVED_FINAL','timestamp':_timestamp};
    s['approved'] = cloneState(v);
    _transition(p,'APPROVED_FINAL');
    s['testingId'] = null;
  });
  Future<StateMap> reject(String id) => _change((s) {
    final p = _proposal(s,id);
    if (!{'PROPOSED','DEFERRED','TESTING','PASSED','FAILED'}.contains(p['status'])) {
      throw StateError('القرار نهائي بالفعل.');
    }
    _transition(p,'REJECTED');
    if (s['testingId'] == id) {
      final v = _list(s,'versions').cast<StateMap>().firstWhere((v)=>v['number']==p['candidateVersion']);
      v['status'] = 'REJECTED';
      v['finalDecision'] = {'decision':'REJECTED','timestamp':_timestamp};
      s['testingId'] = null;
    }
  });
  Future<StateMap> defer(String id) => _change((s) {
    final p = _proposal(s,id);
    if (p['status'] != 'PROPOSED') {
      throw StateError('يمكن تأجيل اقتراح لم يبدأ فقط.');
    }
    _transition(p,'DEFERRED');
  });
  Future<StateMap> restore() => _change((s) {
    final active = s['testingId'] as String?;
    final current = _approved(s);
    final backupId = active != null ? _proposal(s,active)['backupId'] : current['backupId'];
    if (backupId == null) {
      throw StateError('لا توجد نسخة سابقة قابلة للاسترجاع.');
    }
    final b = _list(s,'backups').cast<StateMap>().firstWhere((b)=>b['id']==backupId,
      orElse: ()=>throw StateError('النسخة الاحتياطية غير موجودة.'));
    if (b['deviceId'] != deviceId) {
      throw StateError('النسخة تخص جهازًا آخر.');
    }
    // Preserve current approved state before restoring a previous one.
    final restoreBackup = _backup(s,'قبل الاسترجاع اليدوي');
    if (active != null) {
      final p = _proposal(s,active);
      _transition(p,'ROLLED_BACK');
      final v = _list(s,'versions').cast<StateMap>().firstWhere((v)=>v['number']==p['candidateVersion']);
      v['status'] = 'ROLLED_BACK';
      v['finalDecision'] = {'decision':'ROLLED_BACK','timestamp':_timestamp};
    } else if (current['proposalId'] != null) {
      _transition(_proposal(s,current['proposalId'] as String),'ROLLED_BACK');
    }
    final restored = cloneState(b['snapshot'] as StateMap);
    restored['number'] = _nextVersion(s);
    restored['restoredFrom'] = (b['snapshot'] as Map)['number'];
    restored['timestamp'] = _timestamp;
    restored['status'] = 'APPROVED_FINAL';
    restored['reason'] = 'استرجاع إعدادات سبق اعتمادها';
    restored['finalDecision'] = {'decision':'RESTORED','timestamp':_timestamp};
    restored['backupId'] = restoreBackup['id'];
    restored.remove('proposalId');
    s['approved'] = restored;
    _list(s,'versions').add(cloneState(restored));
    s['testingId'] = null;
  });
}
