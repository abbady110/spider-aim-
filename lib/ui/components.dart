import 'package:flutter/material.dart';

import 'theme.dart';

class SpiderCard extends StatelessWidget {
  const SpiderCard({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF253540)),
    ),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: spiderMuted, height: 1.7)),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, this.good = false});
  final String text;
  final bool good;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: (good ? spiderTeal : Colors.amber).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(40),
      border: Border.all(color: (good ? spiderTeal : Colors.amber).withValues(alpha: 0.25)),
    ),
    child: Text(text, style: TextStyle(color: good ? spiderTeal : Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, required this.icon, this.caption});
  final String label;
  final String value;
  final IconData icon;
  final String? caption;

  @override
  Widget build(BuildContext context) => SpiderCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: spiderTeal, size: 22),
        const SizedBox(height: 18),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: spiderMuted)),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(caption!, style: const TextStyle(color: spiderMuted, fontSize: 11, height: 1.5)),
        ],
      ],
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.title, required this.message, this.icon = Icons.query_stats_rounded, this.action});
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SpiderCard(
    child: SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const SizedBox(height: 14),
          Icon(icon, size: 42, color: spiderMuted),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: spiderMuted, height: 1.8)),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
          const SizedBox(height: 14),
        ],
      ),
    ),
  );
}

class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.text, this.icon = Icons.info_outline, this.warning = false});
  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: (warning ? Colors.amber : spiderTeal).withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: (warning ? Colors.amber : spiderTeal).withValues(alpha: 0.18)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: warning ? Colors.amber : spiderTeal, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.7))),
      ],
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: spiderMuted))),
        const SizedBox(width: 16),
        Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5))),
      ],
    ),
  );
}

class ResponsiveCards extends StatelessWidget {
  const ResponsiveCards({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 850 ? 4 : constraints.maxWidth >= 480 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
      return Wrap(spacing: 14, runSpacing: 14, children: children.map((child) => SizedBox(width: width, child: child)).toList());
    },
  );
}

Map<String, dynamic> jsonMap(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> jsonList(dynamic value) => value is List ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
String reading(dynamic value, [String suffix = '']) => value == null ? 'غير متاح' : '$value$suffix';
String dateLabel(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) {
    return 'وقت غير متاح';
  }
  return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String statusLabel(dynamic status) => switch ('$status') {
  'PROPOSED' => 'اقتراح ينتظر قرارك',
  'APPROVED_FOR_TEST' => 'موافقة على التجربة',
  'BACKED_UP' => 'تم حفظ النسخة الاحتياطية',
  'TESTING' => 'قيد الاختبار',
  'PASSED' => 'اجتاز المقارنة • ينتظر اعتمادك',
  'FAILED' => 'لم يجتز المقارنة',
  'APPROVED_FINAL' => 'معتمد نهائيًا',
  'REJECTED' => 'مرفوض',
  'ROLLED_BACK' => 'تم الاسترجاع',
  'DEFERRED' => 'مؤجل',
  _ => '$status',
};
