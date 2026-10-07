import 'package:flutter/material.dart';

import '../aim/aim_calibration_engine.dart';
import '../core/coach_controller.dart';
import '../death_analysis/death_analysis_engine.dart';
import '../game_mode_guard/game_mode_guard.dart';
import '../hit_registration/hit_registration_diagnostics.dart';
import '../movement/movement_calibration_engine.dart';
import '../throwables/throwables_calibration_engine.dart';
import 'battery_page.dart';
import 'components.dart';
import 'forms.dart';
import 'landing_page.dart';
import 'theme.dart';

String modeLabel(GameMode mode) => switch (mode) {
  GameMode.safeUnranked => 'Unranked • تصريح يدوي',
  GameMode.training => 'Training • تصريح يدوي',
  GameMode.warehouse => 'Warehouse • تصريح يدوي',
  GameMode.rankedBlocked => 'Ranked • مقفول',
  GameMode.unknownBlocked => 'الوضع غير معروف • مقفول',
};

const _engineMetricLabels = {
  'trackingStability': 'ثبات التتبع',
  'shotGrouping': 'تشتت الرش',
  'targetLossDuringMovement': 'فقد الهدف أثناء الحركة',
  'hitAccuracy': 'الإصابات من عدد الطلقات',
  'thermalSeverity': 'شدة الحرارة',
  'batteryDrainPerHour': 'التفريغ في الساعة',
};

String _aimMetricLabel(String key) =>
    aimDetailLabels[key] ?? metricLabels[key] ?? _engineMetricLabels[key] ?? key;

class CoachPage extends StatelessWidget {
  const CoachPage({super.key, required this.index, required this.controller, required this.onNavigate});
  final int index;
  final CoachController controller;
  final ValueChanged<int> onNavigate;
  Map<String, dynamic> get state => controller.state;
  Map<String, dynamic> get approved => jsonMap(state['approved']);
  List<Map<String, dynamic>> get observations => jsonList(state['observations']);
  bool get allowed => controller.guard.allowed && !controller.busy;

  Future<void> _run(BuildContext context, Future<void> Function() action, [String? success]) async {
    try {
      await action();
      if (context.mounted && success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _column(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  Widget _gap([double height = 20]) => SizedBox(height: height);
  Widget _guardNotice() => controller.guard.allowed
      ? const NoticePanel(text: 'مراجعة محلية لنتائج جلسة صرّحت بأنها غير مصنفة. لا يوجد تحقق مباشر من PUBG؛ التحليل المباشر والتقاط الشاشة مقفولان.')
      : const NoticePanel(warning: true, icon: Icons.lock_outline, text: 'المعايرة مقفولة لأن الوضع مصنف أو غير معروف. حدّد نوع جلسة الاختبار التي تراجع نتائجها من صفحة الأمان. لا تستخدم هذا التصريح لتشغيل تحليل أثناء مباراة.');

  @override
  Widget build(BuildContext context) => switch (index) {
    0 => _dashboard(context),
    1 => _device(context),
    2 => _aim(context),
    3 => _weapons(context),
    4 => _movement(context),
    5 => _throwables(context),
    6 => _death(context),
    7 => BatteryPage(controller: controller),
    8 => _proposals(context),
    9 => _testing(context),
    10 => _history(context),
    11 => _restore(context),
    12 => LandingPage(controller: controller),
    _ => _safety(context),
  };

  Widget _dashboard(BuildContext context) {
    final pending = jsonList(state['proposals']).where((item) => ['PROPOSED', 'DEFERRED'].contains(item['status'])).length;
    final aim = observations.where((item) => item['kind'] == 'aim').toList();
    final lastMetrics = aim.isEmpty ? <String, dynamic>{} : jsonMap(jsonMap(aim.last['data'])['metrics']);
    final device = controller.device;
    final settings = jsonMap(approved['settings']);
    return _column([
      const PageHeading(title: 'كل تحسّن يبدأ بثبات.', subtitle: 'مدربك الشخصي للتصويب والتحكم • بياناتك على جهازك • القرار دائمًا لك'),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF163D39), Color(0xFF152630), Color(0xFF141E27)]),
          border: Border.all(color: const Color(0xFF31584F)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const StatusPill(text: 'NON-GYRO · TOUCH ONLY', good: true),
          _gap(20),
          Text(device?.name ?? 'جارٍ التعرف على الجهاز', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          _gap(8),
          Text(settings.isEmpty ? 'ابدأ بتوثيق إعداداتك ونتائج اختبارك الحقيقي.' : 'إعداداتك المعتمدة محفوظة. قارن النتائج قبل اتخاذ أي قرار.', style: const TextStyle(color: Color(0xFFBDCFD0), height: 1.7)),
          _gap(22),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(onPressed: () => onNavigate(controller.guard.allowed ? 2 : 13), icon: const Icon(Icons.my_location), label: Text(controller.guard.allowed ? 'بدء مراجعة المعايرة' : 'تحديد جلسة الاختبار')),
            OutlinedButton.icon(onPressed: () => onNavigate(3), icon: const Icon(Icons.tune), label: const Text('إعداداتي الحالية')),
          ]),
        ]),
      ),
      _gap(),
      ResponsiveCards(children: [
        MetricCard(label: 'آخر ثبات تصويب', value: reading(lastMetrics['aimStability']), icon: Icons.my_location, caption: 'قياس أدخله المستخدم • لا توجد درجة افتراضية'),
        MetricCard(label: 'الإصابات الفعلية', value: reading(lastMetrics['hitRate'], '%'), icon: Icons.gps_fixed, caption: 'نتائج اختبارك؛ ليست ضمانًا لتسجيل السيرفر'),
        MetricCard(label: 'البطارية', value: reading(device?.batteryPercent?.round(), '%'), icon: Icons.battery_5_bar, caption: device?.charging == null ? 'حالة الشحن غير متاحة' : device!.charging! ? 'متصل بالشاحن' : 'على البطارية'),
        MetricCard(label: 'النسخة المعتمدة', value: settings.isEmpty ? 'لم تُسجّل بعد' : 'V${approved['number']}', icon: Icons.verified_outlined, caption: '$pending اقتراح بانتظار قرارك'),
      ]),
      _gap(),
      SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('حالة التدريب', style: Theme.of(context).textTheme.titleMedium),
        _gap(10),
        const DetailRow('ملف اللاعب', 'NON-GYRO / TOUCH ONLY'),
        const DetailRow('الجيروسكوب وADS Gyro', 'معطلان دائمًا'),
        DetailRow('الجلسة', modeLabel(controller.guard.mode)),
        const DetailRow('التحليل المباشر', 'مقفول • لا تحقق موثوق من وضع اللعبة'),
        DetailRow('الحالة الحرارية', device?.thermal ?? 'UNKNOWN'),
        DetailRow('النسخة التجريبية', state['testingId'] == null ? 'لا يوجد اختبار جارٍ' : 'محفوظة • تحتاج نتائج وقرارًا نهائيًا'),
        DetailRow('آخر SPIDER MOVEMENT SCORE', _movementScore()),
      ])),
      _gap(),
      _guardNotice(),
      _gap(),
      const NoticePanel(text: 'Measure → Diagnose → Propose → Test → Compare → Approve\nأي تعديل يمر بموافقتك وBackup وتجربة غير مصنفة، ثم اعتمادك النهائي. لا يكفي أن تصبح الحساسية أسرع.'),
    ]);
  }

  Widget _device(BuildContext context) {
    final device = controller.device;
    final details = device?.details ?? <String, Object?>{};
    const labels = <String, String>{
      'manufacturer': 'الشركة المصنعة', 'model': 'الموديل', 'platform': 'النظام',
      'osVersion': 'إصدار النظام', 'formFactor': 'نوع الجهاز', 'screenWidthPx': 'عرض الشاشة (px)',
      'screenHeightPx': 'ارتفاع الشاشة (px)', 'logicalWidth': 'العرض المنطقي', 'logicalHeight': 'الارتفاع المنطقي',
      'pixelDensityScale': 'معامل كثافة البكسل', 'densityDpi': 'الكثافة (DPI)',
      'availableRefreshRatesHz': 'معدلات التحديث المتاحة (Hz)', 'reportedRefreshRateHz': 'معدل التحديث المبلغ عنه (Hz)',
      'touchSamplingRateHz': 'معدل أخذ عينات اللمس', 'totalMemoryBytes': 'الذاكرة الكلية للجهاز (bytes)',
      'availableProcessorCount': 'أنوية المعالج المتاحة', 'gyroscopeAvailable': 'وجود حساس الجيروسكوب',
    };
    return _column([
      const PageHeading(title: 'ملف الجهاز', subtitle: 'قراءات من واجهات النظام الرسمية. كل جهاز يحتفظ بإعداداته وسجله المستقل.'),
      SpiderCard(child: Column(children: [
        DetailRow('الجهاز', device?.name ?? 'UNKNOWN'),
        DetailRow('هاتف / جهاز لوحي فعلي', device?.physicalDevice == true ? 'نعم، حسب مؤشرات النظام' : 'غير مؤكد'),
        for (final entry in labels.entries) DetailRow(entry.value, reading(details[entry.key])),
        const DetailRow('استخدام الجيروسكوب', 'DISABLED • لا يُستخدم في المعايرة'),
      ])),
      _gap(),
      const NoticePanel(text: 'معدل تحديث الشاشة ليس FPS اللعبة. لا يوفّر النظام دائمًا معدل Touch Sampling الحقيقي أو أبعاد الشاشة بالسنتيمتر؛ تبقى القراءات غير المتاحة UNKNOWN. لا تنسخ حساسية هاتفك إلى الآيباد تلقائيًا.'),
      _gap(),
      Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: controller.busy ? null : () => _run(context, controller.refreshDevice, 'تم تحديث القراءات المتاحة.'), icon: const Icon(Icons.refresh), label: const Text('تحديث قراءات الجهاز'))),
    ]);
  }

  Widget _aim(BuildContext context) {
    final samples = observations.where((item) => item['kind'] == 'aim').toList();
    return _column([
      const PageHeading(title: 'معايرة التصويب', subtitle: 'نبحث عن منطقة الاستقرار: نفس السلاح والسكوب والملحقات والمسافة، وعينات متعددة.'),
      _guardNotice(),
      _gap(),
      ResponsiveCards(children: [
        MetricCard(label: 'عينات التصويب المحفوظة', value: '${samples.length}', icon: Icons.scatter_plot_outlined),
        const MetricCard(label: 'طريقة الإدخال', value: 'لمس فقط', icon: Icons.touch_app_outlined, caption: 'NON-GYRO • لا اعتماد على الحساسات'),
      ]),
      _gap(),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: allowed ? () => showCoachSheet(context, MetricsForm(controller: controller)) : null, icon: const Icon(Icons.add_chart), label: const Text('تسجيل عينة اختبار فعلية')),
        OutlinedButton.icon(onPressed: allowed ? () => showCoachSheet(context, ProposalForm(controller: controller)) : null, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('اقتراح خطوة صغيرة من الدليل')),
      ]),
      _gap(),
      const SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('بروتوكول اختبار متكرر', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 14),
        Text('١. اختر سياقًا واحدًا وسجّل إعداداته الحالية.\n٢. نفّذ 5 محاولات أو أكثر، بنفس الظروف.\n٣. سجّل الثبات والإصابات والتتبع والتشتت.\n٤. افصل مؤشرات Ping وJitter وFPS والحرارة.\n٥. اقترح تغييرًا صغيرًا، ثم اختبره وقارن.', style: TextStyle(height: 2, color: spiderMuted)),
      ])),
      _gap(),
      ..._aimReports(context, samples),
      if (samples.isEmpty) const EmptyPanel(title: 'لا توجد عينات بعد', message: 'لن تظهر حساسية موصى بها أو درجة ثبات قبل تسجيل نتائجك الفعلية.')
      else ...samples.reversed.take(10).map((sample) => Padding(padding: const EdgeInsets.only(bottom: 12), child: SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${jsonMap(sample['data'])['context']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(dateLabel(sample['timestamp']), style: const TextStyle(color: spiderMuted, fontSize: 12)),
        for (final entry in jsonMap(jsonMap(sample['data'])['metrics']).entries) DetailRow(metricLabels[entry.key] ?? entry.key, reading(entry.value)),
      ])))),
    ]);
  }

  List<Widget> _aimReports(BuildContext context, List<Map<String, dynamic>> rows) {
    if (!controller.guard.allowed || rows.isEmpty) {
      return [];
    }
    final groups = <String, List<AimSample>>{};
    for (final row in rows) {
      if (row['approvedVersion'] != approved['number'] || row['testingId'] != null) {
        continue;
      }
      final data = jsonMap(row['data']);
      final parts = '${data['context']}'.split('|');
      if (parts.length != 4) {
        continue;
      }
      final distance = double.tryParse(parts.last);
      if (distance == null || distance <= 0) {
        continue;
      }
      final metrics = jsonMap(data['metrics']);
      final details = jsonMap(data['aimDetails']);
      double? number(String key) => (metrics[key] as num?)?.toDouble();
      double? detail(String key) => (details[key] as num?)?.toDouble();
      int? count(String key) {
        final value = details[key];
        if (value == null) {
          return null;
        }
        if (value is! num || !value.isFinite || value != value.roundToDouble()) {
          throw ArgumentError('Shot counts must be whole measured numbers.');
        }
        return value.toInt();
      }
      final thermal = number('thermalImpact');
      try {
        final sample = AimSample(
          context: WeaponContext(weapon: parts[0], scope: parts[1], attachments: [parts[2]], distanceMeters: distance),
          id: '${row['id']}', recordedAt: DateTime.parse('${row['timestamp']}'),
          aimStability: number('aimStability'), trackingStability: number('trackingScore'),
          shotGrouping: number('sprayGrouping'), overshootRate: number('overshootRate'), undershootRate: number('undershootRate'),
          acquisitionMs: number('acquisitionMs'), movementRetention: number('movementRetention'),
          fpsStability: number('fpsStability'), batteryDrainPerHour: number('batteryDrain'),
          thermalSeverity: thermal != null && thermal == thermal.roundToDouble() ? thermal.toInt() : null,
          verticalRecoil: detail('verticalRecoil'), horizontalDrift: detail('horizontalDrift'),
          firstShotStability: detail('firstShotStability'), adsStabilizationMs: detail('adsStabilizationMs'),
          fingerDragConsistency: detail('fingerDragConsistency'), sprayConsistency: detail('sprayConsistency'),
          hits: count('hits'), shots: count('shots'),
          latencyMs: detail('latencyMs'), jitterMs: detail('jitterMs'), packetLossPercent: detail('packetLossPercent'),
          networkMetricsReliable: details['networkMetricsReliable'] == true,
          frameMetricsReliable: details['frameMetricsReliable'] == true,
        );
        groups.putIfAbsent('${data['context']}', () => []).add(sample);
      } on ArgumentError {
        // A malformed historical observation cannot become calibration evidence.
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    final widgets = <Widget>[];
    final engine = AimCalibrationEngine(controller.guard);
    for (final group in groups.entries) {
      final report = engine.analyze(group.value);
      final currentAds = (jsonMap(approved['settings'])['${group.key}::ads'] as num?)?.toDouble();
      final recommendation = currentAds == null || currentAds < 1
          ? null
          : engine.suggestAds(group.value, currentAds: currentAds);
      widgets.add(SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('تحليل محرك التصويب من العينات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        _gap(10),
        Text(group.key, textDirection: TextDirection.ltr, style: const TextStyle(color: spiderTeal)),
        DetailRow('عينات الإصدار الحالي', '${report.sampleCount}'),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('القياسات التفصيلية وحجم الدليل'), children: report.metrics.entries.map((entry) => DetailRow(
          '${_aimMetricLabel(entry.key)} • ${report.evidenceCounts[entry.key] ?? 0} عينة',
          reading(entry.value?.toStringAsFixed(2)),
        )).toList()),
        if (recommendation == null) const Text('لا يوجد اقتراح ADS آلي مدعوم بما يكفي الآن. يلزم نمط متكرر وقراءات موثوقة للشبكة والإطارات والحرارة لاستبعاد الأسباب الأخرى.', style: TextStyle(color: spiderMuted, height: 1.8))
        else ...[
          NoticePanel(text: '${recommendation.reason}\n${recommendation.evidence}\n${recommendation.currentAds} → ${recommendation.proposedAds}\n${recommendation.expectedEffect}'),
          _gap(14),
          OutlinedButton(onPressed: allowed ? () => showCoachSheet(context, ProposalForm(controller: controller, initial: {'key': '${group.key}::ads', 'proposed': recommendation.proposedAds, 'reason': recommendation.reason, 'evidence': recommendation.evidence, 'expected': recommendation.expectedEffect, 'risk': recommendation.tradeoff})) : null, child: const Text('مراجعة الاقتراح قبل حفظه')),
        ],
      ])));
      widgets.add(_gap());
    }
    return widgets;
  }

  Widget _weapons(BuildContext context) {
    final settings = jsonMap(approved['settings']);
    final groups = <String, Map<String, dynamic>>{};
    for (final entry in settings.entries) { groups.putIfAbsent(entry.key.split('::').first, () => {})[entry.key.split('::').last] = entry.value; }
    return _column([
      const PageHeading(title: 'ملفات الأسلحة والإعدادات', subtitle: 'Weapon + Scope + Attachment + Distance. القيم هنا من إدخالك، وليست حساسية افتراضية للجميع.'),
      Wrap(spacing: 8, runSpacing: 8, children: weaponChoices.map((weapon) => Chip(label: Text(weapon), avatar: const Icon(Icons.adjust, size: 16))).toList()),
      _gap(),
      FilledButton.icon(onPressed: allowed ? () => showCoachSheet(context, BaselineForm(controller: controller)) : null, icon: const Icon(Icons.add), label: const Text('توثيق إعدادات سياق جديد')),
      _gap(),
      if (!allowed) ...[_guardNotice(), _gap()],
      if (groups.isEmpty) const EmptyPanel(title: 'ملفك يبدأ من إعداداتك', message: 'سجّل القيم الحالية من PUBG أولًا. لا تُقرأ إعدادات اللعبة تلقائيًا ولا تُعدّل ملفاتها.')
      else ...groups.entries.map((group) => Padding(padding: const EdgeInsets.only(bottom: 14), child: SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(group.key, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold, color: spiderTeal)),
        _gap(10),
        for (final entry in group.value.entries) DetailRow(settingLabels[entry.key] ?? entry.key, reading(entry.value)),
      ])))),
      _gap(),
      const NoticePanel(text: 'تغيير قيمة سبق حفظها يحتاج اقتراحًا + موافقة + Backup + اختبار + اعتماد نهائي. التطبيق يعرض Current → Proposed، وتطبّقها أنت يدويًا في إعدادات PUBG الرسمية.'),
    ]);
  }

  List<MovementTrial> _movementTrials() {
    final trials = <MovementTrial>[];
    for (final item in observations.where((item) => item['kind'] == 'movement')) {
      final data = jsonMap(item['data']);
      final actions = MovementAction.values.where((value) => value.name == data['action']);
      if (actions.isEmpty || data['successful'] is! bool ||
          data['aimRetained'] is! bool || data['accidentalSprint'] is! bool) {
        continue;
      }
      try {
        trials.add(MovementTrial(
          id: '${item['id']}', action: actions.single,
          successful: data['successful'] as bool,
          aimRetained: data['aimRetained'] as bool,
          accidentalSprint: data['accidentalSprint'] as bool,
          turnErrorDegrees: (data['turnErrorDegrees'] as num?)?.toDouble(),
          responseMs: (data['responseMs'] as num?)?.toDouble(),
        ));
      } on ArgumentError {
        continue;
      } on TypeError {
        continue;
      }
    }
    return trials;
  }

  String _movementScore() {
    if (!controller.guard.allowed || _movementTrials().isEmpty) {
      return 'غير متاح';
    }
    return reading(MovementCalibrationEngine(controller.guard).analyze(_movementTrials()).spiderMovementScore?.toStringAsFixed(1));
  }

  Widget _movement(BuildContext context) {
    final trials = _movementTrials();
    final report = controller.guard.allowed && trials.isNotEmpty ? MovementCalibrationEngine(controller.guard).analyze(trials) : null;
    return _column([
      const PageHeading(title: 'معايرة الحركة', subtitle: 'استجابة أوضح وتحكم أدق ضمن أزرار اللعبة الرسمية. قياس حركة اللاعب، دون تغيير سرعة أو فيزياء.'),
      _guardNotice(), _gap(),
      ResponsiveCards(children: [
        MetricCard(label: 'SPIDER MOVEMENT SCORE', value: reading(report?.spiderMovementScore?.toStringAsFixed(1)), icon: Icons.directions_run),
        MetricCard(label: 'الاحتفاظ بالتصويب', value: reading(report?.aimRetention.toStringAsFixed(1), '%'), icon: Icons.my_location),
        MetricCard(label: 'الركض العرضي', value: reading(report?.accidentalSprintRate.toStringAsFixed(1), '%'), icon: Icons.front_hand_outlined),
      ]),
      _gap(),
      FilledButton.icon(onPressed: allowed ? () => showCoachSheet(context, ObservationForm(controller: controller, kind: 'movement', title: 'اختبار حركة فعلي', fields: const {'turnErrorDegrees': 'خطأ الالتفاف بالدرجات (0–180)', 'responseMs': 'زمن الاستجابة المقاس (ms)'}, options: {'action': MovementAction.values.map((value) => value.name).toList()}, booleans: const {'successful': 'هل نجحت الحركة المقصودة؟', 'aimRetained': 'هل بقي التصويب على الهدف؟', 'accidentalSprint': 'هل حدث ركض غير مقصود؟'})) : null, icon: const Icon(Icons.add), label: const Text('تسجيل محاولة حركة')),
      _gap(),
      SpiderCard(child: Column(children: [
        DetailRow('المحاولات', '${trials.length}'),
        DetailRow('موثوقية تفعيل الركض', reading(report?.sprintActivationReliability?.toStringAsFixed(1), '%')),
        DetailRow('دقة تغيير الاتجاه', reading(report?.directionChangeAccuracy?.toStringAsFixed(1), '%')),
        DetailRow('متوسط خطأ الالتفاف', reading(report?.turnOvershootDegrees?.toStringAsFixed(1), '°')),
      ])),
      _gap(),
      const NoticePanel(text: 'لحساب الدرجة الكاملة، سجّل 3 اختبارات تفعيل ركض و3 تغييرات اتجاه و3 التفافات مقاسة على الأقل. اختبر أيضًا Strafe وSprint → ADS وStop → ADS وJump وCrouch وPeek.'),
      if (report != null) ...report.suggestions.map((text) => Padding(padding: const EdgeInsets.only(top: 12), child: NoticePanel(text: text))),
    ]);
  }

  Widget _throwables(BuildContext context) {
    final rows = observations.where((item) => item['kind'] == 'throwables').toList();
    final reports = <ThrowableReport>[];
    if (controller.guard.allowed) {
      for (final obstacle in ThrowableObstacle.values) {
        final trials = <ThrowableTrial>[];
        for (final item in rows.where((item) => jsonMap(item['data'])['obstacle'] == obstacle.name)) {
          final data = jsonMap(item['data']);
          const requiredFields = ['landedAsIntended', 'trajectoryVisible', 'gameDisplaysTrajectory', 'peekReady', 'cancelSucceeded', 'cookTimingSuccessful'];
          if (requiredFields.any((field) => data[field] is! bool)) {
            continue;
          }
          try {
            trials.add(ThrowableTrial(
              id: '${item['id']}', obstacle: obstacle,
              landedAsIntended: data['landedAsIntended'] as bool,
              trajectoryVisible: data['trajectoryVisible'] as bool,
              gameDisplaysTrajectory: data['gameDisplaysTrajectory'] as bool,
              peekReady: data['peekReady'] as bool,
              cancelSucceeded: data['cancelSucceeded'] as bool,
              cookTimingSuccessful: data['cookTimingSuccessful'] as bool,
              viewAngleDegrees: (data['viewAngleDegrees'] as num?)?.toDouble(),
            ));
          } on ArgumentError {
            continue;
          } on TypeError {
            continue;
          }
        }
        if (trials.isNotEmpty) {
          reports.add(ThrowablesCalibrationEngine(controller.guard).analyze(trials));
        }
      }
    }
    return _column([
      const PageHeading(title: 'القنابل والرميات', subtitle: 'اضبط زاوية الكاميرا وPeek والأزرار وتوقيت الرمي حسب ما تسمح اللعبة برؤيته فعلًا.'),
      _guardNotice(), _gap(),
      Wrap(spacing: 10, runSpacing: 10, children: ThrowableObstacle.values.map((value) => Chip(avatar: const Icon(Icons.landscape_outlined, size: 18), label: Text(optionLabel(value.name)))).toList()),
      _gap(),
      FilledButton.icon(onPressed: allowed ? () => showCoachSheet(context, ObservationForm(controller: controller, kind: 'throwables', title: 'اختبار رمية من خلف ساتر', fields: const {'viewAngleDegrees': 'زاوية الكاميرا المقاسة (−90 إلى 90)'}, options: {'obstacle': ThrowableObstacle.values.map((value) => value.name).toList()}, booleans: const {'landedAsIntended': 'هل وصلت الرمية إلى المكان المقصود؟', 'gameDisplaysTrajectory': 'هل تعرض اللعبة مسار الرمي في هذا الوضع؟', 'trajectoryVisible': 'هل كان المسار المعروض واضحًا من زاويتك؟', 'peekReady': 'هل كان Peek / Lean مريحًا؟', 'cancelSucceeded': 'هل نجحت تجربة إلغاء الرمي؟', 'cookTimingSuccessful': 'هل كان Cook والتوقيت كما قصدت؟'})) : null, icon: const Icon(Icons.add), label: const Text('تسجيل تجربة رمي')),
      _gap(),
      const NoticePanel(text: 'البروتوكول: اختبر زاوية النظر → Peek/Lean → حجم وموضع زر الرمي → Hold/Cook/Cancel → وضوح المسار الظاهر داخل اللعبة. لا يُستنتج مسار خلف صخرة أو جدار ولا تُعرض معلومات محجوبة.'),
      _gap(),
      if (reports.isEmpty) const EmptyPanel(title: 'لكل ساتر تجربة مستقلة', message: 'سجّل الرميات الفعلية. تبدأ توصيات التحكم بعد نمط متكرر من خمس محاولات، ولا تُطبّق أي قيمة تلقائيًا.', icon: Icons.sports_handball),
      for (final report in reports) ...[
        SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(optionLabel(report.obstacle.name), style: const TextStyle(color: spiderTeal, fontSize: 18, fontWeight: FontWeight.bold)),
          DetailRow('المحاولات', '${report.sampleCount}'),
          DetailRow('الوصول للمكان المقصود', '${report.successRate.toStringAsFixed(1)}%'),
          DetailRow('قابلية استخدام المسار المرئي', reading(report.visibleTrajectoryUsability?.toStringAsFixed(1), '%')),
          DetailRow('زاوية ناجحة مرصودة، لا تلقائية', reading(report.observedSuccessfulViewAngle?.toStringAsFixed(1), '°')),
          for (final suggestion in report.suggestions) Padding(padding: const EdgeInsets.only(top: 12), child: Text(suggestion, style: const TextStyle(height: 1.8, color: spiderMuted))),
        ])), _gap(),
      ],
    ]);
  }

  Widget _death(BuildContext context) {
    final rows = observations.where((item) => item['kind'] == 'death').toList();
    final samples = rows.map((item) => DeathObservation(id: '${item['id']}', recordedAt: DateTime.tryParse('${item['timestamp']}') ?? DateTime.fromMillisecondsSinceEpoch(0), observedCause: DeathCause.values.firstWhere((value) => value.name == jsonMap(item['data'])['cause'], orElse: () => DeathCause.inconclusive), reliableEvidence: false)).toList();
    final report = controller.guard.allowed && samples.isNotEmpty ? DeathAnalysisEngine(controller.guard).analyze(samples) : null;
    return _column([
      const PageHeading(title: 'تحليل الوفاة والإصابات', subtitle: 'افصل التصويب والارتداد عن الشبكة والإطارات والحرارة والتمركز. وفاة واحدة لا تبرّر تغيير الحساسية.'),
      _guardNotice(), _gap(),
      const NoticePanel(text: 'CAUSE = INCONCLUSIVE عند غياب دليل كافٍ. لا نستطيع إجبار السيرفر على تسجيل إصابة أو قياس Packet Loss وDesync من إحساس اللاعب وحده. التحليل الحالي يعتمد على مراجعتك بعد اللعب.'),
      _gap(),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: allowed ? () => showCoachSheet(context, ObservationForm(controller: controller, kind: 'death', title: 'مراجعة وفاة بعد اللعب', fields: const {'latencyMs': 'Ping الظاهر داخل اللعبة (ms)', 'jitterMs': 'Jitter من مصدر قياس موثوق (ms)', 'packetLossPercent': 'فقد الحزم من مصدر موثوق (%)', 'thermalSeverity': 'شدة الحرارة المرصودة (0–6)'}, options: {'cause': DeathCause.values.map((value) => value.name).toList()})) : null, icon: const Icon(Icons.add), label: const Text('تسجيل مراجعة وفاة')),
        OutlinedButton.icon(onPressed: allowed ? () => showCoachSheet(context, ObservationForm(controller: controller, kind: 'hit', title: 'تشخيص الإصابات من دليل الجلسة', fields: const {'observedShots': 'إجمالي الطلقات المرصودة', 'observedHits': 'الإصابات المرصودة', 'aimMisses': 'خطأ تصويب قبل الارتداد', 'recoilMisses': 'فقد إصابة بسبب الارتداد المرصود', 'targetMovementMisses': 'فقد إصابة مع خروج الهدف', 'latencyMs': 'Ping من المصدر (ms)', 'jitterMs': 'Jitter موثوق (ms)', 'packetLossPercent': 'فقد الحزم المقاس (%)', 'fpsDropPercent': 'هبوط FPS المقاس (%)', 'thermalSeverity': 'شدة الحرارة (0–6)'}, booleans: const {'visualHitFeedback': 'هل ظهرت إشارة إصابة مرئية؟', 'observedDamageResult': 'هل ظهرت نتيجة ضرر فعلية؟'})) : null, icon: const Icon(Icons.gps_fixed), label: const Text('مراجعة Hit Registration')),
      ]),
      _gap(),
      SpiderCard(child: Column(children: [
        DetailRow('المراجعات المحفوظة', '${rows.length}'),
        const DetailRow('السبب المؤكد', 'غير محسوم • مراجعات يدوية'),
        const DetailRow('تحليل شاشة تلقائي', 'غير متاح • التحليل المباشر مقفول'),
        const DetailRow('Hit Registration من السيرفر', 'غير متاح عبر API رسمي'),
      ])),
      if (report != null) ...[
        _gap(),
        SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('أنماط الملاحظات، وليست أسبابًا مؤكدة', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final entry in report.patterns.entries) DetailRow(optionLabel(entry.key.name), '${entry.value}'),
          for (final note in report.recommendations) Padding(padding: const EdgeInsets.only(top: 14), child: Text(note, style: const TextStyle(height: 1.8, color: spiderMuted))),
        ])),
      ],
      ..._hitReports(),
    ]);
  }

  List<Widget> _hitReports() {
    if (!controller.guard.allowed) {
      return [];
    }
    return observations.where((item) => item['kind'] == 'hit').toList().reversed.take(5).map((row) {
      final data = jsonMap(row['data']);
      int? count(String key) => (data[key] as num?)?.toInt();
      double? number(String key) => (data[key] as num?)?.toDouble();
      final report = HitRegistrationDiagnostics(controller.guard).diagnose(HitEvidence(
        source: 'MANUAL_REVIEW', reliableMeasurements: false,
        observedShots: count('observedShots'), observedHits: count('observedHits'),
        aimMisses: count('aimMisses'), recoilMisses: count('recoilMisses'), targetMovementMisses: count('targetMovementMisses'),
        latencyMs: number('latencyMs'), jitterMs: number('jitterMs'), packetLossPercent: number('packetLossPercent'), fpsDropPercent: number('fpsDropPercent'), thermalSeverity: count('thermalSeverity'),
        visualHitFeedback: data['visualHitFeedback'] as bool?, observedDamageResult: data['observedDamageResult'] as bool?,
      ));
      return Padding(padding: const EdgeInsets.only(top: 16), child: SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hit Registration • ${dateLabel(row['timestamp'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const DetailRow('CAUSE', 'INCONCLUSIVE'),
        for (final evidence in report.evidence) Padding(padding: const EdgeInsets.only(top: 10), child: Text(evidence, style: const TextStyle(height: 1.8, color: spiderMuted))),
      ])));
    }).toList();
  }

  Widget _proposalCard(BuildContext context, Map<String, dynamic> proposal, {bool testing = false}) {
    final status = '${proposal['status']}';
    final id = '${proposal['id']}';
    final test = jsonMap(proposal['test']);
    return SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StatusPill(text: statusLabel(status), good: status == 'APPROVED_FINAL' || status == 'PASSED'),
      _gap(16),
      Text(settingTitle('${proposal['key']}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      _gap(14),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: spiderBackground, borderRadius: BorderRadius.circular(12)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Column(children: [const Text('الحالي', style: TextStyle(color: spiderMuted)), Text('${proposal['current']}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))]),
        const Icon(Icons.arrow_back_rounded, color: spiderTeal),
        Column(children: [const Text('المقترح', style: TextStyle(color: spiderMuted)), Text('${proposal['proposed']}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: spiderTeal))]),
      ])),
      DetailRow('المشكلة والسبب', '${proposal['reason']}'),
      DetailRow('الدليل', '${proposal['evidence']}'),
      DetailRow('عدد العينات', '${proposal['sampleCount']}'),
      DetailRow('الفرق', '${proposal['delta']}'),
      DetailRow('الأثر المتوقع', '${proposal['expected']}'),
      DetailRow('المقايضة أو المخاطر', '${proposal['risk']}'),
      if (proposal['backupId'] != null) const DetailRow('Backup كامل للملف المسجّل', 'محفوظ قبل إنشاء النسخة التجريبية'),
      if (test.isNotEmpty) ...[
        const Divider(),
        const Text('نتيجة المقارنة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        _gap(10),
        for (final reason in (test['reasons'] as List? ?? [])) Text('• $reason', style: const TextStyle(height: 1.8)),
        _gap(14),
        _comparisonTable(proposal),
      ],
      _gap(18),
      if (testing) const NoticePanel(text: 'تطبّق القيمة بنفسك داخل إعدادات PUBG الرسمية، ثم تختبر في Warehouse أو Unranked. لا تتحول هذه النسخة إلى معتمدة إلا بعد نجاح المقارنة وقرارك النهائي.'),
      _gap(12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (['PROPOSED', 'DEFERRED'].contains(status)) FilledButton.icon(onPressed: allowed ? () => _run(context, () => controller.approveForTest(id), 'حُفظ Backup وأُنشئت نسخة تجريبية. طبّق القيمة يدويًا واختبرها.') : null, icon: const Icon(Icons.science_outlined), label: const Text('موافقة على التجربة + Backup')),
        if (['TESTING', 'PASSED', 'FAILED'].contains(status)) OutlinedButton.icon(onPressed: allowed ? () => showCoachSheet(context, MetricsForm(controller: controller, proposal: proposal)) : null, icon: const Icon(Icons.fact_check_outlined), label: Text(status == 'TESTING' ? 'تسجيل الاختبار الفعلي' : 'إعادة اختبار')),
        if (status == 'PASSED') FilledButton.icon(onPressed: allowed ? () => _run(context, () => controller.approveFinal(id), 'تم اعتماد النسخة محليًا بقرارك النهائي.') : null, icon: const Icon(Icons.verified_outlined), label: const Text('أوافق على الاعتماد النهائي')),
        if (['PROPOSED', 'DEFERRED', 'TESTING', 'PASSED', 'FAILED'].contains(status)) OutlinedButton(onPressed: allowed ? () => _run(context, () => controller.reject(id), 'تم رفض الاقتراح. أعد القيمة المعتمدة يدويًا داخل PUBG إذا كنت جرّبتها.') : null, child: const Text('رفض')),
        if (status == 'PROPOSED') TextButton(onPressed: allowed ? () => _run(context, () => controller.defer(id)) : null, child: const Text('تأجيل')),
        if (testing) TextButton.icon(onPressed: allowed ? () => _run(context, controller.restore, 'تم استرجاع الملف المحلي. راجع صفحة الاسترجاع وأعد القيم داخل اللعبة يدويًا.') : null, icon: const Icon(Icons.restore), label: const Text('استرجاع')),
      ]),
    ]));
  }

  Widget _comparisonTable(Map<String, dynamic> proposal) {
    final baseline = jsonMap(proposal['baseline']);
    final after = jsonMap(jsonMap(proposal['test'])['metrics']);
    return Column(children: [
      const Row(children: [Expanded(flex: 3, child: Text('المؤشر', style: TextStyle(color: spiderMuted))), Expanded(child: Text('قبل', textAlign: TextAlign.center)), Expanded(child: Text('بعد', textAlign: TextAlign.center))]),
      const Divider(),
      for (final key in metricLabels.keys) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Expanded(flex: 3, child: Text(metricLabels[key]!, style: const TextStyle(fontSize: 12))),
        Expanded(child: Text(reading((baseline[key] as num?)?.toStringAsFixed(1)), textAlign: TextAlign.center)),
        Expanded(child: Text(reading((after[key] as num?)?.toStringAsFixed(1)), textAlign: TextAlign.center)),
      ])),
    ]);
  }

  Widget _proposals(BuildContext context) {
    final proposals = jsonList(state['proposals']);
    final notifications = jsonList(state['notifications']);
    return _column([
      const PageHeading(title: 'التعديلات المقترحة', subtitle: 'السبب والدليل والمقايضة أمامك قبل التجربة. لا يوجد اعتماد مباشر لاقتراح لم يُختبر.'),
      _guardNotice(), _gap(),
      if (notifications.isNotEmpty) ...[
        NoticePanel(icon: Icons.notifications_outlined, text: 'آخر إشعار محلي: ${notifications.last['body']}'), _gap(),
      ],
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: allowed ? () => showCoachSheet(context, ProposalForm(controller: controller)) : null, icon: const Icon(Icons.add), label: const Text('اقتراح من نتائج الاختبار'))),
      _gap(),
      if (proposals.isEmpty) const EmptyPanel(title: 'لا توجد تعديلات مقترحة', message: 'سجّل إعداداتك الحالية وخمس عينات على الأقل للسياق نفسه. عندما تدعم النتائج تغييرًا، وثّق سببه ودليله هنا.', icon: Icons.auto_awesome_outlined)
      else ...proposals.reversed.map((proposal) => Padding(padding: const EdgeInsets.only(bottom: 18), child: _proposalCard(context, proposal))),
    ]);
  }

  Widget _testing(BuildContext context) {
    final proposals = jsonList(state['proposals']).where((proposal) => proposal['id'] == state['testingId']).toList();
    return _column([
      const PageHeading(title: 'الاختبار والمقارنة', subtitle: 'تحسّن ثبات التصويب والإصابات شرط أساسي. تدهور مؤشرات الأداء الأساسية يمنع نجاح النسخة.'),
      _guardNotice(), _gap(),
      if (proposals.isEmpty) EmptyPanel(title: 'لا توجد نسخة تجريبية نشطة', message: 'ابدأ بالموافقة على تجربة اقتراح. يحفظ التطبيق نسخة احتياطية قبل إنشاء TESTING، ويبقى إصدارك المعتمد محفوظًا.', icon: Icons.science_outlined, action: OutlinedButton(onPressed: () => onNavigate(8), child: const Text('عرض المقترحات')))
      else _proposalCard(context, proposals.first, testing: true),
      _gap(),
      const NoticePanel(text: 'نتائج Warehouse أو Unranked فقط تُقبل لاعتماد المقارنة النهائية. التدريب متاح لجمع القياسات الأولية. إذا أُغلق التطبيق أثناء الاختبار، تُستعاد حالة TESTING وBackup والإصدار المعتمد من قاعدة البيانات.'),
    ]);
  }

  Widget _history(BuildContext context) {
    final versions = jsonList(state['versions']);
    return _column([
      const PageHeading(title: 'سجل الإصدارات', subtitle: 'قراراتك ونسخك ونتائج الاختبار محفوظة محليًا حسب الجهاز. النسخ الاحتياطية محمية من الحذف داخل التطبيق.'),
      if (versions.isEmpty) const EmptyPanel(title: 'لا يوجد سجل بعد', message: 'يبدأ V1 عندما توثّق إعداداتك الحالية.')
      else ...versions.reversed.map((version) => Padding(padding: const EdgeInsets.only(bottom: 16), child: SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('V${version['number']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: spiderTeal)), const SizedBox(width: 14), Expanded(child: Text(statusLabel(version['status'])))]),
        DetailRow('الوقت', dateLabel(version['timestamp'])),
        DetailRow('الملف', '${version['profile']}'),
        DetailRow('السبب', '${version['reason']}'),
        DetailRow('الإعدادات الموثّقة', '${jsonMap(version['settings']).length}'),
        if (version['backupId'] != null) const DetailRow('النسخة الاحتياطية', 'محفوظة'),
        if (version['testResults'] != null) DetailRow('نتيجة الاختبار', jsonMap(version['testResults'])['passed'] == true ? 'اجتاز المقارنة' : 'لم يجتز المقارنة'),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('تفاصيل الإعدادات'), children: jsonMap(version['settings']).entries.map((entry) => DetailRow(settingTitle(entry.key), '${entry.value}')).toList()),
      ])))),
    ]);
  }

  Widget _restore(BuildContext context) {
    final backups = jsonList(state['backups']);
    final settings = jsonMap(approved['settings']);
    final canRestore = state['testingId'] != null || approved['backupId'] != null;
    return _column([
      const PageHeading(title: 'استرجاع الإعدادات', subtitle: 'استرجاع النسخة المحلية السابقة بضغطة. تبقى كل التغييرات داخل PUBG يدوية وبقرارك.'),
      const NoticePanel(warning: true, text: 'Backup يشمل كامل الإعدادات التي وثّقتها داخل SPIDER AIM فقط. لا يمكن قراءة أو حفظ إعدادات PUBG غير المسجّلة. بعد الاسترجاع هنا، أعد القيم المعروضة يدويًا داخل اللعبة.'),
      _gap(),
      FilledButton.icon(onPressed: allowed && canRestore ? () => _run(context, controller.restore, 'استُرجعت النسخة المحلية. القيم أدناه هي المرجع لإعادتها يدويًا داخل PUBG.') : null, icon: const Icon(Icons.restore), label: const Text('استرجاع النسخة السابقة الآن')),
      _gap(),
      if (!allowed) ...[_guardNotice(), _gap()],
      SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('الإعدادات المعتمدة الحالية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (settings.isEmpty) const Padding(padding: EdgeInsets.only(top: 16), child: Text('لم تُسجّل إعدادات بعد.')),
        for (final entry in settings.entries) DetailRow(settingTitle(entry.key), reading(entry.value)),
      ])),
      _gap(),
      SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('النسخ الاحتياطية المحفوظة: ${backups.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final backup in backups.reversed) DetailRow(dateLabel(backup['timestamp']), '${backup['reason']}'),
      ])),
    ]);
  }

  Widget _safety(BuildContext context) => _column([
    const PageHeading(title: 'الأمان وقفل Ranked', subtitle: 'UNKNOWN_BLOCKED افتراضيًا. تصريح المستخدم يفتح مراجعة نتائج جلسة سابقة فقط.'),
    SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StatusPill(text: modeLabel(controller.guard.mode), good: controller.guard.allowed),
      _gap(20),
      const Text('أي جلسة تراجع نتائجها؟', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      _gap(10),
      const Text('اختيارك تصريح يدوي وليس اكتشافًا موثوقًا لوضع PUBG الحالي. عند مغادرة التطبيق أو انتهاء التصريح يعود القفل إلى UNKNOWN.', style: TextStyle(color: spiderMuted, height: 1.8)),
      _gap(20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final mode in [GameMode.training, GameMode.warehouse, GameMode.safeUnranked]) OutlinedButton.icon(onPressed: controller.busy ? null : () => _run(context, () => controller.selectMode(mode), 'فُتحت مراجعة محلية لنتائج الجلسة المصرّح بها.'), icon: const Icon(Icons.check_circle_outline), label: Text(mode == GameMode.training ? 'نتائج Training' : mode == GameMode.warehouse ? 'نتائج Warehouse' : 'نتائج Unranked')),
        FilledButton.tonalIcon(onPressed: () => _run(context, () => controller.selectMode(GameMode.rankedBlocked)), icon: const Icon(Icons.lock), label: const Text('Ranked • قفل كامل')),
        TextButton(onPressed: () => _run(context, () => controller.selectMode(GameMode.unknownBlocked)), child: const Text('الوضع غير معروف')),
      ]),
    ])),
    _gap(),
    const SpiderCard(child: Column(children: [
      DetailRow('لاعب NON-GYRO', 'GYROSCOPE = DISABLED'),
      DetailRow('نوع الإدخال', 'TOUCH_ONLY'),
      DetailRow('ADS Gyroscope', 'DISABLED'),
      DetailRow('تطبيق إعدادات PUBG', 'يدوي من المستخدم فقط'),
      DetailRow('التقاط الشاشة والتحليل المباشر', 'مقفولان؛ لا تكامل موثوق للوضع'),
      DetailRow('تحكم آلي بالتصويب أو الحركة', 'غير موجود'),
      DetailRow('التخزين', 'محلي على الجهاز'),
      DetailRow('خفض FPS أو جودة PUBG تلقائيًا', 'غير مسموح'),
    ])),
    _gap(),
    const NoticePanel(text: 'لا صلاحيات Root أو Accessibility، ولا تعديل ذاكرة أو ملفات اللعبة أو حزم الشبكة. تُعرض الرميات فقط ضمن الرؤية الرسمية. الجهاز الجديد يبدأ بملف مستقل، وأي نقص في الدليل يبقى غير محسوم.'),
  ]);
}
