import '../game_mode_guard/game_mode_guard.dart';

enum HitCause {
  inconclusive, aimMiss, recoilMiss, targetMovement, networkLatency,
  jitter, packetLoss, fpsDrops, thermalThrottling, desyncIndicator,
  visualFeedbackMismatch,
}

/// A supplied observation must identify provenance; user reports are not
/// promoted to measured packet loss, authoritative damage or server telemetry.
class HitEvidence {
  HitEvidence({this.source = 'MANUAL_OBSERVATION', this.reliableMeasurements = false,
    this.observedShots, this.observedHits, this.aimMisses, this.recoilMisses,
    this.targetMovementMisses, this.latencyMs, this.jitterMs,
    this.packetLossPercent, this.fpsDropPercent, this.thermalSeverity,
    this.visualHitFeedback, this.observedDamageResult,
    this.timestampedClientServerDisagreement = false}) {
    if (source.trim().isEmpty) {
      throw ArgumentError('Evidence provenance is required.');
    }
    for (final value in [latencyMs, jitterMs, packetLossPercent, fpsDropPercent]) {
      if (value != null && (!value.isFinite || value < 0)) {
        throw ArgumentError('Measurements must be finite and nonnegative.');
      }
    }
    if ((packetLossPercent ?? 0) > 100 || (fpsDropPercent ?? 0) > 100 ||
        (thermalSeverity != null && (thermalSeverity! < 0 || thermalSeverity! > 6))) {
      throw ArgumentError('Measurement outside its physical range.');
    }
    if ((observedHits != null || aimMisses != null || recoilMisses != null ||
        targetMovementMisses != null) && observedShots == null) {
      throw ArgumentError('Shot evidence requires the total observed shots.');
    }
    if (observedShots != null) {
      if (observedShots! <= 0) {
        throw ArgumentError('Shot count must be positive.');
      }
      for (final count in [observedHits, aimMisses, recoilMisses, targetMovementMisses]) {
        if (count != null && (count < 0 || count > observedShots!)) {
          throw ArgumentError('Shot classification exceeds observed shots.');
        }
      }
      if ((observedHits ?? 0) + (aimMisses ?? 0) + (recoilMisses ?? 0) +
          (targetMovementMisses ?? 0) > observedShots!) {
        throw ArgumentError('Each shot can have at most one observed outcome.');
      }
    }
  }
  final String source;
  final bool reliableMeasurements;
  final int? observedShots, observedHits, aimMisses, recoilMisses, targetMovementMisses;
  final double? latencyMs, jitterMs, packetLossPercent, fpsDropPercent;
  final int? thermalSeverity;
  final bool? visualHitFeedback, observedDamageResult;
  final bool timestampedClientServerDisagreement;
}

class HitDiagnosis {
  HitDiagnosis({required this.cause, required List<HitCause> indicators,
    required List<String> evidence, required this.source,
    required this.reliableMeasurements})
      : indicators = List.unmodifiable(indicators), evidence = List.unmodifiable(evidence);
  final HitCause cause;
  final List<HitCause> indicators;
  final List<String> evidence;
  final String source;
  final bool reliableMeasurements;
  bool get hasPerformanceConfounder => indicators.any((cause) => const [
    HitCause.networkLatency, HitCause.jitter, HitCause.packetLoss,
    HitCause.fpsDrops, HitCause.thermalThrottling, HitCause.desyncIndicator,
  ].contains(cause));
}

class HitRegistrationDiagnostics {
  HitRegistrationDiagnostics(this.guard);
  final GameModeGuard guard;

  HitDiagnosis diagnose(HitEvidence data) {
    guard.requireAllowed();
    final indicators = <HitCause>[];
    final evidence = <String>[];
    void add(HitCause cause, String reason) {
      indicators.add(cause);
      evidence.add(reason);
    }
    if (data.observedShots != null && data.observedShots! >= 5) {
      final shots = data.observedShots!;
      if ((data.aimMisses ?? 0) / shots >= .3) {
        add(HitCause.aimMiss, '${data.aimMisses}/$shots طلقات خارج الهدف قبل الارتداد.');
      }
      if ((data.recoilMisses ?? 0) / shots >= .3) {
        add(HitCause.recoilMiss, '${data.recoilMisses}/$shots طلقات فُقدت مع الارتداد.');
      }
      if ((data.targetMovementMisses ?? 0) / shots >= .3) {
        add(HitCause.targetMovement, '${data.targetMovementMisses}/$shots طلقات متزامنة مع خروج الهدف.');
      }
    }
    if (data.latencyMs != null && data.latencyMs! > 100) {
      add(HitCause.networkLatency, 'Ping مرتفع في المصدر المتاح: ${data.latencyMs} ms؛ مؤشر ارتباط لا إثبات سببي.');
    }
    if (data.jitterMs != null && data.jitterMs! > 20) {
      add(HitCause.jitter, 'تذبذب الشبكة المبلغ عنه ${data.jitterMs} ms.');
    }
    if (data.packetLossPercent != null && data.packetLossPercent! > 1) {
      add(HitCause.packetLoss, 'فقد حزم في المصدر المحدد: ${data.packetLossPercent}%.');
    }
    if (data.fpsDropPercent != null && data.fpsDropPercent! > 10) {
      add(HitCause.fpsDrops, 'تراجع FPS الملاحظ ${data.fpsDropPercent}%.');
    }
    if (data.thermalSeverity != null && data.thermalSeverity! >= 3) {
      add(HitCause.thermalThrottling, 'حالة حرارية مرتفعة؛ قد تتزامن مع خفض أداء الجهاز ولا تثبت السبب وحدها.');
    }
    if (data.visualHitFeedback == true && data.observedDamageResult == false) {
      add(HitCause.visualFeedbackMismatch, 'اختلفت إشارة الإصابة المرئية عن النتيجة المرصودة؛ السبب غير محسوم.');
    }
    if (data.timestampedClientServerDisagreement) {
      add(HitCause.desyncIndicator, 'ورد اختلاف مؤقت موثق في المصدر؛ لا تتوفر قراءة سيرفر PUBG داخل التطبيق.');
    }
    if (!data.reliableMeasurements) {
      evidence.add('المصدر: تقرير المستخدم؛ المؤشرات غير متحققة آليًا.');
    }
    if (indicators.isEmpty) {
      evidence.add('الأدلة المتاحة لا تكفي لتحديد سبب فقد الإصابة.');
    }
    // Network, heat and feedback remain correlates, not proofs of the cause.
    final directlyObserved = indicators.where((cause) => const [
      HitCause.aimMiss, HitCause.recoilMiss, HitCause.targetMovement,
    ].contains(cause)).toList();
    final cause = data.reliableMeasurements && indicators.length == 1 &&
      directlyObserved.length == 1 ? directlyObserved.single : HitCause.inconclusive;
    return HitDiagnosis(cause: cause, indicators: indicators, evidence: evidence,
      source: data.source, reliableMeasurements: data.reliableMeasurements);
  }
}
