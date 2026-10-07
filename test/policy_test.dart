import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/battery/battery_thermal_intelligence.dart';
import 'package:spider_aim/profiles/settings_policy.dart';
import 'package:spider_aim/testing/comparison_policy.dart';

Map<String, double> _metrics() => {
  'aimStability': 60,
  'hitRate': 55,
  'trackingScore': 65,
  'adsStability': 65,
  'movementRetention': 65,
  'fpsStability': 95,
  'sprayGrouping': 10,
  'overshootRate': 20,
  'undershootRate': 10,
  'acquisitionMs': 400,
  'thermalImpact': 1,
  'batteryDrain': 12,
};

Map<String, double> _improved() => {
  ..._metrics(),
  'aimStability': 70,
  'hitRate': 65,
  'sampleCount': 5,
};

void main() {
  group('NON_GYRO and official manual settings policy', () {
    test('touch-only default cannot be mutated globally', () {
      expect(SettingsPolicy.playerMode, 'NON_GYRO');
      expect(SettingsPolicy.inputMode, 'TOUCH_ONLY');
      expect(SettingsPolicy.nonGyro['gyroscope'], isFalse);
      expect(SettingsPolicy.nonGyro['adsGyroscope'], isFalse);
      final copy = SettingsPolicy.nonGyro;
      copy['gyroscope'] = true;
      expect(SettingsPolicy.nonGyro['gyroscope'], isFalse);
    });

    test('gyro, FPS, refresh rate and automation are not writable settings', () {
      for (final setting in [
        'gyroscope', 'adsGyroscope', 'GYROSCOPE', 'fps', 'graphics',
        'refreshRate', 'touchSamplingRate', 'playerSpeed', 'autoAim',
      ]) {
        expect(
          () => SettingsPolicy.validate({'M416|3x|Compensator|50::$setting': 1}),
          throwsArgumentError,
          reason: setting,
        );
      }
    });

    test('weapon, scope, attachment and distance remain part of every key', () {
      for (final key in [
        'ads', 'M416::ads', 'M416|3x|Compensator::ads',
        '|3x|Compensator|50::ads', 'M416||Compensator|50::ads',
        'M416|3x||50::ads', 'M416|3x|Compensator|0::ads',
        'M416|3x|Compensator|-1::ads', 'M416|3x|Compensator|NaN::ads',
        'M416|3x|Compensator|Infinity::ads',
      ]) {
        expect(() => SettingsPolicy.validate({key: 31}), throwsArgumentError);
      }
      expect(
        () => SettingsPolicy.validate({'M416|3x|Compensator|50::ads': 31}),
        returnsNormally,
      );
    });

    test('nonfinite and out-of-range sensitivity values are rejected', () {
      for (final value in [double.nan, double.infinity, -1.0, 401.0]) {
        expect(
          () => SettingsPolicy.validate({'M416|3x|Compensator|50::ads': value}),
          throwsArgumentError,
        );
      }
    });

    test('initial weapon and scope catalogs cover the specification', () {
      expect(SettingsPolicy.weapons, containsAll(
        ['M416', 'AUG', 'SCAR-L', 'AKM', 'ACE32', 'UMP45', 'DP-28'],
      ));
      expect(SettingsPolicy.scopes, containsAll(
        ['Iron Sight', 'Red Dot', 'Holo', '2x', '3x', '4x', '6x', '8x'],
      ));
    });
  });

  group('multi-metric comparison', () {
    test('both stability and observed hit rate must improve', () {
      expect(ComparisonPolicy.compare(_metrics(), _improved()).passed, isTrue);
      for (final requiredMetric in ['aimStability', 'hitRate']) {
        final after = _improved()..[requiredMetric] = _metrics()[requiredMetric]!;
        expect(ComparisonPolicy.compare(_metrics(), after).passed, isFalse);
      }
      final onlyFaster = {..._metrics(), 'acquisitionMs': 200.0, 'sampleCount': 5.0};
      expect(ComparisonPolicy.compare(_metrics(), onlyFaster).passed, isFalse);
    });

    test('regression in any protected metric prevents passing', () {
      for (final metric in ComparisonPolicy.higherIsBetter) {
        final after = _improved()..[metric] = _metrics()[metric]! - 1;
        expect(ComparisonPolicy.compare(_metrics(), after).passed, isFalse,
          reason: metric);
      }
      for (final metric in ComparisonPolicy.lowerIsBetter) {
        final after = _improved()..[metric] = _metrics()[metric]! + 1;
        expect(ComparisonPolicy.compare(_metrics(), after).passed, isFalse,
          reason: metric);
      }
    });

    test('missing or invalid measurements cannot be invented to pass', () {
      for (final metric in ComparisonPolicy.keys) {
        final missing = _improved()..remove(metric);
        expect(() => ComparisonPolicy.compare(_metrics(), missing), throwsArgumentError);
        for (final invalid in [double.nan, double.infinity, -1.0]) {
          final after = _improved()..[metric] = invalid;
          expect(() => ComparisonPolicy.compare(_metrics(), after), throwsArgumentError);
        }
      }
      expect(() => ComparisonPolicy.validate(_metrics()..['aimStability'] = 101),
        throwsArgumentError);
      expect(() => ComparisonPolicy.validate(_metrics()..['thermalImpact'] = 7),
        throwsArgumentError);
    });

    test('fewer than five independent samples cannot pass', () {
      for (final samples in [0.0, 1.0, 4.0]) {
        expect(ComparisonPolicy.compare(_metrics(), _improved()..['sampleCount'] = samples).passed,
          isFalse);
      }
      expect(ComparisonPolicy.compare(_metrics(), _improved()..remove('sampleCount')).passed,
        isFalse);
    });

    test('nonfinite or fractional sample counts never pass', () {
      for (final samples in [double.nan, double.infinity, 5.5]) {
        var rejected = false;
        try {
          rejected = !ComparisonPolicy.compare(
            _metrics(), _improved()..['sampleCount'] = samples,
          ).passed;
        } on ArgumentError {
          rejected = true;
        }
        expect(rejected, isTrue, reason: 'sampleCount=$samples');
      }
    });
  });

  group('battery workload safety', () {
    const engine = BatteryThermalIntelligence();

    test('all automatic plans preserve game FPS, graphics, refresh and touch', () {
      for (final thermal in ThermalLevel.values) {
        for (final safe in [true, false]) {
          for (final battery in [10.0, 80.0]) {
            final plan = engine.plan(safeOfflineSession: safe, thermal: thermal,
              batteryPercent: battery, ownWorkMilliseconds: 15, importantEvent: true);
            expect(plan.changesGameFps, isFalse);
            expect(plan.changesGameGraphics, isFalse);
            expect(plan.changesDisplayRefreshRate, isFalse);
            expect(plan.changesTouchResponsiveness, isFalse);
            expect(plan.networkAllowed, isFalse);
            if (!safe || thermal == ThermalLevel.critical) {
              expect(plan.workload, SpiderWorkload.stopped);
              expect(plan.samplesPerMinute, 0);
            }
          }
        }
      }
    });

    test('own workload is reduced before any game performance tradeoff', () {
      final normal = engine.plan(safeOfflineSession: true, thermal: ThermalLevel.nominal,
        batteryPercent: 80, ownWorkMilliseconds: 2);
      final overloaded = engine.plan(safeOfflineSession: true, thermal: ThermalLevel.nominal,
        batteryPercent: 80, ownWorkMilliseconds: 12, importantEvent: true);
      expect(overloaded.samplesPerMinute, lessThan(normal.samplesPerMinute));
      expect(overloaded.deferHeavyAnalysis, isTrue);
      expect(overloaded.pauseSecondaryTasks, isTrue);
    });

    test('report distinguishes device drain from unknown app energy attribution', () {
      final start = DateTime.utc(2026, 10, 7);
      final report = engine.report([
        BatteryReading(at: start, levelPercent: 80, charging: false,
          spiderCpuTimeMs: 100),
        BatteryReading(at: start.add(const Duration(minutes: 30)),
          levelPercent: 75, charging: false, spiderCpuTimeMs: 18100),
      ]);
      expect(report.drainPerHour, 10);
      expect(report.spiderCpuCorePercent, 1);
      expect(report.pubgEnergyUse, isNull);
      expect(report.spiderBatteryOverhead, isNull);
      expect(report.pubgFpsStability, isNull);
    });
  });
}
