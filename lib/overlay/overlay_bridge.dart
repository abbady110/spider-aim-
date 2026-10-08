import 'dart:async';
import 'dart:convert';

import '../aim/aim_calibration_engine.dart';
import '../core/coach_controller.dart';
import '../game_mode_guard/game_mode_guard.dart';
import '../testing/comparison_policy.dart';
import '../ui/forms.dart';

/// Presentation adapter for the native floating panel. The same controller and
/// SQLite writer used by the Flutter app execute every operation. Native form
/// values cannot provide a safe mode, proposal evidence, an approval, or a
/// replacement settings snapshot without the corresponding reviewed form.
class OverlayBridge {
  OverlayBridge(this.controller, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final CoachController controller;
  final DateTime Function() _now;
  static const formTtl = Duration(minutes: 5);
  final Map<String, _IssuedForm> _forms = {};
  int _formSequence = 0;
  bool _attached = false;
  bool _disposed = false;
  bool _requestBusy = false;
  bool _publishing = false;
  Map<String, Object?>? _pendingState;

  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    controller.overlayService.setRequestHandler(handleRequest);
    controller.addListener(_publish);
    _publish();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_attached) controller.removeListener(_publish);
    controller.overlayService.setRequestHandler(null);
    _forms.clear();
    _pendingState = null;
  }

  /// Used by the native method handler and tests; authorization always comes
  /// from the actual capture guard, never from the request's payload.
  Future<Map<String, Object?>> handleRequest(Map<String, Object?> request) async {
    if (request['action'] == 'hideOverlay' && !_disposed) {
      final payload = request['payload'];
      if (payload is! Map || payload.isNotEmpty) {
        return {'ok': false, 'error': 'طلب إغلاق غير صالح.', 'state': _viewModel()};
      }
      try {
        _forms.clear();
        await controller.hideOverlay();
        return {'ok': true, 'message': 'أُخفيت اللوحة.', 'state': _viewModel()};
      } catch (error) {
        return {'ok': false, 'error': '$error', 'state': _viewModel()};
      }
    }
    if (_disposed) {
      return {'ok': false, 'error': 'اللوحة متوقفة أو توجد عملية جارية.'};
    }
    if (_requestBusy) {
      return {'ok': false, 'error': 'توجد عملية جارية.', 'state': _viewModel()};
    }
    _requestBusy = true;
    Map<String, Object?> result;
    try {
      _requireActive();
      final action = request['action'];
      final rawPayload = request['payload'];
      if (action is! String || rawPayload is! Map ||
          rawPayload.keys.any((key) => key is! String)) {
        throw ArgumentError('طلب لوحة غير صالح.');
      }
      final payload = Map<String, Object?>.from(rawPayload);
      if (action == 'submit') {
        result = await _submit(payload);
      } else {
        if (payload.isNotEmpty) {
          throw ArgumentError('لا تقبل الشاشة أي تصريح أو تجاوز أو سياق من الطلب.');
        }
        result = switch (action) {
          'baseline' => _baseline(),
          'aim' => _aim(),
          'propose' => _proposalContext(),
          'proposals' => _proposalSelection(),
          'testing' => _testing(),
          'restore' => _restore(),
          'history' => _history(),
          _ => throw ArgumentError('إجراء غير مسموح: $action'),
        };
      }
    } catch (error) {
      result = {'ok': false, 'error': '$error'};
    } finally {
      _requestBusy = false;
      _publish();
    }
    // Native must see the current authority/busy state before displaying a
    // follow-up form, even when a previous asynchronous update was in flight.
    return {...result, 'state': _viewModel()};
  }

  void _requireActive() {
    if (_disposed || controller.device?.supported != true ||
        !controller.captureRunning || controller.recognition.sessionId == null) {
      throw StateError('يلزم جهاز مدعوم وجلسة التقاط شاشة نشطة ومصرح بها.');
    }
    controller.guard.requireAllowed('إجراء اللوحة العائمة');
    if (controller.busy) throw StateError('انتظر اكتمال الحفظ الجاري.');
  }

  Map<String, dynamic> get _state => controller.state;
  Map<String, dynamic> get _approved => _map(_state['approved']);

  Map<String, Object?> _issue(String kind, String title, String notice,
      List<_Field> fields, {String submitLabel = 'متابعة',
      Map<String, Object?> data = const {}}) {
    _requireActive();
    final state = _state;
    final approved = _map(state['approved']);
    final id = 'overlay-${_now().microsecondsSinceEpoch}-${_formSequence++}';
    final form = _IssuedForm(
      id: id, kind: kind, createdAt: _now(),
      sessionId: controller.recognition.sessionId!,
      deviceId: controller.device!.deviceId,
      approvedVersion: approved['number'],
      approvedSettings: jsonEncode(approved['settings']),
      testingId: state['testingId'],
      proposalSignature: data['proposalId'] is String
          ? jsonEncode(_proposal(data['proposalId'] as String)) : null,
      fields: fields, data: data,
    );
    // Only a few simultaneous native forms are useful; discard older tokens.
    if (_forms.length >= 8) _forms.remove(_forms.keys.first);
    _forms[id] = form;
    return {'ok': true, 'form': {
      'id': id, 'title': title, 'notice': notice,
      'submitLabel': submitLabel,
      'fields': fields.map((field) => field.toJson()).toList(),
    }};
  }

  List<_Field> _contextFields() => [
    _Field.choice('weapon', 'السلاح الفعلي', weaponChoices),
    _Field.choice('scope', 'السكوب الفعلي', scopeChoices),
    _Field.text('attachments', 'الملحقات الفعلية؛ أدخل None عند عدم وجودها'),
    _Field.number('distance', 'مسافة الاختبار بالمتر', min: 1, max: 2000,
      requiredValue: true),
  ];

  Map<String, Object?> _baseline() => _issue('baseline', 'توثيق الإعدادات الحالية',
    'انسخ إعداداتك الفعلية من PUBG لهذا السلاح والسكوب والملحقات والمسافة. '
    'لا توجد قيم افتراضية للحساسية، وهذا لا يغير إعدادات اللعبة. '
    'الإعداد المسجّل مسبقًا لا يمكن استبداله؛ تغييره يحتاج اقتراحًا وBackup واختبارًا.',
    [
      ..._contextFields(),
      for (final entry in settingLabels.entries)
        _Field.number(entry.key, entry.value, max: 400),
      _Field.checkbox('confirmCurrent',
        'أؤكد أن هذه إعداداتي الحالية الفعلية لهذا الجهاز.', requiredValue: true),
    ], submitLabel: 'حفظ المرجع الحالي');

  List<_Field> _metricFields({bool requiredValue = false}) => [
    for (final entry in metricLabels.entries)
      _Field.number(entry.key, entry.value,
        max: entry.key == 'acquisitionMs' ? 60000
            : entry.key == 'batteryDrain' ? 1000
            : entry.key == 'thermalImpact' ? 6 : 100,
        integer: entry.key == 'thermalImpact', requiredValue: requiredValue),
  ];

  Map<String, Object?> _aim() => _issue('aim', 'تسجيل عينة تصويب فعلية',
    'سجل محاولة مستقلة واحدة لنفس السياق. اترك القياس غير المتاح فارغًا. '
    'خمس عينات أو أكثر ومؤشرات الشبكة والإطارات والحرارة الموثوقة مطلوبة '
    'قبل اقتراح ADS؛ القياسات المجهولة لا تتحول إلى أرقام.',
    [
      ..._contextFields(), ..._metricFields(),
      for (final entry in aimDetailLabels.entries)
        _Field.number(entry.key, entry.value,
          integer: entry.key == 'hits' || entry.key == 'shots',
          max: entry.key.endsWith('Ms') ||
              {'hits', 'shots', 'verticalRecoil', 'horizontalDrift'}.contains(entry.key)
              ? 60000 : 100),
      _Field.checkbox('networkMetricsReliable', 'قيم الشبكة مقاسة من مصدر موثوق لنفس الاختبار.'),
      _Field.checkbox('frameMetricsReliable', 'ثبات FPS مقاس للعبة فعلًا؛ ليس معدل تحديث الشاشة.'),
      _Field.checkbox('actualTest', 'أجريت هذه المحاولة فعلًا وهذه نتيجتها.', requiredValue: true),
    ], submitLabel: 'حفظ العينة');

  Map<String, Object?> _proposalContext() {
    final settings = _map(_approved['settings']);
    final contexts = settings.keys.where((key) => key.endsWith('::ads'))
        .map((key) => key.substring(0, key.length - 5)).toList();
    if (contexts.isEmpty) throw StateError('وثّق ADS الحالي ثم سجل خمس عينات لنفس السياق.');
    return _issue('proposal_context', 'تحليل الدليل واقتراح ADS',
      'يستخدم المحرك عينات الإصدار المعتمد لنفس السلاح والسكوب والملحقات والمسافة. '
      'قد يرفض الاقتراح إذا كانت البيانات ناقصة أو تشير إلى شبكة أو FPS أو حرارة.',
      [_Field.choice('context', 'السياق المسجّل', contexts)]);
  }

  Map<String, Object?> _recommendation(String context) {
    final samples = _samples(context);
    final current = (_map(_approved['settings'])['$context::ads'] as num?)?.toDouble();
    if (current == null) throw StateError('قيمة ADS الحالية غير مسجلة.');
    final recommendation = AimCalibrationEngine(controller.guard)
        .suggestAds(samples, currentAds: current);
    if (recommendation == null) {
      throw StateError('لا يوجد اقتراح مدعوم: يلزم خمس عينات ونمط متكرر '
          'وقراءات موثوقة للشبكة والإطارات والحرارة. لا تُعتبر المشكلة حساسية تلقائيًا.');
    }
    return _issue('recommendation', 'مراجعة اقتراح المحرك',
      '$context\n${recommendation.problem}\n${recommendation.reason}\n'
      'الدليل: ${recommendation.evidence}\n'
      'الحالي: ${recommendation.currentAds} → المقترح: ${recommendation.proposedAds}\n'
      'الفرق: ${recommendation.delta}\n'
      'الأثر المتوقع: ${recommendation.expectedEffect}\n'
      'المقايضة: ${recommendation.tradeoff}\n'
      'الحفظ ينشئ PROPOSED فقط. موافقتك على التجربة تحفظ Backup قبل TESTING؛ '
      'تطبق الإعداد يدويًا داخل PUBG، ثم تختبر قبل موافقة نهائية منفصلة.',
      [_Field.checkbox('confirmProposal', 'أوافق على حفظ هذا الاقتراح للمراجعة فقط.',
        requiredValue: true)], submitLabel: 'حفظ الاقتراح فقط',
      data: {'context': context, 'recommendation': recommendation,
        'sampleIds': samples.map((sample) => sample.id).toList()});
  }

  Map<String, dynamic> _proposal(String id) => _rows(_state['proposals'])
      .firstWhere((proposal) => proposal['id'] == id,
        orElse: () => throw StateError('الاقتراح غير موجود.'));

  Map<String, Object?> _proposalSelection() {
    final proposals = _rows(_state['proposals']).where((proposal) =>
      {'PROPOSED', 'DEFERRED', 'TESTING', 'PASSED', 'FAILED'}.contains(proposal['status'])).toList();
    if (proposals.isEmpty) throw StateError('لا توجد اقتراحات قابلة للمراجعة.');
    return _issue('proposal_selection', 'التعديلات المقترحة',
      'اختر اقتراحًا للاطلاع على سببه ودليله والتغيير والمخاطر قبل أي قرار.',
      [_Field.choice('proposalId', 'الاقتراح',
        proposals.map((proposal) => proposal['id'] as String).toList(),
        labels: {for (final proposal in proposals)
          proposal['id'] as String: '${proposal['key']} • ${proposal['status']}'})]);
  }

  String _proposalNotice(Map<String, dynamic> proposal) {
    final test = _map(proposal['test']);
    final lines = <String>[
      '${proposal['key']} • ${proposal['status']}',
      'الحالي: ${proposal['current']} → المقترح: ${proposal['proposed']}',
      'الفرق: ${proposal['delta']}',
      'السبب: ${proposal['reason']}', 'الدليل: ${proposal['evidence']}',
      'عدد العينات: ${proposal['sampleCount']}',
      'الأثر المتوقع: ${proposal['expected']}', 'المقايضة: ${proposal['risk']}',
      if (proposal['backupId'] != null) 'Backup كامل للإعدادات المسجلة محفوظ.',
      if (test.isNotEmpty) 'المقارنة: ${test['passed'] == true ? 'PASSED' : 'FAILED'}',
      if (test['reasons'] is List) ...(test['reasons'] as List).map((reason) => '$reason'),
      if (test.isNotEmpty)
        for (final key in ComparisonPolicy.keys)
          '${metricLabels[key] ?? key}: ${_map(proposal['baseline'])[key]} → '
              '${_map(test['metrics'])[key]}',
      'SPIDER AIM لا يغير PUBG. طبّق القيمة بنفسك من إعدادات اللعبة الرسمية، '
          'واختبر في Warehouse أو Arena أو Unranked قبل الاعتماد النهائي.',
    ];
    return lines.join('\n');
  }

  Map<String, Object?> _proposalDecision(String id) {
    final proposal = _proposal(id);
    final actions = switch (proposal['status']) {
      'PROPOSED' => ['approveForTest', 'reject', 'defer'],
      'DEFERRED' => ['approveForTest', 'reject'],
      'TESTING' => ['test', 'reject', 'restore'],
      'PASSED' => ['retest', 'approveFinal', 'reject', 'restore'],
      'FAILED' => ['retest', 'reject', 'restore'],
      _ => throw StateError('هذا الاقتراح له قرار نهائي بالفعل.'),
    };
    return _issue('proposal_decision', 'قرارك بشأن الاقتراح', _proposalNotice(proposal),
      [
        _Field.choice('decision', 'القرار المطلوب', actions, labels: _decisionLabels),
        _Field.checkbox('confirmDecision', 'أؤكد اختياري بعد قراءة السبب والدليل والمخاطر.',
          requiredValue: true),
      ], submitLabel: 'تنفيذ قراري فقط', data: {'proposalId': id});
  }

  Map<String, Object?> _testing() {
    final id = _state['testingId'];
    if (id is! String) throw StateError('لا توجد نسخة TESTING نشطة.');
    return _testForm(id);
  }

  Map<String, Object?> _testForm(String id) {
    if (!{GameMode.warehouseSafe, GameMode.arenaSafe, GameMode.safeUnranked}
        .contains(controller.guard.mode)) {
      throw StateError('المقارنة تحتاج Warehouse أو Arena أو Unranked؛ التدريب وحده لا يكفي.');
    }
    final proposal = _proposal(id);
    if (_state['testingId'] != id ||
        !{'TESTING', 'PASSED', 'FAILED'}.contains(proposal['status'])) {
      throw StateError('الاقتراح ليس النسخة التجريبية النشطة.');
    }
    return _issue('test', 'نتائج النسخة التجريبية', _proposalNotice(proposal),
      [
        ..._metricFields(requiredValue: true),
        _Field.number('sampleCount', 'عدد المحاولات المستقلة الفعلية',
          min: 5, max: 10000, integer: true, requiredValue: true),
        _Field.checkbox('actualTest', 'أجريت اختبار المقارنة فعليًا بنفس السياق.',
          requiredValue: true),
        _Field.checkbox('manualApplied', 'طبّقت القيمة التجريبية بنفسي داخل إعدادات PUBG الرسمية.',
          requiredValue: true),
      ], submitLabel: 'حفظ النتائج ومقارنة النسختين', data: {'proposalId': id});
  }

  Map<String, Object?> _restore() {
    final state = _state;
    final approved = _map(state['approved']);
    final active = state['testingId'];
    final backupId = active is String ? _proposal(active)['backupId'] : approved['backupId'];
    if (backupId == null) throw StateError('لا توجد نسخة سابقة قابلة للاسترجاع.');
    final backup = _rows(state['backups']).firstWhere((row) => row['id'] == backupId,
      orElse: () => throw StateError('النسخة الاحتياطية غير موجودة.'));
    final previous = _map(_map(backup['snapshot'])['settings']);
    return _issue('restore', 'استرجاع النسخة السابقة',
      'يشمل Backup كامل الإعدادات التي وثّقتها في SPIDER AIM فقط. '
      'لا يمكن قراءة إعدادات PUBG غير المسجّلة. سنحفظ النسخة الحالية قبل الاسترجاع. '
      'بعد الاسترجاع المحلي أعد هذه القيم يدويًا داخل PUBG:\n'
      '${previous.entries.map((entry) => '${settingTitle(entry.key)}: ${entry.value}').join('\n')}',
      [_Field.checkbox('confirmRestore', 'أوافق على الاسترجاع المحلي وإعادة القيم داخل اللعبة يدويًا.',
        requiredValue: true)], submitLabel: 'استرجاع محلي فقط',
      data: {if (active is String) 'proposalId': active, 'backupId': backupId});
  }

  Map<String, Object?> _history() {
    final state = _state;
    final versions = _rows(state['versions']);
    final settings = _map(_map(state['approved'])['settings']);
    return _issue('history', 'الإصدارات والإعدادات المسجلة',
      'قراءة فقط؛ لا تغيير لإعدادات اللعبة أو لقفل الأمان.\n'
      '${versions.reversed.take(12).map((row) => 'V${row['number']} • '
        '${row['status']} • ${row['reason']}').join('\n')}\n'
      'الإعدادات المعتمدة:\n'
      '${settings.entries.map((entry) => '${settingTitle(entry.key)}: ${entry.value}').join('\n')}',
      const [], submitLabel: 'إغلاق');
  }

  Future<Map<String, Object?>> _submit(Map<String, Object?> payload) async {
    if (payload.keys.any((key) => key != 'formId' && key != 'values')) {
      throw ArgumentError('طلب إرسال غير صالح.');
    }
    final id = payload['formId'];
    final rawValues = payload['values'];
    if (id is! String || rawValues is! Map ||
        rawValues.keys.any((key) => key is! String)) {
      throw ArgumentError('معرف النموذج والقيم مطلوبان.');
    }
    final form = _forms[id];
    if (form == null) throw StateError('النموذج غير معروف أو انتهت صلاحيته.');
    _validateBinding(form);
    final values = _validateFields(form.fields, Map<String, Object?>.from(rawValues));
    switch (form.kind) {
      case 'baseline':
        final context = _context(values);
        final settings = <String, double>{
          for (final key in settingLabels.keys)
            if (values[key] is double) '$context::$key': values[key] as double,
        };
        if (settings.isEmpty) throw ArgumentError('أدخل إعدادًا حاليًا واحدًا على الأقل.');
        _forms.remove(id);
        await controller.saveBaseline(settings);
        return _success('حُفظت نسخة من إعداداتك الحالية محليًا؛ لم يتغير PUBG.');
      case 'aim':
        final metrics = _metrics(values);
        if (metrics.isEmpty) throw ArgumentError('أدخل قياسًا موثوقًا واحدًا على الأقل.');
        if ((metrics['overshootRate'] ?? 0) + (metrics['undershootRate'] ?? 0) > 100) {
          throw ArgumentError('مجموع Overshoot وUndershoot لا يمكن أن يتجاوز 100٪.');
        }
        final details = <String, dynamic>{
          'networkMetricsReliable': values['networkMetricsReliable'] == true,
          'frameMetricsReliable': values['frameMetricsReliable'] == true,
          for (final key in aimDetailLabels.keys)
            if (values[key] is double) key:
              key == 'hits' || key == 'shots' ? (values[key] as double).toInt() : values[key],
        };
        final hits = details['hits'] as int?;
        final shots = details['shots'] as int?;
        if ((hits == null) != (shots == null) ||
            (shots != null && (shots <= 0 || hits! > shots))) {
          throw ArgumentError('أدخل الإصابات والطلقات معًا؛ الإصابات لا تتجاوز عدد الطلقات.');
        }
        if (hits != null && shots != null && metrics['hitRate'] != null &&
            (metrics['hitRate']! - hits / shots * 100).abs() > 1) {
          throw ArgumentError('نسبة الإصابات لا تطابق عدد الإصابات والطلقات.');
        }
        _forms.remove(id);
        await controller.addObservation('aim', {
          'context': _context(values), 'metrics': metrics, 'aimDetails': details,
          'source': 'MANUAL_OVERLAY_AUTOMATIC_MODE',
        });
        return _success('حُفظت محاولة واحدة فعلية. الاقتراح يحتاج نمطًا متكررًا وبيانات كافية.');
      case 'proposal_context':
        return _replaceForm(id, _recommendation(values['context'] as String));
      case 'recommendation':
        final context = form.data['context'] as String;
        final samples = _samples(context);
        if (jsonEncode(samples.map((sample) => sample.id).toList()) !=
            jsonEncode(form.data['sampleIds'])) {
          throw StateError('تغيرت العينات؛ أعد تحليل الدليل قبل حفظ الاقتراح.');
        }
        final recommendation = form.data['recommendation'] as AimRecommendation;
        _forms.remove(id);
        await controller.propose(key: '$context::ads',
          proposed: recommendation.proposedAds, reason: recommendation.reason,
          evidence: recommendation.evidence, sampleCount: recommendation.sampleCount,
          expected: recommendation.expectedEffect, risk: recommendation.tradeoff);
        return _success('حُفظ PROPOSED فقط. راجع الاقتراح قبل الموافقة على التجربة.');
      case 'proposal_selection':
        return _replaceForm(id, _proposalDecision(values['proposalId'] as String));
      case 'proposal_decision':
        final proposalId = form.data['proposalId'] as String;
        switch (values['decision']) {
          case 'approveForTest':
            _forms.remove(id);
            await controller.approveForTest(proposalId);
            return _success('حُفظ Backup كامل للإعدادات المسجلة وأُنشئت TESTING فقط. '
              'طبّق القيمة يدويًا ثم اختبر قبل الاعتماد النهائي.');
          case 'reject':
            _forms.remove(id);
            await controller.reject(proposalId);
            return _success('رُفض الاقتراح. أعد القيمة المعتمدة يدويًا داخل PUBG إذا جرّبت التعديل.');
          case 'defer':
            _forms.remove(id);
            await controller.defer(proposalId);
            return _success('أُجّل الاقتراح دون تغيير الإعدادات.');
          case 'test':
          case 'retest':
            return _replaceForm(id, _testForm(proposalId));
          case 'approveFinal':
            _forms.remove(id);
            await controller.approveFinal(proposalId);
            return _success('اعتمدت النسخة محليًا بقرارك بعد نجاح المقارنة؛ لا تغيير آلي في PUBG.');
          case 'restore':
            return _replaceForm(id, _restore());
        }
        throw StateError('قرار غير صالح.');
      case 'test':
        final metrics = _metrics(values)..['sampleCount'] = values['sampleCount'] as double;
        _forms.remove(id);
        await controller.recordTest(form.data['proposalId'] as String, metrics,
          manualApplied: values['manualApplied'] == true);
        // The capture may change immediately after a valid commit. Do not issue
        // a new approval form while blocked; the saved result remains durable.
        if (controller.captureRunning && controller.guard.allowed && !controller.busy) {
          return _proposalDecision(form.data['proposalId'] as String);
        }
        return _success('حُفظت المقارنة. قفل الأمان الحالي يمنع القرار حتى يتجدد التحقق.');
      case 'restore':
        _forms.remove(id);
        await controller.restore();
        return _success('استُرجعت النسخة المحلية. اعرض السجل وأعد قيم PUBG بنفسك يدويًا.');
      case 'history':
        _forms.remove(id);
        return _success('عرض فقط؛ لم تتغير أي إعدادات.');
      default:
        throw StateError('نوع نموذج غير صالح.');
    }
  }

  Map<String, Object?> _replaceForm(String previousId, Map<String, Object?> next) {
    _forms.remove(previousId);
    return next;
  }

  void _validateBinding(_IssuedForm form) {
    _requireActive();
    final age = _now().difference(form.createdAt);
    final state = _state;
    final approved = _map(state['approved']);
    if (age.isNegative || age >= formTtl ||
        form.sessionId != controller.recognition.sessionId ||
        form.deviceId != controller.device!.deviceId ||
        form.approvedVersion != approved['number'] ||
        form.approvedSettings != jsonEncode(approved['settings']) ||
        form.testingId != state['testingId']) {
      throw StateError('تغيرت الجلسة أو الجهاز أو النسخة؛ افتح نموذجًا جديدًا.');
    }
    if (form.proposalSignature != null &&
        form.proposalSignature != jsonEncode(_proposal(form.data['proposalId'] as String))) {
      throw StateError('تغيرت حالة الاقتراح؛ راجع نتائجه الحالية أولًا.');
    }
  }

  Map<String, Object?> _validateFields(List<_Field> fields, Map<String, Object?> raw) {
    final permitted = fields.map((field) => field.key).toSet();
    if (raw.keys.any((key) => !permitted.contains(key))) {
      throw ArgumentError('النموذج لا يقبل حقولًا إضافية أو تصريحًا يدويًا.');
    }
    final values = <String, Object?>{};
    for (final field in fields) {
      final value = raw[field.key];
      if (field.type == 'checkbox') {
        if (value != null && value is! bool) throw ArgumentError('${field.label}: قيمة غير صالحة.');
        if (field.requiredValue && value != true) throw ArgumentError('${field.label}: يلزم تأكيد صريح.');
        values[field.key] = value == true;
      } else if (field.type == 'number') {
        if (value == null || (value is String && value.trim().isEmpty)) {
          if (field.requiredValue) throw ArgumentError('${field.label}: القياس مطلوب.');
          continue;
        }
        final parsed = value is num ? value.toDouble()
            : value is String ? double.tryParse(value.trim()) : null;
        if (parsed == null || !parsed.isFinite || parsed < field.min || parsed > field.max ||
            (field.integer && parsed != parsed.roundToDouble())) {
          throw ArgumentError('${field.label}: أدخل قراءة صالحة بين ${field.min} و${field.max}.');
        }
        values[field.key] = parsed;
      } else {
        if (value is! String || value.trim().isEmpty || value.length > 512) {
          throw ArgumentError('${field.label}: أدخل القيمة المطلوبة.');
        }
        final text = value.trim();
        if (field.type == 'choice' && !field.options.contains(text)) {
          throw ArgumentError('${field.label}: الاختيار ليس ضمن النموذج المراجع.');
        }
        values[field.key] = text;
      }
    }
    return values;
  }

  String _context(Map<String, Object?> values) {
    final attachments = values['attachments'] as String;
    if (attachments.contains('|') || attachments.contains('::')) {
      throw ArgumentError('لا تستخدم | أو :: داخل الملحقات.');
    }
    final distance = (values['distance'] as double).toString().replaceFirst(RegExp(r'\.0$'), '');
    return '${values['weapon']}|${values['scope']}|$attachments|$distance';
  }

  Map<String, double> _metrics(Map<String, Object?> values) => {
    for (final key in ComparisonPolicy.keys)
      if (values[key] is double) key: values[key] as double,
  };

  List<AimSample> _samples(String context) {
    final approved = _approved;
    final parts = context.split('|');
    if (parts.length != 4) throw ArgumentError('سياق غير صالح.');
    final distance = double.tryParse(parts.last);
    if (distance == null || !distance.isFinite || distance <= 0) {
      throw ArgumentError('مسافة غير صالحة.');
    }
    final samples = <AimSample>[];
    for (final row in _rows(_state['observations'])) {
      final data = _map(row['data']);
      if (row['kind'] != 'aim' || data['context'] != context ||
          row['approvedVersion'] != approved['number'] || row['testingId'] != null) {
        continue;
      }
      final metrics = _map(data['metrics']);
      final details = _map(data['aimDetails']);
      double? number(Map<String, dynamic> source, String key) {
        final value = source[key];
        if (value == null) return null;
        if (value is! num || !value.isFinite) throw ArgumentError('قياس تاريخي غير صالح: $key');
        return value.toDouble();
      }
      int? count(String key) {
        final value = number(details, key);
        if (value == null) return null;
        if (value != value.roundToDouble()) throw ArgumentError('عدد تاريخي غير صحيح: $key');
        return value.toInt();
      }
      final thermal = number(metrics, 'thermalImpact');
      if (thermal != null && thermal != thermal.roundToDouble()) {
        throw ArgumentError('القراءة الحرارية ليست حالة نظام صحيحة.');
      }
      samples.add(AimSample(
        context: WeaponContext(weapon: parts[0], scope: parts[1],
          attachments: [parts[2]], distanceMeters: distance),
        id: row['id'] as String, recordedAt: DateTime.parse(row['timestamp'] as String),
        source: row['source'] as String? ?? 'MANUAL_OBSERVATION',
        aimStability: number(metrics, 'aimStability'),
        trackingStability: number(metrics, 'trackingScore'),
        shotGrouping: number(metrics, 'sprayGrouping'),
        overshootRate: number(metrics, 'overshootRate'),
        undershootRate: number(metrics, 'undershootRate'),
        acquisitionMs: number(metrics, 'acquisitionMs'),
        movementRetention: number(metrics, 'movementRetention'),
        fpsStability: number(metrics, 'fpsStability'),
        batteryDrainPerHour: number(metrics, 'batteryDrain'),
        thermalSeverity: thermal?.toInt(),
        verticalRecoil: number(details, 'verticalRecoil'),
        horizontalDrift: number(details, 'horizontalDrift'),
        firstShotStability: number(details, 'firstShotStability'),
        adsStabilizationMs: number(details, 'adsStabilizationMs'),
        fingerDragConsistency: number(details, 'fingerDragConsistency'),
        sprayConsistency: number(details, 'sprayConsistency'),
        hits: count('hits'), shots: count('shots'),
        latencyMs: number(details, 'latencyMs'), jitterMs: number(details, 'jitterMs'),
        packetLossPercent: number(details, 'packetLossPercent'),
        networkMetricsReliable: details['networkMetricsReliable'] == true,
        frameMetricsReliable: details['frameMetricsReliable'] == true,
      ));
    }
    return samples;
  }

  Map<String, Object?> _success(String message) => {'ok': true, 'message': message, 'refresh': true};

  void _publish() {
    if (!_attached || _disposed) return;
    _pendingState = _viewModel();
    if (_pendingState!['allowed'] != true) _forms.clear();
    if (!_publishing) unawaited(_flushPublish());
  }

  Map<String, Object?> _viewModel() {
    final decision = controller.recognition;
    final allowed = decision.allowed && controller.captureRunning && controller.device?.supported == true;
    final state = _state;
    final approved = _map(state['approved']);
    final proposals = _rows(state['proposals']);
    final enabled = allowed && !controller.busy && !_requestBusy;
    return {
      'mode': decision.mode.code, 'confidence': decision.confidence,
      'evidence': decision.evidence, 'lastVerifiedMs': decision.lastVerified?.millisecondsSinceEpoch,
      'sessionId': decision.sessionId, 'captureRunning': controller.captureRunning,
      'allowed': allowed, 'busy': controller.busy || _requestBusy,
      'visible': controller.overlayVisible,
      'approvedVersion': approved['number'], 'testingId': state['testingId'],
      'proposals': proposals.reversed.take(12).map((proposal) => {
        'id': proposal['id'], 'key': proposal['key'], 'status': proposal['status'],
        'current': proposal['current'], 'proposed': proposal['proposed'],
      }).toList(),
      'menu': [
        {'action': 'baseline', 'label': 'توثيق إعداداتي الحالية', 'enabled': enabled},
        {'action': 'aim', 'label': 'تسجيل محاولة تصويب', 'enabled': enabled},
        {'action': 'propose', 'label': 'تحليل العينات واقتراح ADS', 'enabled': enabled},
        {'action': 'proposals', 'label': 'الموافقة / الرفض / التأجيل', 'enabled': enabled && proposals.isNotEmpty},
        {'action': 'testing', 'label': 'اختبار النسخة ومقارنة النتائج', 'enabled': enabled && state['testingId'] != null},
        {'action': 'restore', 'label': 'استرجاع النسخة السابقة', 'enabled': enabled &&
            (state['testingId'] != null || approved['backupId'] != null)},
        {'action': 'history', 'label': 'الإصدارات والإعدادات المعتمدة', 'enabled': enabled},
      ],
    };
  }

  Future<void> _flushPublish() async {
    _publishing = true;
    try {
      while (!_disposed && _pendingState != null) {
        final state = _pendingState!;
        _pendingState = null;
        try {
          await controller.overlayService.updateState(state);
        } catch (_) {
          // A stale/unreachable panel cannot authorize a write. The native
          // side also checks foreground/freshness; hide it after bridge loss.
          _pendingState = null;
          try { await controller.hideOverlay(); } catch (_) {}
          // hideOverlay notifies listeners; discard that queued retry after
          // loss of the native bridge instead of looping on the same failure.
          _pendingState = null;
          break;
        }
      }
    } finally {
      _publishing = false;
    }
  }

  static const _decisionLabels = {
    'approveForTest': 'موافقة على التجربة + Backup؛ لا اعتماد نهائي',
    'reject': 'رفض الاقتراح', 'defer': 'تأجيل', 'test': 'تسجيل الاختبار الفعلي',
    'retest': 'إعادة اختبار', 'approveFinal': 'أوافق على الاعتماد النهائي بعد نجاح المقارنة',
    'restore': 'مراجعة استرجاع النسخة السابقة',
  };
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : [];

class _IssuedForm {
  const _IssuedForm({required this.id, required this.kind, required this.createdAt,
    required this.sessionId, required this.deviceId, required this.approvedVersion,
    required this.approvedSettings, required this.testingId, required this.proposalSignature,
    required this.fields, required this.data});
  final String id, kind, sessionId, deviceId, approvedSettings;
  final DateTime createdAt;
  final Object? approvedVersion, testingId;
  final String? proposalSignature;
  final List<_Field> fields;
  final Map<String, Object?> data;
}

class _Field {
  const _Field.number(this.key, this.label, {this.min = 0, this.max = 100,
    this.requiredValue = false, this.integer = false})
    : type = 'number', options = const [], labels = const {};
  const _Field.text(this.key, this.label)
    : type = 'text', min = 0, max = 0, requiredValue = true, integer = false,
      options = const [], labels = const {};
  const _Field.choice(this.key, this.label, this.options, {this.labels = const {}})
    : type = 'choice', min = 0, max = 0, requiredValue = true, integer = false;
  const _Field.checkbox(this.key, this.label, {this.requiredValue = false})
    : type = 'checkbox', min = 0, max = 0, integer = false,
      options = const [], labels = const {};
  final String key, label, type;
  final double min, max;
  final bool requiredValue, integer;
  final List<String> options;
  final Map<String, String> labels;
  Map<String, Object?> toJson() => {
    'key': key, 'type': type, 'label': label, 'required': requiredValue,
    'value': type == 'checkbox' ? false : null,
    if (type == 'number') 'min': min,
    if (type == 'number') 'max': max,
    if (type == 'number') 'integer': integer,
    if (type == 'choice') 'options': options.map((value) => {
      'value': value, 'label': labels[value] ?? value,
    }).toList(),
  };
}
