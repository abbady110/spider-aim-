import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/aim/aim_calibration_engine.dart';
import 'package:spider_aim/battery/battery_thermal_intelligence.dart';
import 'package:spider_aim/death_analysis/death_analysis_engine.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/hit_registration/hit_registration_diagnostics.dart';
import 'package:spider_aim/landing/landing_assistant.dart';
import 'package:spider_aim/movement/movement_calibration_engine.dart';
import 'package:spider_aim/throwables/throwables_calibration_engine.dart';

import 'support/recognized_guard.dart';

final _time = DateTime.utc(2026, 1, 1);
WeaponContext _context({String scope = '3x', double distance = 50}) => WeaponContext(
  weapon: 'M416', scope: scope, distanceMeters: distance,
  attachments: ['Vertical Grip', 'Compensator']);

AimSample _sample(int id, {WeaponContext? context, double aim = 60, int hits = 60,
  double fps = 99, double overshoot = 40, double undershoot = 10,
  double ping = 30, double jitter = 3, int heat = 1,
  bool reliable = true}) => AimSample(
    context: context ?? _context(), id: '$id', recordedAt: _time.add(Duration(seconds: id)),
    aimStability: aim, trackingStability: 70, verticalRecoil: 12,
    horizontalDrift: 4, shotGrouping: 15, firstShotStability: 80,
    overshootRate: overshoot, undershootRate: undershoot, acquisitionMs: 300,
    adsStabilizationMs: 200, movementRetention: 80, fingerDragConsistency: 75,
    sprayConsistency: 80, hits: hits, shots: 100, fpsStability: fps,
    thermalSeverity: heat, batteryDrainPerHour: 12, latencyMs: ping,
    jitterMs: jitter, packetLossPercent: 0, networkMetricsReliable: reliable,
    frameMetricsReliable: reliable);

List<AimSample> _samples({double aim = 60, int hits = 60, double fps = 99}) =>
  List.generate(5, (i) => _sample(i, aim: aim, hits: hits, fps: fps));

ThrowableTrial _throw(int id, {bool landed = true, bool visible = true,
  bool displayed = true, bool cancel = true, bool cook = true,
  ThrowableObstacle obstacle = ThrowableObstacle.rock, double angle = 20}) =>
  ThrowableTrial(id: '$id', obstacle: obstacle, landedAsIntended: landed,
    trajectoryVisible: visible, gameDisplaysTrajectory: displayed, peekReady: true,
    cancelSucceeded: cancel, cookTimingSuccessful: cook, viewAngleDegrees: angle);

LandingInput _landing({double east = 0, double north = 1500, double heading = 0}) =>
  LandingInput(aircraft: MapPosition(0, 0), target: MapPosition(east, north),
    aircraftHeadingDegrees: heading, aircraftSpeedMetersPerSecond: 100,
    measuredGlideMetersPerSecond: 50, measuredDescentMetersPerSecond: 10,
    altitudeMeters: 300, fastDiveStartAltitudeMeters: 100,
    measuredDiveHorizontalMetersPerSecond: 10, measuredDiveDescentMetersPerSecond: 50);

void main() {
  late GameModeGuard guard;
  setUp(() { guard = recognizedGuard(mode: GameMode.trainingSafe); });

  group('all coaching entry points obey Ranked and UNKNOWN lock', () {
    for (final mode in [GameMode.competitiveBlocked, GameMode.unknownBlocked]) {
      test('$mode blocks all gameplay analyses even with observations', () {
        if (mode == GameMode.competitiveBlocked) {
          observeCompetitiveSession(guard);
        } else {
          guard.stopCaptureSession();
        }
        expect(guard.mode, mode);
        expect(() => AimCalibrationEngine(guard).analyze(_samples()), throwsStateError);
        expect(() => AimCalibrationEngine(guard).suggestAds(_samples(), currentAds: 50), throwsStateError);
        expect(() => MovementCalibrationEngine(guard).analyze([]), throwsStateError);
        expect(() => ThrowablesCalibrationEngine(guard).analyze([]), throwsStateError);
        expect(() => DeathAnalysisEngine(guard).analyze([]), throwsStateError);
        expect(() => HitRegistrationDiagnostics(guard).diagnose(HitEvidence()), throwsStateError);
        expect(() => LandingAssistant(guard).plan(_landing()), throwsStateError);
        final plan = PassiveAnalysisPolicy(guard).offlinePlan(thermal: ThermalLevel.nominal);
        expect(plan.workload, SpiderWorkload.stopped);
        expect(plan.samplesPerMinute, 0);
      });
    }
    test('comparison is blocked after session invalidation', () {
      final engine = AimCalibrationEngine(guard);
      final baseline = engine.analyze(_samples());
      final candidate = engine.analyze(_samples(aim: 70, hits: 70));
      guard.invalidate();
      expect(() => engine.compare(baseline, candidate), throwsStateError);
    });
  });

  group('Aim calibration evidence and acceptance', () {
    test('normalizes attachment order but isolates scope and distance', () {
      final context = WeaponContext(weapon: 'M416', scope: '3x', distanceMeters: 50,
        attachments: ['Compensator', 'Vertical Grip']);
      expect(context, _context());
      expect(context, isNot(_context(scope: 'Red Dot')));
      expect(context, isNot(_context(distance: 100)));
    });
    test('does not average mixed weapon contexts', () {
      expect(() => AimCalibrationEngine(guard).analyze([
        _sample(1), _sample(2, context: _context(scope: 'Red Dot'))]), throwsArgumentError);
    });
    test('duplicate observations do not create repeated evidence', () {
      expect(() => AimCalibrationEngine(guard).analyze([_sample(1), _sample(1)]), throwsArgumentError);
    });
    test('unknown metrics remain null rather than zero or inferred', () {
      final sample = AimSample(context: _context(), id: 'empty', recordedAt: _time);
      final report = AimCalibrationEngine(guard).analyze([sample]);
      expect(report.aimStability, isNull);
      expect(report.hitAccuracy, isNull);
      expect(report.metrics['targetLossDuringMovement'], isNull);
      expect(report.evidenceCounts['aimStability'], 0);
    });
    test('hit accuracy is weighted by actual shots instead of averaging rates', () {
      final report = AimCalibrationEngine(guard).analyze([
        AimSample(context: _context(), id: 'a', recordedAt: _time, hits: 1, shots: 1),
        AimSample(context: _context(), id: 'b', recordedAt: _time, hits: 0, shots: 9),
      ]);
      expect(report.hitAccuracy, 10);
      expect(report.evidenceCounts['hitAccuracy'], 2);
    });
    test('preserves provenance and nullable measurements on JSON round trip', () {
      final sample = _sample(1);
      final copy = AimSample.fromJson(sample.toJson());
      expect(copy.toJson(), sample.toJson());
    });
    test('rejects nonfinite scores and impossible hit accounting', () {
      expect(() => _sample(1, aim: double.nan), throwsArgumentError);
      expect(() => _sample(1, hits: 101), throwsArgumentError);
      expect(() => _sample(1, overshoot: 90, undershoot: 50), throwsArgumentError);
      expect(() => WeaponContext(weapon: 'M416', scope: '3x', distanceMeters: double.infinity), throwsArgumentError);
      expect(() => AimReport(context: _context(), sampleCount: 5,
        metrics: {'aimStability': double.nan}, evidenceCounts: {'aimStability': 5}), throwsArgumentError);
      expect(() => AimReport(context: _context(), sampleCount: 5,
        metrics: {'aimStability': 101}, evidenceCounts: {'aimStability': 5}), throwsArgumentError);
      expect(() => AimCalibrationEngine(guard).suggestAds(_samples(), currentAds: .5), throwsArgumentError);
    });
    test('one attempt never leads to sensitivity suggestion', () {
      expect(AimCalibrationEngine(guard).suggestAds([_sample(1)], currentAds: 31), isNull);
    });
    test('small proposal reflects repeated overshoot and never mutates input', () {
      final observations = _samples();
      final proposal = AimCalibrationEngine(guard).suggestAds(observations, currentAds: 100)!;
      expect(proposal.currentAds, 100);
      expect(proposal.proposedAds, 95);
      expect(proposal.evidenceCount, 5);
      expect(proposal.sampleCount, 5);
      expect(proposal.reason, isNotEmpty);
      expect(proposal.evidence, isNotEmpty);
      expect(proposal.tradeoff, isNotEmpty);
      expect(observations.first.overshootRate, 40);
    });
    test('undershoot suggests a small increase rather than maximum sensitivity', () {
      final proposal = AimCalibrationEngine(guard).suggestAds(
        List.generate(5, (i) => _sample(i, overshoot: 10, undershoot: 40)), currentAds: 100)!;
      expect(proposal.proposedAds, 105);
    });
    test('rounding never increases an experiment beyond the five percent limit', () {
      final proposal = AimCalibrationEngine(guard).suggestAds(_samples(), currentAds: 1.17)!;
      expect(proposal.delta.abs(), lessThanOrEqualTo(1.17 * .05));
      expect(proposal.proposedAds, lessThan(proposal.currentAds));
    });
    test('network, jitter, thermal, unknown and FPS confounders suppress ADS proposals', () {
      final confoundedSets = [
        List.generate(5, (i) => _sample(i, ping: 150)),
        List.generate(5, (i) => _sample(i, jitter: 35)),
        List.generate(5, (i) => _sample(i, heat: 3)),
        List.generate(5, (i) => _sample(i, reliable: false)),
        List.generate(5, (i) => _sample(i, fps: 65)),
      ];
      for (final observations in confoundedSets) {
        expect(AimCalibrationEngine(guard).suggestAds(observations, currentAds: 31), isNull);
      }
    });
    test('improved aim AND hit rate with no regressions passes comparison', () {
      final engine = AimCalibrationEngine(guard);
      expect(engine.compare(engine.analyze(_samples()),
        engine.analyze(_samples(aim: 70, hits: 70))).passed, isTrue);
    });
    test('faster aim or improved hit rate alone does not pass', () {
      final engine = AimCalibrationEngine(guard);
      final baseline = engine.analyze(_samples());
      expect(engine.compare(baseline, engine.analyze(_samples(aim: 70))).passed, isFalse);
      expect(engine.compare(baseline, engine.analyze(_samples(hits: 70))).passed, isFalse);
    });
    test('FPS regression vetoes improvements in both primary outcomes', () {
      final engine = AimCalibrationEngine(guard);
      final result = engine.compare(engine.analyze(_samples()),
        engine.analyze(_samples(aim: 70, hits: 70, fps: 80)));
      expect(result.passed, isFalse);
      expect(result.reasons.any((reason) => reason.contains('fpsStability')), isTrue);
    });
    test('missing comparison evidence cannot pass final gate', () {
      final engine = AimCalibrationEngine(guard);
      final before = engine.analyze(List.generate(5, (i) => AimSample(
        context: _context(), id: '$i', recordedAt: _time, aimStability: 60, hits: 6, shots: 10)));
      final after = engine.analyze(List.generate(5, (i) => AimSample(
        context: _context(), id: '$i', recordedAt: _time, aimStability: 70, hits: 7, shots: 10)));
      expect(engine.compare(before, after).passed, isFalse);
    });
  });

  group('Hit registration and death diagnosis', () {
    test('absent evidence has INCONCLUSIVE cause', () {
      final diagnosis = HitRegistrationDiagnostics(guard).diagnose(HitEvidence());
      expect(diagnosis.cause, HitCause.inconclusive);
      expect(diagnosis.indicators, isEmpty);
    });
    test('reported ping and heat are separate indicators, not sensitivity blame', () {
      final diagnosis = HitRegistrationDiagnostics(guard).diagnose(
        HitEvidence(latencyMs: 140, jitterMs: 40, thermalSeverity: 4));
      expect(diagnosis.cause, HitCause.inconclusive);
      expect(diagnosis.indicators, containsAll([HitCause.networkLatency, HitCause.jitter, HitCause.thermalThrottling]));
      expect(diagnosis.hasPerformanceConfounder, isTrue);
      expect(diagnosis.indicators, isNot(contains(HitCause.aimMiss)));
    });
    test('unverified hit feedback does not prove desync or damage manipulation', () {
      final diagnosis = HitRegistrationDiagnostics(guard).diagnose(
        HitEvidence(visualHitFeedback: true, observedDamageResult: false));
      expect(diagnosis.cause, HitCause.inconclusive);
      expect(diagnosis.indicators, [HitCause.visualFeedbackMismatch]);
    });
    test('isolated reliably observed aim misses are identifiable', () {
      final diagnosis = HitRegistrationDiagnostics(guard).diagnose(HitEvidence(
        source: 'USER_VERIFIED_FRAME_REVIEW', reliableMeasurements: true,
        observedShots: 10, observedHits: 2, aimMisses: 8));
      expect(diagnosis.cause, HitCause.aimMiss);
    });
    test('conflicting measured signals remain inconclusive', () {
      final diagnosis = HitRegistrationDiagnostics(guard).diagnose(HitEvidence(
        reliableMeasurements: true, observedShots: 10, aimMisses: 5, latencyMs: 200));
      expect(diagnosis.cause, HitCause.inconclusive);
    });
    test('even reliable network and thermal signals do not prove a server cause', () {
      final engine = HitRegistrationDiagnostics(guard);
      expect(engine.diagnose(HitEvidence(reliableMeasurements: true, latencyMs: 200)).cause,
        HitCause.inconclusive);
      expect(engine.diagnose(HitEvidence(reliableMeasurements: true, thermalSeverity: 4)).cause,
        HitCause.inconclusive);
      expect(engine.diagnose(HitEvidence(observedShots: 10, aimMisses: 8)).cause,
        HitCause.inconclusive);
    });
    test('invalid shot labels and made-up percent ranges are rejected', () {
      expect(() => HitEvidence(observedShots: 5, aimMisses: 3, recoilMisses: 3), throwsArgumentError);
      expect(() => HitEvidence(packetLossPercent: 101), throwsArgumentError);
      expect(() => HitEvidence(aimMisses: 3), throwsArgumentError);
    });
    test('one death never creates sensitivity pattern', () {
      final report = DeathAnalysisEngine(guard).analyze([
        DeathObservation(id: 'd1', recordedAt: _time,
          observedCause: DeathCause.aimOvershoot, reliableEvidence: true),
      ]);
      expect(report.sensitivityPattern, isFalse);
      expect(report.primaryCause, DeathCause.inconclusive);
    });
    test('repeated tactical mistakes do not propose sensitivity', () {
      final report = DeathAnalysisEngine(guard).analyze(List.generate(5, (i) =>
        DeathObservation(id: '$i', recordedAt: _time,
          observedCause: DeathCause.poorPositioning, reliableEvidence: true)));
      expect(report.primaryCause, DeathCause.poorPositioning);
      expect(report.sensitivityPattern, isFalse);
    });
    test('environment confounder vetoes repeated overshoot sensitivity attribution', () {
      final report = DeathAnalysisEngine(guard).analyze(List.generate(5, (i) =>
        DeathObservation(id: '$i', recordedAt: _time,
          observedCause: DeathCause.aimOvershoot, reliableEvidence: true,
          hitEvidence: HitEvidence(latencyMs: 200))));
      expect(report.sensitivityPattern, isFalse);
    });
    test('user reports remain labeled inconclusive even when pattern repeats', () {
      final report = DeathAnalysisEngine(guard).analyze(List.generate(5, (i) =>
        DeathObservation(id: '$i', recordedAt: _time, observedCause: DeathCause.aimOvershoot)));
      expect(report.patterns[DeathCause.aimOvershoot], 5);
      expect(report.primaryCause, DeathCause.inconclusive);
      expect(report.sensitivityPattern, isFalse);
    });
  });

  group('movement and legal throwables calibration', () {
    test('incomplete movement tests return UNKNOWN score', () {
      final report = MovementCalibrationEngine(guard).analyze([
        MovementTrial(id: 'one', action: MovementAction.jump, successful: true, aimRetained: true)]);
      expect(report.spiderMovementScore, isNull);
      expect(report.sprintActivationReliability, isNull);
    });
    test('movement score derives from measured independent subtests', () {
      final trials = <MovementTrial>[];
      for (final action in [MovementAction.sprintActivation, MovementAction.directionChange, MovementAction.turn90]) {
        for (var i = 0; i < 3; i++) {
          trials.add(MovementTrial(id: '${action.name}$i', action: action,
            successful: true, aimRetained: true, turnErrorDegrees: 0));
        }
      }
      final report = MovementCalibrationEngine(guard).analyze(trials);
      expect(report.spiderMovementScore, 100);
      expect(report.accidentalSprintRate, 0);
    });
    test('throwable angles summarize only observed visible successful attempts', () {
      final report = ThrowablesCalibrationEngine(guard).analyze([
        _throw(1, angle: 10), _throw(2, angle: 20), _throw(3, angle: 30),
        _throw(4, angle: 80, landed: false), _throw(5, angle: 70, visible: false)]);
      expect(report.observedSuccessfulViewAngle, 20);
      expect(report.visibleTrajectoryUsability, 80);
    });
    test('trajectory unavailable means UNKNOWN, not vision through a rock', () {
      final report = ThrowablesCalibrationEngine(guard).analyze([
        _throw(1, visible: false, displayed: false)]);
      expect(report.visibleTrajectoryUsability, isNull);
      expect(report.observedSuccessfulViewAngle, isNull);
      expect(() => _throw(2, visible: true, displayed: false), throwsArgumentError);
    });
    test('mixing rock and window trials is rejected', () {
      expect(() => ThrowablesCalibrationEngine(guard).analyze([
        _throw(1), _throw(2, obstacle: ThrowableObstacle.window)]), throwsArgumentError);
    });
    test('only repeated Cook/Cancel problems produce practice guidance', () {
      final engine = ThrowablesCalibrationEngine(guard);
      expect(engine.analyze([_throw(1, cancel: false, cook: false)]).suggestions, isEmpty);
      expect(engine.analyze(List.generate(5, (i) => _throw(i, cancel: false, cook: false)))
        .suggestions.length, 2);
    });
  });

  group('battery policy preserves game quality', () {
    const engine = BatteryThermalIntelligence();
    test('critical heat stops only SPIDER work', () {
      final plan = engine.plan(safeOfflineSession: true, thermal: ThermalLevel.critical);
      expect(plan.workload, SpiderWorkload.stopped);
      expect(plan.changesGameFps, isFalse);
      expect(plan.changesGameGraphics, isFalse);
      expect(plan.changesDisplayRefreshRate, isFalse);
      expect(plan.changesTouchResponsiveness, isFalse);
    });
    test('own workload overload reduces analysis and defers heavy tasks', () {
      final plan = engine.plan(safeOfflineSession: true, thermal: ThermalLevel.nominal,
        ownWorkMilliseconds: 20, importantEvent: true);
      expect(plan.workload, SpiderWorkload.low);
      expect(plan.deferHeavyAnalysis, isTrue);
      expect(plan.pauseSecondaryTasks, isTrue);
      expect(plan.networkAllowed, isFalse);
    });
    test('computes full-device drain and CPU time without energy attribution', () {
      final report = engine.report([
        BatteryReading(at: _time, levelPercent: 80, charging: false, spiderCpuTimeMs: 100),
        BatteryReading(at: _time.add(const Duration(minutes: 30)), levelPercent: 70,
          charging: false, spiderCpuTimeMs: 18100),
      ]);
      expect(report.drainPerHour, 20);
      expect(report.spiderCpuCorePercent, 1);
      expect(report.spiderBatteryOverhead, isNull);
      expect(report.pubgEnergyUse, isNull);
      expect(report.pubgFpsStability, isNull);
    });
    test('charging and missing battery samples never produce fake drain rate', () {
      for (final charging in [true, null]) {
        final report = engine.report([
          BatteryReading(at: _time, levelPercent: 80, charging: charging),
          BatteryReading(at: _time.add(const Duration(minutes: 30)), levelPercent: 70, charging: false),
        ]);
        expect(report.drainPerHour, isNull);
      }
      final report = engine.report([
        BatteryReading(at: _time, charging: false),
        BatteryReading(at: _time.add(const Duration(minutes: 30)), levelPercent: 70, charging: false),
      ]);
      expect(report.drainPerHour, isNull);
    });
    test('short sessions and backwards readings are rejected or unknown', () {
      final report = engine.report([
        BatteryReading(at: _time, levelPercent: 80, charging: false),
        BatteryReading(at: _time.add(const Duration(seconds: 10)), levelPercent: 79, charging: false),
      ]);
      expect(report.drainPerHour, isNull);
      expect(() => engine.report([
        BatteryReading(at: _time), BatteryReading(at: _time.subtract(const Duration(seconds: 1))),
      ]), throwsArgumentError);
    });
    test('submillisecond CPU interval stays UNKNOWN instead of Infinity', () {
      final report = engine.report([
        BatteryReading(at: _time, spiderCpuTimeMs: 0),
        BatteryReading(at: _time.add(const Duration(microseconds: 1)), spiderCpuTimeMs: 1),
      ]);
      expect(report.spiderCpuCorePercent, isNull);
    });
    test('CPU arithmetic overflow is UNKNOWN instead of invented utilization', () {
      final report = engine.report([
        BatteryReading(at: _time, spiderCpuTimeMs: 0),
        BatteryReading(at: _time.add(const Duration(milliseconds: 1)), spiderCpuTimeMs: 1e308),
      ]);
      expect(report.spiderCpuCorePercent, isNull);
    });
  });

  group('landing is supplied-parameter geometry only', () {
    test('computes heading, reach and earliest future interval from supplied speeds', () {
      final plan = LandingAssistant(guard).plan(_landing());
      expect(plan.currentDistanceMeters, 1500);
      expect(plan.headingDegrees, 0);
      expect(plan.estimatedReachMeters, 1020);
      expect(plan.estimatedJumpInSeconds, closeTo(4.8, .0001));
      expect(plan.fastDiveAfterSeconds, 20);
      expect(plan.isLiveInstruction, isFalse);
    });
    test('target behind departing aircraft has no future reachable interval', () {
      final plan = LandingAssistant(guard).plan(_landing(north: -2000));
      expect(plan.reachable, isFalse);
      expect(plan.estimatedJumpInSeconds, isNull);
    });
    test('cross-track target outside measured range is unreachable', () {
      final plan = LandingAssistant(guard).plan(_landing(east: 2000));
      expect(plan.reachable, isFalse);
    });
    test('invalid unmeasured coordinates are rejected', () {
      expect(() => MapPosition(double.nan, 0), throwsArgumentError);
      expect(() => _landing(heading: 360), throwsArgumentError);
      expect(() => LandingAssistant(guard).plan(_landing(east: 1e308)), throwsArgumentError);
    });
  });
}
