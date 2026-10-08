import 'dart:convert';
import 'dart:math' as math;

import '../game_mode_guard/game_mode_guard.dart';

/// An exact calibration context. Attachments are compared as an unordered set.
class WeaponContext {
  WeaponContext({
    required this.weapon,
    required this.scope,
    required this.distanceMeters,
    List<String> attachments = const [],
  }) : attachments = List.unmodifiable(attachments.toSet().toList()..sort()) {
    if (weapon.trim().isEmpty || scope.trim().isEmpty ||
        !distanceMeters.isFinite || distanceMeters <= 0 ||
        attachments.any((value) => value.trim().isEmpty)) {
      throw ArgumentError('A complete weapon, scope and positive distance are required.');
    }
  }

  static const weapons = ['M416', 'AUG', 'SCAR-L', 'AKM', 'ACE32', 'UMP45', 'DP-28'];
  static const scopes = ['Iron Sight', 'Red Dot', 'Holo', '2x', '3x', '4x', '6x', '8x'];
  final String weapon;
  final String scope;
  final List<String> attachments;
  final double distanceMeters;

  String get key => jsonEncode([weapon, scope, attachments, distanceMeters]);
  @override
  bool operator ==(Object other) => other is WeaponContext && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

/// Measurements are observations, never guessed values. Null means UNKNOWN.
/// Scores/rates use 0–100; displacement uses the observer's normalized units.
class AimSample {
  AimSample({
    required this.context,
    required this.id,
    required this.recordedAt,
    this.source = 'MANUAL_OBSERVATION',
    this.aimStability,
    this.trackingStability,
    this.verticalRecoil,
    this.horizontalDrift,
    this.shotGrouping,
    this.firstShotStability,
    this.overshootRate,
    this.undershootRate,
    this.acquisitionMs,
    this.adsStabilizationMs,
    this.movementRetention,
    this.fingerDragConsistency,
    this.sprayConsistency,
    this.hits,
    this.shots,
    this.fpsStability,
    this.thermalSeverity,
    this.batteryDrainPerHour,
    this.latencyMs,
    this.jitterMs,
    this.packetLossPercent,
    this.networkMetricsReliable = false,
    this.frameMetricsReliable = false,
  }) {
    if (id.trim().isEmpty || source.trim().isEmpty) {
      throw ArgumentError('An observation ID and provenance are required.');
    }
    for (final value in [aimStability, trackingStability, firstShotStability,
      overshootRate, undershootRate, movementRetention, fingerDragConsistency,
      sprayConsistency, fpsStability, packetLossPercent]) {
      _range(value, 0, 100);
    }
    for (final value in [verticalRecoil, horizontalDrift, shotGrouping,
      acquisitionMs, adsStabilizationMs, batteryDrainPerHour, latencyMs, jitterMs]) {
      _range(value, 0, double.infinity);
    }
    _range(thermalSeverity?.toDouble(), 0, 6);
    if ((hits == null) != (shots == null) ||
        (shots != null && (shots! <= 0 || hits! < 0 || hits! > shots!))) {
      throw ArgumentError('Hits and positive shot count must be supplied together.');
    }
    if (overshootRate != null && undershootRate != null &&
        overshootRate! + undershootRate! > 100) {
      throw ArgumentError('Overshoot and undershoot cannot exceed all attempts.');
    }
  }

  final WeaponContext context;
  final String id;
  final DateTime recordedAt;
  final String source;
  final double? aimStability, trackingStability, verticalRecoil, horizontalDrift;
  final double? shotGrouping, firstShotStability, overshootRate, undershootRate;
  final double? acquisitionMs, adsStabilizationMs, movementRetention;
  final double? fingerDragConsistency, sprayConsistency, fpsStability;
  final double? batteryDrainPerHour, latencyMs, jitterMs, packetLossPercent;
  final int? hits, shots, thermalSeverity;
  final bool networkMetricsReliable, frameMetricsReliable;

  Map<String, Object?> toJson() => {
    'id': id, 'recordedAt': recordedAt.toUtc().toIso8601String(), 'source': source,
    'context': {'weapon': context.weapon, 'scope': context.scope,
      'attachments': context.attachments, 'distanceMeters': context.distanceMeters},
    'aimStability': aimStability, 'trackingStability': trackingStability,
    'verticalRecoil': verticalRecoil, 'horizontalDrift': horizontalDrift,
    'shotGrouping': shotGrouping, 'firstShotStability': firstShotStability,
    'overshootRate': overshootRate, 'undershootRate': undershootRate,
    'acquisitionMs': acquisitionMs, 'adsStabilizationMs': adsStabilizationMs,
    'movementRetention': movementRetention, 'fingerDragConsistency': fingerDragConsistency,
    'sprayConsistency': sprayConsistency, 'hits': hits, 'shots': shots,
    'fpsStability': fpsStability, 'thermalSeverity': thermalSeverity,
    'batteryDrainPerHour': batteryDrainPerHour, 'latencyMs': latencyMs,
    'jitterMs': jitterMs, 'packetLossPercent': packetLossPercent,
    'networkMetricsReliable': networkMetricsReliable,
    'frameMetricsReliable': frameMetricsReliable,
  };

  factory AimSample.fromJson(Map<String, dynamic> json) {
    final context = Map<String, dynamic>.from(json['context'] as Map);
    double? number(String key) => (json[key] as num?)?.toDouble();
    return AimSample(
      context: WeaponContext(weapon: context['weapon'] as String,
        scope: context['scope'] as String,
        distanceMeters: (context['distanceMeters'] as num).toDouble(),
        attachments: List<String>.from(context['attachments'] as List)),
      id: json['id'] as String, recordedAt: DateTime.parse(json['recordedAt'] as String),
      source: json['source'] as String,
      aimStability: number('aimStability'), trackingStability: number('trackingStability'),
      verticalRecoil: number('verticalRecoil'), horizontalDrift: number('horizontalDrift'),
      shotGrouping: number('shotGrouping'), firstShotStability: number('firstShotStability'),
      overshootRate: number('overshootRate'), undershootRate: number('undershootRate'),
      acquisitionMs: number('acquisitionMs'), adsStabilizationMs: number('adsStabilizationMs'),
      movementRetention: number('movementRetention'), fingerDragConsistency: number('fingerDragConsistency'),
      sprayConsistency: number('sprayConsistency'), hits: json['hits'] as int?,
      shots: json['shots'] as int?, fpsStability: number('fpsStability'),
      thermalSeverity: json['thermalSeverity'] as int?, batteryDrainPerHour: number('batteryDrainPerHour'),
      latencyMs: number('latencyMs'), jitterMs: number('jitterMs'),
      packetLossPercent: number('packetLossPercent'),
      networkMetricsReliable: json['networkMetricsReliable'] == true,
      frameMetricsReliable: json['frameMetricsReliable'] == true,
    );
  }
}

void _range(double? value, double minimum, double maximum) {
  if (value != null && (!value.isFinite || value < minimum || value > maximum)) {
    throw ArgumentError('Measurement outside valid range: $value');
  }
}

class AimReport {
  AimReport({required this.context, required this.sampleCount,
    required Map<String, double?> metrics, required Map<String, int> evidenceCounts})
      : metrics = Map.unmodifiable(metrics), evidenceCounts = Map.unmodifiable(evidenceCounts) {
    if (sampleCount <= 0 || evidenceCounts.values.any((count) => count < 0 || count > sampleCount) ||
        metrics.values.whereType<double>().any((value) => !value.isFinite || value < 0)) {
      throw ArgumentError('Reports must contain finite metrics and valid evidence counts.');
    }
    for (final key in ['aimStability', 'hitAccuracy', 'trackingStability',
      'firstShotStability', 'overshootRate', 'undershootRate', 'movementRetention',
      'targetLossDuringMovement', 'fingerDragConsistency', 'sprayConsistency', 'fpsStability']) {
      _range(metrics[key], 0, 100);
    }
    _range(metrics['thermalSeverity'], 0, 6);
  }
  final WeaponContext context;
  final int sampleCount;
  final Map<String, double?> metrics;
  final Map<String, int> evidenceCounts;
  double? get aimStability => metrics['aimStability'];
  double? get hitAccuracy => metrics['hitAccuracy'];
}

class AimRecommendation {
  const AimRecommendation({required this.context, required this.currentAds,
    required this.proposedAds, required this.evidenceCount, required this.sampleCount,
    required this.problem, required this.reason, required this.evidence,
    required this.expectedEffect, required this.tradeoff});
  final WeaponContext context;
  final double currentAds, proposedAds;
  final int evidenceCount, sampleCount;
  final String problem, reason, evidence, expectedEffect, tradeoff;
  double get delta => proposedAds - currentAds;
}

class AimComparison {
  AimComparison({required this.passed, required List<String> reasons})
      : reasons = List.unmodifiable(reasons);
  final bool passed;
  final List<String> reasons;
}

class AimCalibrationEngine {
  AimCalibrationEngine(this.guard);
  final GameModeGuard guard;
  static const minimumSamples = 5;

  AimReport analyze(List<AimSample> samples) {
    guard.requireAllowed();
    if (samples.isEmpty) {
      throw ArgumentError('At least one observation is required.');
    }
    if (samples.map((sample) => sample.id).toSet().length != samples.length) {
      throw ArgumentError('Duplicate observations cannot count as independent evidence.');
    }
    final context = samples.first.context;
    if (samples.any((sample) => sample.context != context)) {
      throw ArgumentError('Do not mix weapon, scope, attachment or distance contexts.');
    }
    final readers = <String, double? Function(AimSample)>{
      'aimStability': (s) => s.aimStability, 'trackingStability': (s) => s.trackingStability,
      'verticalRecoil': (s) => s.verticalRecoil, 'horizontalDrift': (s) => s.horizontalDrift,
      'shotGrouping': (s) => s.shotGrouping, 'firstShotStability': (s) => s.firstShotStability,
      'overshootRate': (s) => s.overshootRate, 'undershootRate': (s) => s.undershootRate,
      'acquisitionMs': (s) => s.acquisitionMs, 'adsStabilizationMs': (s) => s.adsStabilizationMs,
      'movementRetention': (s) => s.movementRetention,
      'targetLossDuringMovement': (s) => s.movementRetention == null ? null : 100 - s.movementRetention!,
      'fingerDragConsistency': (s) => s.fingerDragConsistency,
      'sprayConsistency': (s) => s.sprayConsistency,
      'fpsStability': (s) => s.frameMetricsReliable ? s.fpsStability : null,
      'thermalSeverity': (s) => s.thermalSeverity?.toDouble(),
      'batteryDrainPerHour': (s) => s.batteryDrainPerHour,
    };
    final metrics = <String, double?>{};
    final counts = <String, int>{};
    for (final entry in readers.entries) {
      final values = samples.map(entry.value).whereType<double>().toList();
      metrics[entry.key] = values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
      counts[entry.key] = values.length;
    }
    final shooting = samples.where((sample) => sample.shots != null).toList();
    final shots = shooting.fold<int>(0, (sum, sample) => sum + sample.shots!);
    final hits = shooting.fold<int>(0, (sum, sample) => sum + sample.hits!);
    metrics['hitAccuracy'] = shots == 0 ? null : hits / shots * 100;
    counts['hitAccuracy'] = shooting.length;
    return AimReport(context: context, sampleCount: samples.length,
      metrics: metrics, evidenceCounts: counts);
  }

  /// A small experiment, never an applied sensitivity or server-hit guarantee.
  /// Missing network/FPS evidence prevents claiming sensitivity is the cause.
  AimRecommendation? suggestAds(List<AimSample> samples, {required double currentAds}) {
    final report = analyze(samples);
    if (!currentAds.isFinite || currentAds < 1 || currentAds > 400) {
      throw ArgumentError('Enter the actual ADS sensitivity shown in PUBG (1–400).');
    }
    if (report.sampleCount < minimumSamples) {
      return null;
    }
    if (samples.any((s) => !s.networkMetricsReliable || !s.frameMetricsReliable ||
      s.latencyMs == null || s.jitterMs == null || s.fpsStability == null ||
      s.thermalSeverity == null || s.latencyMs! > 100 || s.jitterMs! > 20 ||
      (s.packetLossPercent ?? 0) > 1 || s.fpsStability! < 90 || s.thermalSeverity! >= 3)) {
      return null;
    }
    final over = samples.where((s) => s.overshootRate != null && s.undershootRate != null &&
      s.overshootRate! >= 30 && s.overshootRate! > s.undershootRate! + 10).length;
    final under = samples.where((s) => s.overshootRate != null && s.undershootRate != null &&
      s.undershootRate! >= 30 && s.undershootRate! > s.overshootRate! + 10).length;
    final threshold = math.max(minimumSamples, (samples.length * .7).ceil());
    if (over < threshold && under < threshold) {
      return null;
    }
    // PUBG's percentage ADS controls use whole points. Do not recommend an
    // unenterable decimal or infer control precision from a fractional import.
    if (currentAds != currentAds.roundToDouble()) return null;
    final decreasing = over >= threshold;
    final step = (currentAds * .05).clamp(1.0, 20.0).floorToDouble();
    final proposed = (currentAds + (decreasing ? -step : step)).clamp(1.0, 400.0).toDouble();
    if (proposed == currentAds) {
      return null;
    }
    final evidenceCount = decreasing ? over : under;
    return AimRecommendation(context: report.context, currentAds: currentAds,
      proposedAds: proposed,
      evidenceCount: evidenceCount, sampleCount: samples.length,
      problem: decreasing ? 'تجاوز الهدف المتكرر' : 'التوقف قبل الهدف المتكرر',
      reason: 'ظهر نمط متكرر في نفس السلاح والسكوب والملحقات والمسافة؛ تجربة بخطوة صحيحة صغيرة ضمن حد 5٪ وبحد أدنى نقطة.',
      evidence: '$evidenceCount/${samples.length} ملاحظات؛ مصدرها مدخلات المستخدم أو قياسات موثقة، وليست قراءة لسيرفر اللعبة. '
        '${samples.any((s) => s.packetLossPercent == null) ? 'فقد الحزم UNKNOWN؛ لا يستبعد الاقتراح سببًا غير مقاس.' : ''}',
      expectedEffect: decreasing ? 'قد يقل تجاوز الهدف مع تحسن الثبات؛ يلزم قياس جديد.' : 'قد يتحسن الوصول إلى الهدف؛ يلزم قياس جديد.',
      tradeoff: decreasing ? 'قد يصبح اكتساب الهدف أبطأ.' : 'قد يزيد تجاوز الهدف أو يتراجع ثبات الرش.');
  }

  /// Final approval remains a separate explicit user action in the workflow.
  AimComparison compare(AimReport before, AimReport after) {
    guard.requireAllowed();
    final reasons = <String>[];
    if (before.context != after.context) {
      reasons.add('اختلف سياق السلاح أو المسافة.');
    }
    if (before.sampleCount < minimumSamples || after.sampleCount < minimumSamples) {
      reasons.add('يلزم خمس عينات مستقلة على الأقل لكل نسخة.');
    }
    const higherBetter = ['aimStability', 'hitAccuracy', 'trackingStability',
      'firstShotStability', 'movementRetention', 'fingerDragConsistency', 'sprayConsistency', 'fpsStability'];
    const lowerBetter = ['shotGrouping', 'overshootRate', 'undershootRate',
      'acquisitionMs', 'adsStabilizationMs', 'thermalSeverity', 'batteryDrainPerHour'];
    for (final key in [...higherBetter, ...lowerBetter]) {
      final oldValue = before.metrics[key];
      final newValue = after.metrics[key];
      if (oldValue == null || newValue == null ||
          (before.evidenceCounts[key] ?? 0) < minimumSamples ||
          (after.evidenceCounts[key] ?? 0) < minimumSamples) {
        reasons.add('أدلة غير كافية للمؤشر $key.');
        continue;
      }
      if ((higherBetter.contains(key) && newValue < oldValue) ||
          (lowerBetter.contains(key) && newValue > oldValue)) {
        reasons.add('تراجع المؤشر الأساسي $key.');
      }
    }
    for (final key in ['aimStability', 'hitAccuracy']) {
      final oldValue = before.metrics[key];
      final newValue = after.metrics[key];
      if (oldValue == null || newValue == null || newValue <= oldValue) {
        reasons.add('يجب إثبات تحسن $key؛ سرعة الحساسية وحدها لا تكفي.');
      }
    }
    return AimComparison(passed: reasons.isEmpty, reasons: reasons);
  }
}
