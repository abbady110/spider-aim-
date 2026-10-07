import 'package:flutter/material.dart';

import '../battery/battery_thermal_intelligence.dart';
import '../core/coach_controller.dart';
import 'components.dart';
import 'theme.dart';

ThermalLevel thermalLevel(String value) => switch (value.toLowerCase()) {
  'none' || 'nominal' || 'normal' || '0' => ThermalLevel.nominal,
  'light' || 'moderate' || 'fair' || '1' || '2' => ThermalLevel.fair,
  'severe' || 'serious' || '3' => ThermalLevel.serious,
  'critical' || 'emergency' || 'shutdown' || '4' || '5' || '6' => ThermalLevel.critical,
  _ => ThermalLevel.unknown,
};

class BatteryPage extends StatefulWidget {
  const BatteryPage({super.key, required this.controller});
  final CoachController controller;

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  CoachController get controller => widget.controller;
  bool _recording = false;

  Future<void> _reading(BuildContext context, String phase, String sessionId) async {
    if (_recording) {
      return;
    }
    setState(() => _recording = true);
    try {
      await controller.refreshDevice();
      final device = controller.device!;
      await controller.addObservation('battery', {
        'phase': phase, 'sessionId': sessionId,
        'batteryPercent': device.batteryPercent, 'charging': device.charging,
        'thermal': device.thermal, 'spiderCpuTimeMs': device.details['appCpuTimeMs'],
        'spiderPssKb': device.details['appPssKb'], 'source': 'OFFICIAL_OS_API',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(phase == 'start' ? 'حُفظت بداية الجلسة من النظام.' : 'حُفظت نهاية الجلسة وأُعد التقرير.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _recording = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = controller.device;
    final rows = jsonList(controller.state['observations']).where((row) => row['kind'] == 'battery').toList();
    final starts = rows.where((row) => jsonMap(row['data'])['phase'] == 'start').toList();
    final lastStart = starts.isEmpty ? null : starts.last;
    final sessionId = lastStart == null ? null : jsonMap(lastStart['data'])['sessionId'] as String?;
    final session = rows.where((row) => sessionId != null && jsonMap(row['data'])['sessionId'] == sessionId).toList();
    final completed = session.any((row) => jsonMap(row['data'])['phase'] == 'end');
    final active = sessionId != null && !completed;
    BatterySessionReport? report;
    if (completed && session.length >= 2) {
      final readings = session.map((row) {
        final data = jsonMap(row['data']);
        return BatteryReading(
          at: DateTime.parse('${row['timestamp']}'),
          levelPercent: (data['batteryPercent'] as num?)?.toDouble(),
          charging: data['charging'] as bool?,
          thermal: thermalLevel('${data['thermal']}'),
          spiderCpuTimeMs: (data['spiderCpuTimeMs'] as num?)?.toDouble(),
          spiderWorkingSetBytes: data['spiderPssKb'] is num ? (data['spiderPssKb'] as num).toInt() * 1024 : null,
        );
      }).toList();
      if (readings.last.at.isAfter(readings.first.at)) {
        report = const BatteryThermalIntelligence().report(readings);
      }
    }
    final plan = const BatteryThermalIntelligence().plan(safeOfflineSession: controller.guard.allowed, thermal: thermalLevel(device?.thermal ?? 'UNKNOWN'), batteryPercent: device?.batteryPercent);
    final allowed = controller.guard.allowed && !controller.busy && !_recording;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeading(title: 'البطارية والحرارة', subtitle: 'مراقبة بيانات النظام المتاحة وتقليل حمل SPIDER AIM قبل المساس بتجربة اللعب.'),
      ResponsiveCards(children: [
        MetricCard(label: 'البطارية الحالية', value: reading(device?.batteryPercent?.toStringAsFixed(0), '%'), icon: Icons.battery_charging_full),
        MetricCard(label: 'الحالة الحرارية', value: device?.thermal ?? 'UNKNOWN', icon: Icons.thermostat_outlined),
        MetricCard(label: 'حالة الشحن', value: device?.charging == null ? 'غير متاحة' : device!.charging! ? 'قيد الشحن' : 'غير متصل', icon: Icons.power_outlined),
      ]),
      const SizedBox(height: 20),
      NoticePanel(text: '${plan.reason}\nالتحليل المباشر غير نشط. لا يُعدّل التطبيق FPS أو الرسوميات أو معدل التحديث أو استجابة اللمس.'),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: allowed && !active ? () => _reading(context, 'start', DateTime.now().microsecondsSinceEpoch.toString()) : null, icon: const Icon(Icons.play_arrow), label: const Text('بدء قياس جلسة البطارية')),
        OutlinedButton.icon(onPressed: allowed && !completed && sessionId != null ? () => _reading(context, 'end', sessionId) : null, icon: const Icon(Icons.stop_circle_outlined), label: const Text('إنهاء الجلسة وعرض التقرير')),
      ]),
      const SizedBox(height: 20),
      if (active) NoticePanel(text: 'بدأ القياس ${dateLabel(lastStart?['timestamp'])}. لا يوجد تسجيل فيديو. أعد التصريح بنوع الجلسة عند الرجوع من اللعبة، ثم أنهِ القياس. معدل التفريغ يتطلب 5 دقائق على الأقل دون شحن.'),
      if (!controller.guard.allowed) const NoticePanel(warning: true, text: 'الجلسة غير معروفة أو مصنفة. حدّد جلسة غير مصنفة في صفحة الأمان لتسجيل تقرير.'),
      if (report == null && !active) const EmptyPanel(title: 'تقرير من قراءتين فعليتين', message: 'ابدأ جلسة ثم أنهها لحساب المدة وتغير مستوى البطارية. لا يمكن نسبة استهلاك الجهاز إلى PUBG من قراءات البطارية وحدها.', icon: Icons.battery_saver_outlined),
      if (report != null) ...[
        SpiderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('تقرير الجلسة الأخيرة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          DetailRow('مدة الجلسة', '${report.duration.inMinutes} دقيقة'),
          DetailRow('البطارية عند البداية', reading(report.startPercent, '%')),
          DetailRow('البطارية عند النهاية', reading(report.endPercent, '%')),
          DetailRow('تفريغ الجهاز في الساعة', reading(report.drainPerHour?.toStringAsFixed(2), '%')),
          DetailRow('أعلى حالة حرارية مرصودة', report.worstThermal.name),
          DetailRow('حمل SPIDER AIM على نواة CPU', reading(report.spiderCpuCorePercent?.toStringAsFixed(2), '%')),
          const DetailRow('طاقة بطارية SPIDER AIM وحده', 'UNKNOWN'),
          const DetailRow('استهلاك PUBG المباشر', 'UNKNOWN'),
          const DetailRow('ثبات FPS اللعبة', 'UNKNOWN'),
        ])),
        const SizedBox(height: 16),
        for (final text in report.recommendations) Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticePanel(text: text)),
      ],
      const SizedBox(height: 20),
      const Text('CPU time مقياس عمل المعالج، وليس قياسًا لطاقة البطارية. القراءات هنا مأخوذة عند بداية الجلسة ونهايتها؛ الأحداث الحرارية بين القراءتين قد لا تُرصد.', style: TextStyle(color: spiderMuted, height: 1.8)),
    ]);
  }
}
