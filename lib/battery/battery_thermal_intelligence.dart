import '../game_mode_guard/game_mode_guard.dart';

enum ThermalLevel { unknown, nominal, fair, serious, critical }
enum SpiderWorkload { stopped, low, normal, eventBurst }

class WorkloadPlan {
  const WorkloadPlan({required this.workload, required this.samplesPerMinute,
    required this.deferHeavyAnalysis, required this.pauseSecondaryTasks,
    required this.networkAllowed, required this.reason});
  final SpiderWorkload workload;
  final int samplesPerMinute;
  final bool deferHeavyAnalysis, pauseSecondaryTasks, networkAllowed;
  final String reason;
  // These are deliberately immutable policy invariants, not user controls.
  bool get changesGameFps => false;
  bool get changesGameGraphics => false;
  bool get changesDisplayRefreshRate => false;
  bool get changesTouchResponsiveness => false;
}

class BatteryReading {
  BatteryReading({required this.at, this.levelPercent, this.charging,
    this.thermal = ThermalLevel.unknown, this.spiderCpuTimeMs,
    this.spiderWorkingSetBytes}) {
    if (levelPercent != null && (!levelPercent!.isFinite || levelPercent! < 0 || levelPercent! > 100)) {
      throw ArgumentError('Battery level must be an actual 0–100% reading.');
    }
    if (spiderCpuTimeMs != null && (!spiderCpuTimeMs!.isFinite || spiderCpuTimeMs! < 0)) {
      throw ArgumentError('App CPU time must be finite and nonnegative.');
    }
    if (spiderWorkingSetBytes != null && spiderWorkingSetBytes! < 0) {
      throw ArgumentError('App memory must be nonnegative.');
    }
  }
  final DateTime at;
  final double? levelPercent;
  final bool? charging;
  final ThermalLevel thermal;
  final double? spiderCpuTimeMs;
  final int? spiderWorkingSetBytes;
}

class BatterySessionReport {
  BatterySessionReport({required this.duration, required this.startPercent,
    required this.endPercent, required this.drainPerHour,
    required this.worstThermal, required this.spiderCpuCorePercent,
    required List<String> recommendations}) : recommendations = List.unmodifiable(recommendations);
  final Duration duration;
  final double? startPercent, endPercent, drainPerHour, spiderCpuCorePercent;
  final ThermalLevel worstThermal;
  final List<String> recommendations;
  // CPU core utilization is not battery energy. Attribution requires OS support.
  double? get pubgEnergyUse => null;
  double? get spiderBatteryOverhead => null;
  double? get pubgFpsStability => null;
}

class BatteryThermalIntelligence {
  const BatteryThermalIntelligence();

  /// Only SPIDER AIM's own scheduling may be changed automatically.
  WorkloadPlan plan({required bool safeOfflineSession,
    required ThermalLevel thermal, double? batteryPercent,
    double? ownWorkMilliseconds, bool importantEvent = false}) {
    if (batteryPercent != null && (!batteryPercent.isFinite || batteryPercent < 0 || batteryPercent > 100)) {
      throw ArgumentError('Invalid battery reading.');
    }
    if (ownWorkMilliseconds != null && (!ownWorkMilliseconds.isFinite || ownWorkMilliseconds < 0)) {
      throw ArgumentError('Invalid measured SPIDER AIM workload.');
    }
    if (!safeOfflineSession || thermal == ThermalLevel.critical) {
      return const WorkloadPlan(workload: SpiderWorkload.stopped,
        samplesPerMinute: 0, deferHeavyAnalysis: true, pauseSecondaryTasks: true,
        networkAllowed: false, reason: 'التحليل متوقف: وضع غير مؤكد/مصنف أو حالة حرارية حرجة.');
    }
    final constrained = thermal == ThermalLevel.serious || thermal == ThermalLevel.fair ||
      (batteryPercent != null && batteryPercent <= 20) ||
      (ownWorkMilliseconds != null && ownWorkMilliseconds > 8);
    if (constrained) {
      return const WorkloadPlan(workload: SpiderWorkload.low,
        samplesPerMinute: 2, deferHeavyAnalysis: true, pauseSecondaryTasks: true,
        networkAllowed: false, reason: 'خفض حمل SPIDER AIM وتأجيل العمل الثقيل لحماية تجربة اللعب.');
    }
    return WorkloadPlan(workload: importantEvent ? SpiderWorkload.eventBurst : SpiderWorkload.normal,
      samplesPerMinute: importantEvent ? 12 : 4,
      deferHeavyAnalysis: !importantEvent, pauseSecondaryTasks: false,
      networkAllowed: false, reason: 'معالجة محلية محدودة؛ لا تسجيل شاشة أو بث مباشر.');
  }

  BatterySessionReport report(List<BatteryReading> readings) {
    if (readings.length < 2) {
      throw ArgumentError('Start and end readings are required.');
    }
    for (var i = 1; i < readings.length; i++) {
      if (!readings[i].at.isAfter(readings[i - 1].at)) {
        throw ArgumentError('Battery readings must be strictly time ordered.');
      }
    }
    final first = readings.first;
    final last = readings.last;
    final duration = last.at.difference(first.at);
    final completeUnplugged = readings.every((r) => r.charging == false && r.levelPercent != null);
    final monotonicallyDischarging = List.generate(readings.length - 1,
      (i) => readings[i + 1].levelPercent != null && readings[i].levelPercent != null &&
        readings[i + 1].levelPercent! <= readings[i].levelPercent!).every((v) => v);
    // Very short or charging sessions cannot support a useful drain projection.
    final rate = completeUnplugged && monotonicallyDischarging && duration.inMinutes >= 5 ?
      (first.levelPercent! - last.levelPercent!) / (duration.inMilliseconds / 3600000) : null;
    final cpuDelta = first.spiderCpuTimeMs == null || last.spiderCpuTimeMs == null ? null :
      last.spiderCpuTimeMs! - first.spiderCpuTimeMs!;
    final rawCpu = cpuDelta == null || cpuDelta < 0 || duration.inMilliseconds == 0 ? null :
      cpuDelta / duration.inMilliseconds * 100;
    final cpu = rawCpu != null && rawCpu.isFinite ? rawCpu : null;
    final worst = readings.map((r) => r.thermal).reduce((a, b) => a.index >= b.index ? a : b);
    final advice = <String>['المعدل يخص الجهاز بالكامل، ولا ينسب الاستهلاك إلى PUBG.'];
    if (readings.any((reading) => reading.thermal == ThermalLevel.unknown)) {
      advice.add('الحالة الحرارية القصوى تخص القراءات المتاحة؛ توجد قراءات حرارية UNKNOWN.');
    }
    if (rate == null) {
      advice.add('معدل التفريغ UNKNOWN: شحن أو بيانات ناقصة أو جلسة أقصر من خمس دقائق.');
    }
    if (worst == ThermalLevel.serious || worst == ThermalLevel.critical) {
      advice.add('أوقف العمل الثقيل داخل SPIDER AIM واترك الجهاز يبرد؛ لا تخفيض تلقائي لجودة اللعبة.');
    }
    if (cpu != null && cpu > 5) {
      advice.add('حمل SPIDER AIM المقاس مرتفع نسبيًا؛ قلّل وتيرة تحليله.');
    }
    advice.add('استهلاك SPIDER AIM من طاقة البطارية وFPS اللعبة UNKNOWN دون API موثوق.');
    return BatterySessionReport(duration: duration, startPercent: first.levelPercent,
      endPercent: last.levelPercent, drainPerHour: rate, worstThermal: worst,
      spiderCpuCorePercent: cpu, recommendations: advice);
  }
}

/// Guarded scheduling hook for a future official passive analysis provider.
/// This implementation deliberately does not start screen capture or run live.
class PassiveAnalysisPolicy {
  PassiveAnalysisPolicy(this.guard);
  final GameModeGuard guard;
  WorkloadPlan offlinePlan({required ThermalLevel thermal, double? batteryPercent,
    double? ownWorkMilliseconds, bool importantEvent = false}) {
    return const BatteryThermalIntelligence().plan(safeOfflineSession: guard.allowed,
      thermal: thermal, batteryPercent: batteryPercent,
      ownWorkMilliseconds: ownWorkMilliseconds, importantEvent: importantEvent);
  }
}
