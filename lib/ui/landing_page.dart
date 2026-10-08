import 'package:flutter/material.dart';

import '../core/coach_controller.dart';
import '../landing/landing_assistant.dart';
import 'components.dart';
import 'forms.dart';
import 'theme.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key, required this.controller});
  final CoachController controller;
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  static const _labels = {
    'aircraftEast': 'إحداثي الطائرة شرقًا (m)', 'aircraftNorth': 'إحداثي الطائرة شمالًا (m)',
    'targetEast': 'إحداثي الهدف شرقًا (m)', 'targetNorth': 'إحداثي الهدف شمالًا (m)',
    'heading': 'اتجاه الطائرة (0–359°)', 'aircraftSpeed': 'سرعة الطائرة المقاسة (m/s)',
    'glideSpeed': 'سرعة الانزلاق الأفقية المقاسة (m/s)', 'descentSpeed': 'سرعة الهبوط العمودية المقاسة (m/s)',
    'altitude': 'الارتفاع الابتدائي المقاس (m)', 'diveAltitude': 'ارتفاع بدء Fast Dive المقاس (m)',
    'diveHorizontal': 'سرعة الغوص الأفقية المقاسة (m/s)', 'diveDescent': 'سرعة الغوص العمودية المقاسة (m/s)',
  };
  final _form = GlobalKey<FormState>();
  final _fields = {for (final key in _labels.keys) key: TextEditingController()};
  LandingPlan? _plan;
  String? _error;
  bool _saving = false;
  @override
  void dispose() { for (final value in _fields.values) { value.dispose(); } super.dispose(); }

  Future<void> _calculate() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      double value(String key) => double.parse(_fields[key]!.text);
      final input = LandingInput(
        aircraft: MapPosition(value('aircraftEast'), value('aircraftNorth')),
        target: MapPosition(value('targetEast'), value('targetNorth')),
        aircraftHeadingDegrees: value('heading'), aircraftSpeedMetersPerSecond: value('aircraftSpeed'),
        measuredGlideMetersPerSecond: value('glideSpeed'), measuredDescentMetersPerSecond: value('descentSpeed'),
        altitudeMeters: value('altitude'), fastDiveStartAltitudeMeters: value('diveAltitude'),
        measuredDiveHorizontalMetersPerSecond: value('diveHorizontal'), measuredDiveDescentMetersPerSecond: value('diveDescent'),
      );
      final plan = LandingAssistant(widget.controller.guard).plan(input);
      await widget.controller.addObservation('landing', {'source': 'MANUAL_OFFLINE_GEOMETRY', 'inputs': {for (final key in _fields.keys) key: value(key)}, 'distanceMeters': plan.currentDistanceMeters, 'headingDegrees': plan.headingDegrees, 'estimatedJumpInSeconds': plan.estimatedJumpInSeconds, 'reachable': plan.reachable});
      if (mounted) {
        setState(() => _plan = plan);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    }
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.controller.guard.allowed && !widget.controller.busy && !_saving;
    final plan = _plan;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeading(title: 'مساعد الهبوط', subtitle: 'تقدير هندسي للتدريب من قياساتك. تعليمات حسابية فقط، دون تحكم بالمظلة أو الحركة.'),
      const NoticePanel(text: 'لا توجد قراءة مباشرة للخريطة أو فيزياء موثقة من PUBG. أدخل إحداثيات ومسافات وسرعات قستها في جلسة غير مصنفة. النتيجة تقدير للمراجعة، وليست إشارة JUMP NOW أثناء اللعب.'),
      const SizedBox(height: 20),
      if (!widget.controller.guard.allowed) const NoticePanel(warning: true, icon: Icons.lock_outline, text: 'الحساب مقفول: يلزم تعرف تلقائي حديث على وضع مسموح. اختيار Training أو Warehouse يدويًا من السجل لا يفتح المساعد.'),
      const SizedBox(height: 20),
      SpiderCard(child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final entry in _fields.entries) ...[
          NumberField(controller: entry.value, label: _labels[entry.key]!, requiredValue: true, min: entry.key.endsWith('East') || entry.key.endsWith('North') ? -100000 : 0, max: entry.key == 'heading' ? 359.999 : 100000),
          const SizedBox(height: 14),
        ],
        if (_error != null) ...[NoticePanel(text: _error!, warning: true), const SizedBox(height: 14)],
        FilledButton.icon(onPressed: allowed ? _calculate : null, icon: const Icon(Icons.calculate_outlined), label: const Text('حساب وحفظ تقدير التدريب')),
      ]))),
      if (plan != null && widget.controller.guard.allowed) ...[
        const SizedBox(height: 20),
        SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('تقدير من المدخلات', style: TextStyle(color: spiderTeal, fontSize: 20, fontWeight: FontWeight.bold)),
          DetailRow('المسافة الحالية', '${plan.currentDistanceMeters.toStringAsFixed(0)} m'),
          DetailRow('الاتجاه', '${plan.headingDegrees.toStringAsFixed(1)}°'),
          DetailRow('وقت قفز مقدّر من نقطة القياس', reading(plan.estimatedJumpInSeconds?.toStringAsFixed(1), ' s')),
          DetailRow('زاوية الانزلاق المقدّرة', '${plan.estimatedGlideAngleDegrees.toStringAsFixed(1)}°'),
          DetailRow('Fast Dive بعد القفز', '${plan.fastDiveAfterSeconds.toStringAsFixed(1)} s'),
          DetailRow('ارتفاع بدء Fast Dive', '${plan.fastDiveStartAltitudeMeters.toStringAsFixed(0)} m'),
          DetailRow('المدى المحسوب', '${plan.estimatedReachMeters.toStringAsFixed(0)} m'),
          DetailRow('الوصول ضمن نموذج السرعة الثابتة', plan.reachable ? 'ممكن وفق المدخلات' : 'لم يتحقق ضمن المدخلات'),
          const SizedBox(height: 12),
          Text(plan.explanation, style: const TextStyle(color: spiderMuted, height: 1.8)),
        ])),
      ],
    ]);
  }
}
