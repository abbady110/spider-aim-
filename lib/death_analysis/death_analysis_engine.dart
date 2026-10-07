import '../game_mode_guard/game_mode_guard.dart';
import '../hit_registration/hit_registration_diagnostics.dart';

enum DeathCause {
  inconclusive, aimOvershoot, aimUndershoot, poorTracking, badRecoilControl,
  lateAds, badPeek, poorMovement, poorPositioning, exposureTooLong,
  wrongScopeForDistance, fpsDrop, thermalIssue, networkIssue, tacticalMistake,
}

class DeathObservation {
  DeathObservation({required this.id, required this.recordedAt,
    required this.observedCause, this.source = 'MANUAL_REVIEW',
    this.reliableEvidence = false, this.hitEvidence}) {
    if (id.trim().isEmpty || source.trim().isEmpty) {
      throw ArgumentError('A unique observation ID and source are required.');
    }
  }
  final String id, source;
  final DateTime recordedAt;
  final DeathCause observedCause;
  final bool reliableEvidence;
  final HitEvidence? hitEvidence;
}

class DeathAnalysisReport {
  DeathAnalysisReport({required this.sampleCount, required this.primaryCause,
    required Map<DeathCause, int> patterns, required this.sensitivityPattern,
    required List<String> recommendations})
      : patterns = Map.unmodifiable(patterns), recommendations = List.unmodifiable(recommendations);
  final int sampleCount;
  final DeathCause primaryCause;
  final Map<DeathCause, int> patterns;
  final bool sensitivityPattern;
  final List<String> recommendations;
}

class DeathAnalysisEngine {
  DeathAnalysisEngine(this.guard);
  final GameModeGuard guard;

  DeathAnalysisReport analyze(List<DeathObservation> observations) {
    guard.requireAllowed();
    if (observations.isEmpty ||
        observations.map((observation) => observation.id).toSet().length != observations.length) {
      throw ArgumentError('Supply independent post-session observations.');
    }
    final patterns = <DeathCause, int>{};
    var confounded = false;
    for (final observation in observations) {
      final cause = observation.observedCause;
      patterns[cause] = (patterns[cause] ?? 0) + 1;
      if (const [DeathCause.fpsDrop, DeathCause.thermalIssue, DeathCause.networkIssue].contains(cause)) {
        confounded = true;
      }
      if (observation.hitEvidence != null &&
          HitRegistrationDiagnostics(guard).diagnose(observation.hitEvidence!).hasPerformanceConfounder) {
        confounded = true;
      }
    }
    final ordered = patterns.entries.where((entry) => entry.key != DeathCause.inconclusive)
      .toList()..sort((a, b) => b.value.compareTo(a.value));
    final hasPattern = observations.length >= 5 && ordered.isNotEmpty &&
      ordered.first.value >= 3 && ordered.first.value / observations.length >= .6 &&
      (ordered.length == 1 || ordered.first.value > ordered[1].value);
    final dominant = hasPattern ? ordered.first.key : DeathCause.inconclusive;
    final allMeasured = observations.every((o) => o.reliableEvidence);
    final sensitivityPattern = hasPattern && allMeasured && !confounded &&
      const [DeathCause.aimOvershoot, DeathCause.aimUndershoot].contains(dominant);
    final notes = <String>[];
    if (!allMeasured) {
      notes.add('الأنماط مبنية على مراجعة المستخدم؛ السبب النهائي غير مؤكد.');
    }
    if (!hasPattern) {
      notes.add('لا يوجد نمط متكرر كافٍ؛ اجمع خمس ملاحظات على الأقل ولا تغيّر الحساسية بسبب وفاة واحدة.');
    }
    if (hasPattern) {
      switch (dominant) {
        case DeathCause.aimOvershoot:
        case DeathCause.aimUndershoot:
          notes.add(confounded ? 'عالج مؤشرات الشبكة أو الإطارات أو الحرارة أولًا قبل عزو الوفاة للحساسية.' :
            'أعد اختبار اكتساب الهدف في نفس السلاح والسكوب؛ أي تعديل يحتاج أدلة معايرة مستقلة.');
        case DeathCause.poorTracking:
          notes.add('اختبر تتبع هدف متحرك واحتفاظ التصويب أثناء الحركة في Training.');
        case DeathCause.badRecoilControl:
          notes.add('قارن تجمع الرش وسحب الإصبع مع نفس الملحقات والمسافة.');
        case DeathCause.lateAds:
          notes.add('قِس زمن Sprint → ADS وStop → ADS وراجع موضع زر التصويب.');
        case DeathCause.badPeek:
        case DeathCause.exposureTooLong:
        case DeathCause.poorPositioning:
        case DeathCause.tacticalMistake:
          notes.add('راجع التمركز ومدة الانكشاف وزاوية Peek؛ هذا لا يثبت مشكلة حساسية.');
        case DeathCause.fpsDrop:
        case DeathCause.thermalIssue:
        case DeathCause.networkIssue:
          notes.add('راجع مؤشرات الشبكة وFPS والحرارة مع توقيت الوفاة؛ لا توجد توصية حساسية.');
        case DeathCause.poorMovement:
          notes.add('اختبر تغيير الاتجاه وترتيب أزرار الحركة واحتفاظ التصويب.');
        case DeathCause.wrongScopeForDistance:
          notes.add('أعد اختبار نفس المسافة بسكوب مناسب ضمن اختيارات اللعبة الرسمية.');
        case DeathCause.inconclusive:
          break;
      }
    }
    return DeathAnalysisReport(sampleCount: observations.length,
      primaryCause: allMeasured && hasPattern ? dominant : DeathCause.inconclusive,
      patterns: patterns, sensitivityPattern: sensitivityPattern, recommendations: notes);
  }
}
