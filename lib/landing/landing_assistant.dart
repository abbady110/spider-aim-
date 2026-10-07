import 'dart:math' as math;

import '../game_mode_guard/game_mode_guard.dart';

class MapPosition {
  MapPosition(this.eastMeters, this.northMeters) {
    if (!eastMeters.isFinite || !northMeters.isFinite) {
      throw ArgumentError('Map positions must be finite measured coordinates.');
    }
  }
  final double eastMeters, northMeters;
}

class LandingInput {
  LandingInput({required this.aircraft, required this.target,
    required this.aircraftHeadingDegrees, required this.aircraftSpeedMetersPerSecond,
    required this.measuredGlideMetersPerSecond, required this.measuredDescentMetersPerSecond,
    required this.altitudeMeters, required this.fastDiveStartAltitudeMeters,
    required this.measuredDiveHorizontalMetersPerSecond,
    required this.measuredDiveDescentMetersPerSecond}) {
    for (final value in [aircraftHeadingDegrees, aircraftSpeedMetersPerSecond,
      measuredGlideMetersPerSecond, measuredDescentMetersPerSecond,
      altitudeMeters, fastDiveStartAltitudeMeters,
      measuredDiveHorizontalMetersPerSecond, measuredDiveDescentMetersPerSecond]) {
      if (!value.isFinite || value < 0) {
        throw ArgumentError('Measured parameters must be finite and nonnegative.');
      }
    }
    if (aircraftHeadingDegrees >= 360 || aircraftSpeedMetersPerSecond <= 0 ||
        measuredDescentMetersPerSecond <= 0 || measuredDiveDescentMetersPerSecond <= 0 ||
        altitudeMeters <= 0 || fastDiveStartAltitudeMeters > altitudeMeters) {
      throw ArgumentError('Supply valid heading, speeds and dive altitude.');
    }
  }
  final MapPosition aircraft, target;
  final double aircraftHeadingDegrees, aircraftSpeedMetersPerSecond;
  final double measuredGlideMetersPerSecond, measuredDescentMetersPerSecond;
  final double altitudeMeters, fastDiveStartAltitudeMeters;
  final double measuredDiveHorizontalMetersPerSecond, measuredDiveDescentMetersPerSecond;
}

class LandingPlan {
  const LandingPlan({required this.currentDistanceMeters,
    required this.headingDegrees, required this.estimatedJumpInSeconds,
    required this.estimatedGlideAngleDegrees, required this.fastDiveAfterSeconds,
    required this.fastDiveStartAltitudeMeters, required this.estimatedReachMeters,
    required this.reachable, required this.explanation});
  final double currentDistanceMeters, headingDegrees, estimatedGlideAngleDegrees;
  final double? estimatedJumpInSeconds;
  final double fastDiveAfterSeconds, fastDiveStartAltitudeMeters, estimatedReachMeters;
  final bool reachable;
  final String explanation;
  // No live mode/map verification is available. Never emit a live JUMP NOW cue.
  bool get isLiveInstruction => false;
}

class LandingAssistant {
  LandingAssistant(this.guard);
  final GameModeGuard guard;

  /// Constant-speed geometry using only the user's measured parameters.
  /// It is a retrospective training estimate, not PUBG physics or an autopilot.
  LandingPlan plan(LandingInput input) {
    guard.requireAllowed();
    final dx = input.target.eastMeters - input.aircraft.eastMeters;
    final dy = input.target.northMeters - input.aircraft.northMeters;
    final distance = math.sqrt(dx * dx + dy * dy);
    final heading = (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
    final glideTime = (input.altitudeMeters - input.fastDiveStartAltitudeMeters) /
      input.measuredDescentMetersPerSecond;
    final diveTime = input.fastDiveStartAltitudeMeters / input.measuredDiveDescentMetersPerSecond;
    final reach = input.measuredGlideMetersPerSecond * glideTime +
      input.measuredDiveHorizontalMetersPerSecond * diveTime;
    final headingRadians = input.aircraftHeadingDegrees * math.pi / 180;
    final ux = math.sin(headingRadians);
    final uy = math.cos(headingRadians);
    final alongTrack = dx * ux + dy * uy;
    final crossTrackSquared = math.max(0.0, distance * distance - alongTrack * alongTrack);
    final reachSquared = reach * reach;
    if (![dx, dy, distance, heading, glideTime, diveTime, reach,
        alongTrack, crossTrackSquared, reachSquared].every((value) => value.isFinite)) {
      throw ArgumentError('Coordinates or measurements exceed a finite calculation range.');
    }
    double? jumpSeconds;
    if (distance <= reach) {
      jumpSeconds = 0;
    } else if (crossTrackSquared <= reachSquared) {
      final earliest = alongTrack - math.sqrt(reachSquared - crossTrackSquared);
      final latest = alongTrack + math.sqrt(reachSquared - crossTrackSquared);
      if (latest >= 0) {
        jumpSeconds = math.max(0, earliest) / input.aircraftSpeedMetersPerSecond;
      }
    }
    if (jumpSeconds != null && !jumpSeconds.isFinite) {
      throw ArgumentError('Aircraft speed is too small for a finite estimate.');
    }
    return LandingPlan(currentDistanceMeters: distance, headingDegrees: heading,
      estimatedJumpInSeconds: jumpSeconds,
      estimatedGlideAngleDegrees: math.atan2(input.measuredDescentMetersPerSecond,
        input.measuredGlideMetersPerSecond) * 180 / math.pi,
      fastDiveAfterSeconds: glideTime, fastDiveStartAltitudeMeters: input.fastDiveStartAltitudeMeters,
      estimatedReachMeters: reach, reachable: jumpSeconds != null,
      explanation: 'تقدير تدريب من الإحداثيات والسرعات التي أدخلتها؛ يتجاهل تغير السرعة والتضاريس وفتح المظلة. '
        'لا نعرف أفضل نقطة داخل المنطقة أو فيزياء PUBG الفعلية دون قياساتك.');
  }
}
