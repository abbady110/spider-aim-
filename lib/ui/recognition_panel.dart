import 'package:flutter/material.dart';

import '../core/coach_controller.dart';
import '../game_mode_guard/game_mode_guard.dart';
import '../game_mode_recognition/automatic_mode_recognizer.dart';
import 'components.dart';
import 'theme.dart';

String modeLabel(GameMode mode) => switch (mode) {
  GameMode.trainingSafe => 'Training • تعرّف تلقائي',
  GameMode.warehouseSafe => 'Warehouse • تعرّف تلقائي',
  GameMode.arenaSafe => 'Arena • تعرّف تلقائي',
  GameMode.safeUnranked => 'Unranked • تعرّف تلقائي',
  GameMode.competitiveBlocked => 'Competitive / Battle Royale • مقفول',
  GameMode.unknownBlocked => 'الوضع غير معروف • مقفول',
};

String historyModeLabel(GameMode mode) => switch (mode) {
  GameMode.trainingSafe => 'سجل Training',
  GameMode.warehouseSafe => 'سجل Warehouse',
  GameMode.arenaSafe => 'سجل Arena',
  GameMode.safeUnranked => 'سجل Unranked',
  GameMode.competitiveBlocked => 'سجل Competitive',
  GameMode.unknownBlocked => 'سجل الوضع غير المعروف',
};

/// Displays the actual automatic decision. No control in this widget assigns a
/// safe mode, bypasses screen consent, or changes the classifier's confidence.
class RecognitionPanel extends StatefulWidget {
  const RecognitionPanel({super.key, required this.controller, this.showControls = false});
  final CoachController controller;
  final bool showControls;

  @override
  State<RecognitionPanel> createState() => _RecognitionPanelState();
}

class _RecognitionPanelState extends State<RecognitionPanel> {
  bool _requestPending = false;

  Future<void> _perform(Future<void> Function() action) async {
    if (_requestPending) {
      return;
    }
    setState(() => _requestPending = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _requestPending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final decision = controller.recognition;
    final capabilities = controller.captureCapabilities;
    final android = controller.device?.details['platform'] == 'android';
    final supported = android && capabilities['supported'] == true;
    final usageGranted = capabilities['usageAccessGranted'] == true;
    final pending = _requestPending || controller.busy;
    return SpiderCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(decision.allowed ? Icons.verified_user_outlined : Icons.lock_outline,
            color: decision.allowed ? spiderTeal : Colors.amber),
          const SizedBox(width: 12),
          const Expanded(child: Text('التعرف التلقائي على وضع اللعب',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 18),
        StatusPill(text: modeLabel(decision.mode), good: decision.allowed),
        const SizedBox(height: 10),
        const Text('الحالة المكتشفة', style: TextStyle(color: spiderMuted)),
        const SizedBox(height: 6),
        Text(decision.mode.code, key: const Key('recognition-mode-code'),
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Text('درجة ثقة استدلالية', style: TextStyle(color: spiderMuted))),
          Text('${(decision.confidence * 100).toStringAsFixed(0)}%',
            key: const Key('recognition-confidence'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        const Text('هذه درجة أدلة المحرك، وليست نسبة دقة مثبتة أو ضمانًا لصحة الاكتشاف.',
          style: TextStyle(color: spiderMuted, fontSize: 12, height: 1.7)),
        DetailRow('آخر تحقق', decision.lastVerified == null
            ? 'لم يحدث تحقق بعد' : dateLabel(decision.lastVerified)),
        DetailRow('صلاحية الدليل الآمن', '${AutomaticModeRecognizer.verificationTtl.inSeconds} ثانية؛ ثم يُقفل تلقائيًا'),
        Row(children: [
          const Expanded(child: Text('الإطارات الداعمة', style: TextStyle(color: spiderMuted))),
          Text('${decision.frameCount}', key: const Key('recognition-frame-count')),
        ]),
        DetailRow('التقاط الشاشة', controller.captureRunning ? 'نشط بموافقة النظام' : 'متوقف'),
        DetailRow('السماح بالمعايرة', decision.allowed ? 'سماح آلي مؤقت من الأدلة الحالية' : 'مقفول'),
        if (decision.sessionId != null) DetailRow('جلسة الالتقاط', decision.sessionId!),
        const Divider(height: 24),
        const Text('الدليل الحالي', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (decision.evidence.isEmpty)
          const Text('لا توجد إطارات شاشة موثوقة كافية. يبقى UNKNOWN_BLOCKED.',
            style: TextStyle(color: spiderMuted, height: 1.7)),
        for (final evidence in decision.evidence)
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text(evidence, style: const TextStyle(height: 1.7))),
        if (controller.competitiveLatched) ...[
          const SizedBox(height: 8),
          const Text('قفل Battle Royale / Ranked محفوظ لهذه الجلسة',
            key: Key('recognition-br-latch'),
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        ],
        if (decision.mode == GameMode.competitiveBlocked) ...[
          const SizedBox(height: 8),
          const NoticePanel(warning: true, icon: Icons.lock,
            text: 'قفل تنافسي نشط: لا معايرة أو تحليل لعب أو تجربة إعدادات.'),
        ],
        if (widget.showControls) ...[
          const SizedBox(height: 18),
          const NoticePanel(text: 'Android: يحتاج التعرف إذن معرفة التطبيق الأمامي ثم موافقة التقاط الشاشة الرسمية. تُحلّل عينات شاشة PUBG محليًا؛ لا تُحفظ صور أو فيديو ولا تُرسل إلى خادم.'),
          const SizedBox(height: 14),
          DetailRow('إذن معرفة التطبيق الأمامي', !supported
              ? 'غير متاح على هذا الجهاز' : usageGranted ? 'ممنوح حسب النظام' : 'لم يُمنح بعد'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              key: const Key('recognition-request-usage'),
              onPressed: supported && !pending && !controller.captureRunning
                  ? () => _perform(controller.requestUsageAccess) : null,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('إذن معرفة التطبيق الأمامي'),
            ),
            FilledButton.icon(
              key: const Key('recognition-start'),
              onPressed: supported && usageGranted && !pending && !controller.captureRunning
                  ? () => _perform(controller.startAutomaticRecognition) : null,
              icon: const Icon(Icons.screen_search_desktop_outlined),
              label: const Text('بدء التعرف التلقائي'),
            ),
            OutlinedButton.icon(
              key: const Key('recognition-stop'),
              onPressed: controller.captureRunning && !pending
                  ? () => _perform(controller.stopAutomaticRecognition) : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('إيقاف التقاط الشاشة'),
            ),
          ]),
          if (_requestPending) const Padding(
            padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
          const SizedBox(height: 16),
          if (!android)
            const NoticePanel(warning: true,
              text: 'التعرف التلقائي عبر الشاشة غير متاح في إصدار iPhone / iPad الحالي. يبقى القفل مغلقًا، ويمكن عرض السجلات السابقة فقط.')
          else if (!supported)
            const NoticePanel(warning: true,
              text: 'التقاط الشاشة غير متاح أو لم يكتمل فحصه. لن تفتح المعايرة قبل توفر دعم النظام والأذونات والأدلة.')
          else
            const NoticePanel(text: 'التعرف النصي الحالي يدعم عناصر HUD بالأحرف اللاتينية. الواجهات المترجمة أو غير المدعومة قد تبقى UNKNOWN. مغادرة PUBG أو تقادم الدليل يعيد القفل؛ اختيار سجل يدوي لا يغيّر ذلك.'),
        ],
      ],
    ));
  }
}
