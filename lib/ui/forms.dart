import 'package:flutter/material.dart';

import '../core/coach_controller.dart';
import 'components.dart';
import 'theme.dart';

const weaponChoices = ['M416', 'AUG', 'SCAR-L', 'AKM', 'ACE32', 'UMP45', 'DP-28'];
const scopeChoices = ['Iron Sight', 'Red Dot', 'Holo', '2x', '3x', '4x', '6x', '8x'];
const settingLabels = {
  'ads': 'حساسية ADS',
  'camera': 'حساسية الكاميرا',
  'fireButtonSize': 'حجم زر الإطلاق',
  'fireButtonX': 'موضع زر الإطلاق أفقيًا',
  'fireButtonY': 'موضع زر الإطلاق عموديًا',
  'joystickSize': 'حجم عصا الحركة',
  'joystickX': 'موضع عصا الحركة أفقيًا',
  'joystickY': 'موضع عصا الحركة عموديًا',
  'sprintActivation': 'قيمة تفعيل الركض الرسمية',
  'peekButtonSize': 'حجم زر الميل',
  'peekButtonX': 'موضع زر الميل أفقيًا',
  'peekButtonY': 'موضع زر الميل عموديًا',
  'throwableCamera': 'حساسية كاميرا الرمي',
  'throwButtonSize': 'حجم زر الرمي',
  'throwButtonX': 'موضع زر الرمي أفقيًا',
  'throwButtonY': 'موضع زر الرمي عموديًا',
  'cookButtonSize': 'حجم زر Cook',
  'cancelButtonSize': 'حجم زر إلغاء الرمي',
  'fov': 'مجال الرؤية FOV المتاح رسميًا',
};
const metricLabels = {
  'aimStability': 'ثبات التصويب (0–100)',
  'hitRate': 'نسبة الإصابات الفعلية (%)',
  'sprayGrouping': 'تشتت الرش (0–100؛ الأقل أفضل)',
  'trackingScore': 'ثبات التتبع (0–100)',
  'overshootRate': 'تجاوز الهدف (%)',
  'undershootRate': 'عدم بلوغ الهدف (%)',
  'acquisitionMs': 'زمن التقاط الهدف (ms)',
  'adsStability': 'ثبات ADS (0–100)',
  'movementRetention': 'الاحتفاظ بالهدف أثناء الحركة (%)',
  'fpsStability': 'ثبات FPS موثوق (0–100)',
  'thermalImpact': 'شدة الحرارة (0–6)',
  'batteryDrain': 'نزف البطارية (%/ساعة)',
};

const aimDetailLabels = {
  'verticalRecoil': 'الارتداد العمودي (وحدة إزاحة ثابتة)',
  'horizontalDrift': 'الانحراف الأفقي (نفس وحدة الإزاحة)',
  'firstShotStability': 'ثبات الطلقة الأولى (0–100)',
  'adsStabilizationMs': 'زمن استقرار ADS (ms)',
  'fingerDragConsistency': 'اتساق سحب الإصبع (0–100)',
  'sprayConsistency': 'اتساق الرش (0–100)',
  'hits': 'عدد الإصابات المؤكدة في الاختبار',
  'shots': 'عدد الطلقات الفعلية في الاختبار',
  'latencyMs': 'Ping موثوق لنفس الاختبار (ms)',
  'jitterMs': 'Jitter موثوق لنفس الاختبار (ms)',
  'packetLossPercent': 'فقد الحزم المقاس (%)',
};

const _optionLabels = {
  'sprintActivation': 'تفعيل الركض', 'directionChange': 'تغيير الاتجاه',
  'strafe': 'حركة جانبية', 'turn90': 'التفاف 90°', 'turn180': 'التفاف 180°',
  'sprintToAds': 'من الركض إلى ADS', 'stopToAds': 'من التوقف إلى ADS',
  'jump': 'القفز', 'crouch': 'الانحناء', 'peek': 'الميل / Peek',
  'rock': 'صخرة', 'wall': 'جدار', 'barrier': 'حاجز', 'window': 'نافذة', 'edge': 'حافة',
  'inconclusive': 'غير محسوم', 'aimOvershoot': 'تجاوز الهدف', 'aimUndershoot': 'عدم بلوغ الهدف',
  'poorTracking': 'ضعف التتبع', 'badRecoilControl': 'ضعف التحكم بالارتداد', 'lateAds': 'تأخر ADS',
  'badPeek': 'ميل غير مناسب', 'poorMovement': 'خطأ حركة', 'poorPositioning': 'تمركز غير مناسب',
  'exposureTooLong': 'انكشاف طويل', 'wrongScopeForDistance': 'سكوب غير مناسب', 'fpsDrop': 'هبوط FPS',
  'thermalIssue': 'مشكلة حرارة', 'networkIssue': 'مشكلة شبكة', 'tacticalMistake': 'خطأ تكتيكي',
};

String optionLabel(String value) => _optionLabels[value] ?? value;

String settingTitle(String key) {
  final parts = key.split('::');
  final field = parts.last;
  return '${settingLabels[field] ?? field}${parts.length > 1 ? ' • ${parts.first}' : ''}';
}

Future<void> showCoachSheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: spiderSurface,
  constraints: const BoxConstraints(maxWidth: 700),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  ),
);

class ContextPicker extends StatelessWidget {
  const ContextPicker({super.key, required this.weapon, required this.scope, required this.attachment, required this.distance, required this.onWeapon, required this.onScope});
  final String weapon;
  final String scope;
  final TextEditingController attachment;
  final TextEditingController distance;
  final ValueChanged<String> onWeapon;
  final ValueChanged<String> onScope;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: weapon,
          decoration: const InputDecoration(labelText: 'السلاح'),
          items: weaponChoices.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
          onChanged: (value) { if (value != null) { onWeapon(value); } },
        )),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: scope,
          decoration: const InputDecoration(labelText: 'السكوب'),
          items: scopeChoices.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
          onChanged: (value) { if (value != null) { onScope(value); } },
        )),
      ]),
      const SizedBox(height: 14),
      TextFormField(
        controller: attachment,
        decoration: const InputDecoration(labelText: 'الملحقات الفعلية', hintText: 'Compensator أو None'),
        validator: (value) => value == null || value.trim().isEmpty ? 'أدخل الملحقات أو None' : value.contains('|') || value.contains('::') ? 'لا تستخدم | أو ::' : null,
      ),
      const SizedBox(height: 14),
      NumberField(controller: distance, label: 'مسافة الاختبار بالمتر', requiredValue: true, max: 2000, min: 1),
    ],
  );
}

class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.controller, required this.label, this.requiredValue = false, this.min = 0, this.max = 100, this.integer = false});
  final TextEditingController controller;
  final String label;
  final bool requiredValue;
  final double min;
  final double max;
  final bool integer;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer, signed: min < 0),
    textDirection: TextDirection.ltr,
    decoration: InputDecoration(labelText: label, helperText: requiredValue ? null : 'اتركه فارغًا إذا لم تتوفر قراءة موثوقة'),
    validator: (value) {
      if (value == null || value.trim().isEmpty) {
        return requiredValue ? 'هذا الحقل مطلوب' : null;
      }
      final parsed = double.tryParse(value);
      if (parsed == null || !parsed.isFinite || parsed < min || parsed > max || (integer && parsed != parsed.roundToDouble())) {
        return 'أدخل ${integer ? 'عددًا صحيحًا' : 'رقمًا'} بين $min و$max';
      }
      return null;
    },
  );
}

class BaselineForm extends StatefulWidget {
  const BaselineForm({super.key, required this.controller});
  final CoachController controller;
  @override
  State<BaselineForm> createState() => _BaselineFormState();
}

class _BaselineFormState extends State<BaselineForm> {
  final _form = GlobalKey<FormState>();
  final _attachment = TextEditingController();
  final _distance = TextEditingController();
  final _values = {for (final key in settingLabels.keys) key: TextEditingController()};
  String _weapon = weaponChoices.first;
  String _scope = scopeChoices.first;
  bool _confirmed = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _attachment.dispose();
    _distance.dispose();
    for (final value in _values.values) { value.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    if (!_confirmed) { setState(() => _error = 'أكد أن القيم من إعداداتك الحالية.'); return; }
    final values = <String, double>{};
    final contextKey = '$_weapon|$_scope|${_attachment.text.trim()}|${double.parse(_distance.text).toString().replaceFirst(RegExp(r'\.0$'), '')}';
    for (final entry in _values.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) { values['$contextKey::${entry.key}'] = value; }
    }
    if (values.isEmpty) { setState(() => _error = 'أدخل إعدادًا حاليًا واحدًا على الأقل.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.controller.saveBaseline(values);
      if (mounted) {
        if (widget.controller.error != null) { setState(() => _error = widget.controller.error); }
        else { Navigator.pop(context); }
      }
    } catch (error) { if (mounted) { setState(() => _error = '$error'); } }
    if (mounted) { setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: 'توثيق الإعدادات الحالية',
    subtitle: 'انسخ القيم التي تستخدمها الآن من PUBG. هذا حفظ مرجعي محلي؛ لا يغيّر اللعبة.',
    formKey: _form,
    error: _error,
    saving: _saving,
    onSave: _save,
    saveLabel: 'حفظ المرجع الحالي',
    children: [
      ContextPicker(weapon: _weapon, scope: _scope, attachment: _attachment, distance: _distance, onWeapon: (value) => setState(() => _weapon = value), onScope: (value) => setState(() => _scope = value)),
      const SizedBox(height: 20),
      for (final entry in _values.entries.where((entry) => ['ads', 'camera', 'fireButtonSize', 'joystickSize', 'peekButtonSize', 'throwableCamera'].contains(entry.key))) ...[
        NumberField(controller: entry.value, label: settingLabels[entry.key]!, max: 400),
        const SizedBox(height: 14),
      ],
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('مواضع الأزرار والرمي وFOV'),
        subtitle: const Text('إعدادات إضافية اختيارية ضمن القيم الرسمية'),
        children: [
          for (final entry in _values.entries.where((entry) => !['ads', 'camera', 'fireButtonSize', 'joystickSize', 'peekButtonSize', 'throwableCamera'].contains(entry.key))) ...[
            NumberField(controller: entry.value, label: settingLabels[entry.key]!, max: 400),
            const SizedBox(height: 14),
          ],
        ],
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _confirmed,
        onChanged: (value) => setState(() => _confirmed = value ?? false),
        title: const Text('هذه إعداداتي الحالية الفعلية لهذا الجهاز، وليست قيمًا مقترحة.'),
      ),
    ],
  );
}

class MetricsForm extends StatefulWidget {
  const MetricsForm({super.key, required this.controller, this.proposal});
  final CoachController controller;
  final Map<String, dynamic>? proposal;
  @override
  State<MetricsForm> createState() => _MetricsFormState();
}

class _MetricsFormState extends State<MetricsForm> {
  final _form = GlobalKey<FormState>();
  final _attachment = TextEditingController();
  final _distance = TextEditingController();
  final _sampleCount = TextEditingController();
  final _values = {for (final key in metricLabels.keys) key: TextEditingController()};
  final _details = {for (final key in aimDetailLabels.keys) key: TextEditingController()};
  String _weapon = weaponChoices.first;
  String _scope = scopeChoices.first;
  bool _manualApplied = false;
  bool _actualTest = false;
  bool _networkReliable = false;
  bool _framesReliable = false;
  bool _saving = false;
  String? _error;
  bool get _testing => widget.proposal != null;

  @override
  void dispose() {
    _attachment.dispose();
    _distance.dispose();
    _sampleCount.dispose();
    for (final value in _values.values) { value.dispose(); }
    for (final value in _details.values) { value.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    if (!_actualTest || (_testing && !_manualApplied)) { setState(() => _error = 'أكد إجراء الاختبار الفعلي والتطبيق اليدوي عند التجربة.'); return; }
    final metrics = <String, double>{};
    for (final entry in _values.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) { metrics[entry.key] = value; }
    }
    if (metrics.isEmpty) { setState(() => _error = 'أدخل قياسًا موثوقًا واحدًا على الأقل.'); return; }
    if ((metrics['overshootRate'] ?? 0) + (metrics['undershootRate'] ?? 0) > 100) { setState(() => _error = 'مجموع Overshoot وUndershoot لا يمكن أن يتجاوز 100٪.'); return; }
    final aimDetails = <String, dynamic>{'networkMetricsReliable': _networkReliable, 'frameMetricsReliable': _framesReliable};
    for (final entry in _details.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) {
        aimDetails[entry.key] = entry.key == 'hits' || entry.key == 'shots' ? value.toInt() : value;
      }
    }
    final hits = aimDetails['hits'] as int?;
    final shots = aimDetails['shots'] as int?;
    if ((hits == null) != (shots == null) || (shots != null && (shots <= 0 || hits! > shots))) { setState(() => _error = 'أدخل الإصابات والطلقات معًا؛ لا يجوز أن تتجاوز الإصابات عدد الطلقات.'); return; }
    if (hits != null && shots != null && metrics['hitRate'] != null && (metrics['hitRate']! - hits / shots * 100).abs() > 1) { setState(() => _error = 'نسبة الإصابات لا تطابق عدد الإصابات والطلقات.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      if (_testing) {
        metrics['sampleCount'] = double.parse(_sampleCount.text);
        await widget.controller.recordTest('${widget.proposal!['id']}', metrics, manualApplied: _manualApplied);
      } else {
        final contextKey = '$_weapon|$_scope|${_attachment.text.trim()}|${double.parse(_distance.text).toString().replaceFirst(RegExp(r'\.0$'), '')}';
        await widget.controller.addObservation('aim', {'context': contextKey, 'metrics': metrics, 'aimDetails': aimDetails, 'source': 'MANUAL_UNRANKED_TEST'});
      }
      if (mounted) {
        if (widget.controller.error != null) { setState(() => _error = widget.controller.error); }
        else { Navigator.pop(context); }
      }
    } catch (error) { if (mounted) { setState(() => _error = '$error'); } }
    if (mounted) { setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: _testing ? 'نتائج النسخة التجريبية' : 'تسجيل عينة اختبار',
    subtitle: 'أدخل نتائج اختبار حقيقي غير مصنف، بنفس السلاح والسكوب والملحقات والمسافة. لا تخمّن القياسات المفقودة.',
    formKey: _form,
    error: _error,
    saving: _saving,
    onSave: _save,
    saveLabel: _testing ? 'حفظ النتائج ومقارنة النسختين' : 'حفظ العينة',
    children: [
      if (!_testing) ContextPicker(weapon: _weapon, scope: _scope, attachment: _attachment, distance: _distance, onWeapon: (value) => setState(() => _weapon = value), onScope: (value) => setState(() => _scope = value)),
      if (_testing) ...[
        NoticePanel(text: settingTitle('${widget.proposal!['key']}')),
        const SizedBox(height: 14),
        NumberField(controller: _sampleCount, label: 'عدد المحاولات الفعلية في هذه المقارنة', requiredValue: true, min: 5, max: 10000, integer: true),
      ],
      const SizedBox(height: 18),
      const NoticePanel(text: 'ثبات التصويب ونسبة الإصابات أولوية. القياسات غير المتاحة تبقى مجهولة، وقد تمنع الاعتماد إذا لم تكفِ للمقارنة. FPS هنا قياس للعبة من مصدر موثوق، وليس معدل تحديث الشاشة.'),
      const SizedBox(height: 18),
      for (final entry in _values.entries) ...[
        NumberField(controller: entry.value, label: metricLabels[entry.key]!, max: entry.key == 'acquisitionMs' ? 60000 : entry.key == 'thermalImpact' ? 6 : entry.key == 'batteryDrain' ? 1000 : 100),
        const SizedBox(height: 14),
      ],
      if (!_testing) ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('قياسات تفصيلية للتصويب والشبكة'),
        subtitle: const Text('اختيارية؛ لا تُخمن القيم المجهولة'),
        children: [
          for (final entry in _details.entries) ...[
            NumberField(controller: entry.value, label: aimDetailLabels[entry.key]!, integer: entry.key == 'hits' || entry.key == 'shots', max: entry.key.endsWith('Ms') || ['hits', 'shots', 'verticalRecoil', 'horizontalDrift'].contains(entry.key) ? 60000 : 100),
            const SizedBox(height: 14),
          ],
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: _networkReliable, onChanged: (value) => setState(() => _networkReliable = value ?? false), title: const Text('قيم الشبكة من مصدر قياس موثوق لنفس الاختبار.')),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: _framesReliable, onChanged: (value) => setState(() => _framesReliable = value ?? false), title: const Text('قيمة ثبات FPS مقاسة للعبة فعلًا، وليست معدل تحديث الشاشة.')),
        ],
      ),
      CheckboxListTile(contentPadding: EdgeInsets.zero, value: _actualTest, onChanged: (value) => setState(() => _actualTest = value ?? false), title: const Text('أجريت الاختبار فعلًا في Training أو Warehouse أو Unranked، وهذه نتائجه.')),
      if (_testing) CheckboxListTile(contentPadding: EdgeInsets.zero, value: _manualApplied, onChanged: (value) => setState(() => _manualApplied = value ?? false), title: const Text('طبّقت القيمة التجريبية يدويًا داخل إعدادات PUBG الرسمية.')),
    ],
  );
}

class ProposalForm extends StatefulWidget {
  const ProposalForm({super.key, required this.controller, this.initial});
  final CoachController controller;
  final Map<String, dynamic>? initial;
  @override
  State<ProposalForm> createState() => _ProposalFormState();
}

class _ProposalFormState extends State<ProposalForm> {
  final _form = GlobalKey<FormState>();
  final _proposed = TextEditingController();
  final _reason = TextEditingController();
  final _evidence = TextEditingController();
  final _expected = TextEditingController();
  final _risk = TextEditingController();
  String? _key;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> get _settings => jsonMap(jsonMap(widget.controller.state['approved'])['settings']);
  int get _sampleCount => jsonList(widget.controller.state['observations']).where((item) => item['kind'] == 'aim' && jsonMap(item['data'])['context'] == _key?.split('::').first && item['approvedVersion'] == jsonMap(widget.controller.state['approved'])['number'] && item['testingId'] == null).length;

  @override
  void initState() {
    super.initState();
    if (_settings.isNotEmpty) {
      _key = _settings.keys.first;
    }
    final initial = widget.initial;
    if (initial != null) {
      _key = initial['key'] as String? ?? _key;
      _proposed.text = '${initial['proposed'] ?? ''}';
      _reason.text = '${initial['reason'] ?? ''}';
      _evidence.text = '${initial['evidence'] ?? ''}';
      _expected.text = '${initial['expected'] ?? ''}';
      _risk.text = '${initial['risk'] ?? ''}';
    }
  }
  @override
  void dispose() { for (final field in [_proposed, _reason, _evidence, _expected, _risk]) { field.dispose(); } super.dispose(); }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    if (_key == null || _sampleCount < 5) { setState(() => _error = 'يلزم إعداد حالي موثّق وخمس عينات على الأقل لنفس السياق.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.controller.propose(key: _key!, proposed: double.parse(_proposed.text), reason: _reason.text.trim(), evidence: _evidence.text.trim(), sampleCount: _sampleCount, expected: _expected.text.trim(), risk: _risk.text.trim());
      if (mounted) {
        if (widget.controller.error != null) { setState(() => _error = widget.controller.error); }
        else { Navigator.pop(context); }
      }
    } catch (error) { if (mounted) { setState(() => _error = '$error'); } }
    if (mounted) { setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: 'اقتراح تعديل قابل للاختبار',
    subtitle: 'لن يُطبّق أو يُعتمد أي شيء هنا. يحفظ التطبيق اقتراحًا مدعومًا بعيناتك لمراجعته أولًا.',
    formKey: _form,
    error: _error,
    saving: _saving,
    onSave: _save,
    saveLabel: 'حفظ الاقتراح للمراجعة',
    children: [
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _key,
        decoration: const InputDecoration(labelText: 'الإعداد الموثّق'),
        items: _settings.keys.map((key) => DropdownMenuItem(value: key, child: Text(settingTitle(key), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (value) => setState(() => _key = value),
        validator: (value) => value == null ? 'سجّل إعداداتك الحالية أولًا' : null,
      ),
      const SizedBox(height: 12),
      DetailRow('القيمة الحالية', reading(_settings[_key])),
      DetailRow('العينات لنفس السياق', '$_sampleCount'),
      const SizedBox(height: 12),
      NumberField(controller: _proposed, label: 'القيمة المقترحة', max: 400, requiredValue: true),
      const SizedBox(height: 14),
      for (final entry in {_reason: 'المشكلة والسبب', _evidence: 'الدليل والنمط المتكرر', _expected: 'التأثير المتوقع', _risk: 'المخاطر أو المقايضة'}.entries) ...[
        TextFormField(controller: entry.key, decoration: InputDecoration(labelText: entry.value), minLines: 2, maxLines: 4, validator: (value) => value == null || value.trim().length < 5 ? 'أضف شرحًا واضحًا' : null),
        const SizedBox(height: 14),
      ],
    ],
  );
}

class ObservationForm extends StatefulWidget {
  const ObservationForm({super.key, required this.controller, required this.kind, required this.title, required this.fields, this.options = const {}, this.booleans = const {}});
  final CoachController controller;
  final String kind;
  final String title;
  final Map<String, String> fields;
  final Map<String, List<String>> options;
  final Map<String, String> booleans;
  @override
  State<ObservationForm> createState() => _ObservationFormState();
}

class _ObservationFormState extends State<ObservationForm> {
  final _form = GlobalKey<FormState>();
  late final _values = {for (final key in widget.fields.keys) key: TextEditingController()};
  final _notes = TextEditingController();
  final _choices = <String, String>{};
  final _booleans = <String, bool>{};
  bool _confirmed = false;
  bool _saving = false;
  String? _error;
  @override
  void dispose() { for (final field in _values.values) { field.dispose(); } _notes.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    if (!_confirmed) { setState(() => _error = 'أكد أن هذه ملاحظات جلسة غير مصنفة فعلية.'); return; }
    if (widget.options.keys.any((key) => !_choices.containsKey(key)) || widget.booleans.keys.any((key) => !_booleans.containsKey(key))) { setState(() => _error = 'أجب عن نتائج التجربة أولًا.'); return; }
    final data = <String, dynamic>{'source': 'MANUAL_UNRANKED_TEST', 'notes': _notes.text.trim(), ..._choices, ..._booleans};
    for (final entry in _values.entries) { final value = double.tryParse(entry.value.text); if (value != null) { data[entry.key] = value; } }
    if (widget.kind == 'throwables' && data['trajectoryVisible'] == true && data['gameDisplaysTrajectory'] != true) { setState(() => _error = 'لا يمكن أن يكون المسار واضحًا إذا كانت اللعبة لا تعرضه.'); return; }
    if (widget.kind == 'hit') {
      const countKeys = ['observedHits', 'aimMisses', 'recoilMisses', 'targetMovementMisses'];
      final shots = data['observedShots'] as double?;
      if (countKeys.any((key) => data.containsKey(key)) && shots == null) { setState(() => _error = 'أدخل عدد الطلقات الكلي عند تصنيف الإصابات والأخطاء.'); return; }
      final sum = countKeys.fold<double>(0, (total, key) => total + ((data[key] as double?) ?? 0));
      if (shots != null && (shots <= 0 || sum > shots)) { setState(() => _error = 'يجب أن تكون الطلقات موجبة وألا يتجاوز مجموع النتائج عددها.'); return; }
    }
    if (data.length <= 2 && _notes.text.trim().isEmpty) { setState(() => _error = 'أدخل قياسًا أو ملاحظة فعلية.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.controller.addObservation(widget.kind, data);
      if (mounted) {
        if (widget.controller.error != null) { setState(() => _error = widget.controller.error); }
        else { Navigator.pop(context); }
      }
    } catch (error) { if (mounted) { setState(() => _error = '$error'); } }
    if (mounted) { setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: widget.title,
    subtitle: 'سجل ما لاحظته في اختبار مسموح. الملاحظات اليدوية لا تثبت سببًا تقنيًا بمفردها.',
    formKey: _form,
    error: _error,
    saving: _saving,
    onSave: _save,
    saveLabel: 'حفظ الملاحظة',
    children: [
      for (final entry in widget.options.entries) ...[
        DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: entry.key == 'obstacle' ? 'موضع الرمي' : entry.key == 'cause' ? 'السبب الملحوظ أو غير المحسوم' : entry.key == 'action' ? 'اختبار الحركة' : entry.key),
          items: entry.value.map((value) => DropdownMenuItem(value: value, child: Text(optionLabel(value)))).toList(),
          onChanged: (value) { if (value != null) { _choices[entry.key] = value; } },
        ),
        const SizedBox(height: 14),
      ],
      for (final entry in _values.entries) ...[
        NumberField(controller: entry.value, label: widget.fields[entry.key]!, integer: ['observedShots', 'observedHits', 'aimMisses', 'recoilMisses', 'targetMovementMisses', 'thermalSeverity'].contains(entry.key), min: entry.key == 'viewAngleDegrees' ? -90 : 0, max: entry.key == 'turnErrorDegrees' ? 180 : entry.key == 'viewAngleDegrees' ? 90 : entry.key.endsWith('Ms') || entry.key.startsWith('observed') || entry.key.endsWith('Misses') ? 60000 : entry.key.contains('thermal') ? 6 : 100),
        const SizedBox(height: 14),
      ],
      for (final entry in widget.booleans.entries) ...[
        DropdownButtonFormField<bool>(
          decoration: InputDecoration(labelText: entry.value),
          items: const [DropdownMenuItem(value: true, child: Text('نعم')), DropdownMenuItem(value: false, child: Text('لا'))],
          onChanged: (value) { if (value != null) { _booleans[entry.key] = value; } },
          validator: (value) => value == null ? 'حدد النتيجة التي لاحظتها' : null,
        ),
        const SizedBox(height: 14),
      ],
      TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'تفاصيل التجربة ومصدر القياس'), minLines: 3, maxLines: 6),
      const SizedBox(height: 14),
      CheckboxListTile(contentPadding: EdgeInsets.zero, value: _confirmed, onChanged: (value) => setState(() => _confirmed = value ?? false), title: const Text('هذه نتائج فعلية من جلسة غير مصنفة.')),
    ],
  );
}

class FormSheet extends StatelessWidget {
  const FormSheet({super.key, required this.title, required this.subtitle, required this.formKey, required this.children, required this.onSave, required this.saveLabel, required this.saving, this.error});
  final String title;
  final String subtitle;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final VoidCallback onSave;
  final String saveLabel;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), IconButton(tooltip: 'إغلاق', onPressed: saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close))]),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: spiderMuted, height: 1.8)),
          const SizedBox(height: 24),
          ...children,
          if (error != null) ...[const SizedBox(height: 14), NoticePanel(text: error!, warning: true)],
          const SizedBox(height: 22),
          FilledButton(onPressed: saving ? null : onSave, child: saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(saveLabel)),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}
