class ComparisonResult {
  const ComparisonResult(this.passed, this.reasons);
  final bool passed;
  final List<String> reasons;
}

class ComparisonPolicy {
  static const higherIsBetter = {
    'aimStability', 'hitRate', 'trackingScore', 'adsStability',
    'movementRetention', 'fpsStability',
  };
  static const lowerIsBetter = {
    'sprayGrouping', 'overshootRate', 'undershootRate', 'acquisitionMs',
    'thermalImpact', 'batteryDrain',
  };
  static Set<String> get keys => {...higherIsBetter, ...lowerIsBetter};
  static void validate(Map<String, double> metrics) {
    for (final key in keys) {
      final v = metrics[key];
      final max = key == 'acquisitionMs' || key == 'batteryDrain' || key == 'sprayGrouping'
          ? double.infinity : key == 'thermalImpact' ? 6.0 : 100.0;
      if (v == null || !v.isFinite || v < 0 || v > max) {
        throw ArgumentError('المؤشر $key غير متاح أو غير صالح؛ لا يمكن الاعتماد.');
      }
    }
  }
  static ComparisonResult compare(Map<String, double> before, Map<String, double> after) {
    validate(before);
    validate(after);
    final reasons = <String>[];
    final count = after['sampleCount'];
    if (count == null || !count.isFinite || count < 5 || count != count.truncateToDouble()) {
      reasons.add('يلزم عدد صحيح من 5 اختبارات مستقلة على الأقل.');
    }
    if (after['aimStability']! <= before['aimStability']!) {
      reasons.add('لم يتحسن ثبات التصويب.');
    }
    if (after['hitRate']! <= before['hitRate']!) {
      reasons.add('لم تتحسن نسبة الإصابات المرصودة يدويًا.');
    }
    for (final key in higherIsBetter) {
      if (after[key]! < before[key]!) {
        reasons.add('تراجع $key');
      }
    }
    for (final key in lowerIsBetter) {
      if (after[key]! > before[key]!) {
        reasons.add('تراجع $key');
      }
    }
    return ComparisonResult(reasons.isEmpty, reasons);
  }
}
