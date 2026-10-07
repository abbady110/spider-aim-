import '../game_mode_guard/game_mode_guard.dart';

enum ThrowableObstacle { rock, wall, barrier, window, edge }

class ThrowableTrial {
  ThrowableTrial({required this.id, required this.obstacle,
    required this.landedAsIntended, required this.trajectoryVisible,
    required this.gameDisplaysTrajectory, required this.peekReady,
    required this.cancelSucceeded, required this.cookTimingSuccessful,
    this.viewAngleDegrees, this.officialSettingsOnly = true}) {
    if (id.trim().isEmpty) {
      throw ArgumentError('A trial ID is required.');
    }
    if (!officialSettingsOnly) {
      throw ArgumentError('Only official, visible in-game controls are supported.');
    }
    if (trajectoryVisible && !gameDisplaysTrajectory) {
      throw ArgumentError('A trajectory cannot be visible if the game does not display it.');
    }
    if (viewAngleDegrees != null && (!viewAngleDegrees!.isFinite ||
        viewAngleDegrees! < -90 || viewAngleDegrees! > 90)) {
      throw ArgumentError('Supply a measured view angle from -90 to 90 degrees.');
    }
  }
  final String id;
  final ThrowableObstacle obstacle;
  final bool landedAsIntended, trajectoryVisible, gameDisplaysTrajectory;
  final bool peekReady, cancelSucceeded, cookTimingSuccessful, officialSettingsOnly;
  final double? viewAngleDegrees;
}

class ThrowableReport {
  ThrowableReport({required this.obstacle, required this.sampleCount,
    required this.successRate, required this.visibleTrajectoryUsability,
    required this.observedSuccessfulViewAngle, required List<String> suggestions})
      : suggestions = List.unmodifiable(suggestions);
  final ThrowableObstacle obstacle;
  final int sampleCount;
  final double successRate;
  final double? visibleTrajectoryUsability, observedSuccessfulViewAngle;
  final List<String> suggestions;
}

class ThrowablesCalibrationEngine {
  ThrowablesCalibrationEngine(this.guard);
  final GameModeGuard guard;

  ThrowableReport analyze(List<ThrowableTrial> trials) {
    guard.requireAllowed();
    if (trials.isEmpty || trials.map((t) => t.id).toSet().length != trials.length) {
      throw ArgumentError('Supply independent throwable trials.');
    }
    if (trials.any((t) => t.obstacle != trials.first.obstacle)) {
      throw ArgumentError('Keep separate profiles for rocks, walls, barriers, windows and edges.');
    }
    final visible = trials.where((t) => t.gameDisplaysTrajectory).toList();
    final angles = trials.where((t) => t.landedAsIntended && t.trajectoryVisible)
      .map((t) => t.viewAngleDegrees).whereType<double>().toList()..sort();
    // This is an observed angle, not a predicted trajectory through a barrier.
    final successfulAngle = angles.length < 3 ? null : angles.length.isOdd ?
      angles[angles.length ~/ 2] : (angles[angles.length ~/ 2 - 1] + angles[angles.length ~/ 2]) / 2;
    final suggestions = <String>[];
    if (trials.length >= 5) {
      if (visible.where((t) => !t.trajectoryVisible).length >= 3) {
        suggestions.add('اختبر زاوية الكاميرا وPeek/Lean حتى يظهر المسار الذي تعرضه اللعبة؛ لا يمكن رؤية ما خلف الحاجز.');
      }
      if (trials.where((t) => !t.cancelSucceeded).length >= 3) {
        suggestions.add('اختبر موضع وحجم زر إلغاء الرمي لمنع الضغط غير المقصود.');
      }
      if (trials.where((t) => !t.cookTimingSuccessful).length >= 3) {
        suggestions.add('تدرّب على Hold / Cook / Cancel وتوقيت الرمي في Training؛ لا يوجد توقيت أو رمي آلي.');
      }
      if (trials.where((t) => !t.peekReady).length >= 3) {
        suggestions.add('اختبر ترتيب زر Peek/Lean مع زر الرمي وزاوية النظر ضمن مجال الرؤية الرسمي.');
      }
    }
    return ThrowableReport(obstacle: trials.first.obstacle, sampleCount: trials.length,
      successRate: trials.where((t) => t.landedAsIntended).length / trials.length * 100,
      visibleTrajectoryUsability: visible.isEmpty ? null :
        visible.where((t) => t.trajectoryVisible).length / visible.length * 100,
      observedSuccessfulViewAngle: successfulAngle, suggestions: suggestions);
  }
}
