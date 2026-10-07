import '../game_mode_guard/game_mode_guard.dart';

enum MovementAction {
  sprintActivation, directionChange, strafe, turn90, turn180,
  sprintToAds, stopToAds, jump, crouch, peek,
}

class MovementTrial {
  MovementTrial({required this.id, required this.action, required this.successful,
    required this.aimRetained, this.accidentalSprint = false,
    this.turnErrorDegrees, this.responseMs}) {
    if (id.trim().isEmpty) {
      throw ArgumentError('A trial ID is required.');
    }
    if (turnErrorDegrees != null && (!turnErrorDegrees!.isFinite ||
        turnErrorDegrees! < 0 || turnErrorDegrees! > 180)) {
      throw ArgumentError('Turn error must be in degrees from 0 to 180.');
    }
    if (responseMs != null && (!responseMs!.isFinite || responseMs! < 0)) {
      throw ArgumentError('Response time must be a nonnegative measurement.');
    }
  }
  final String id;
  final MovementAction action;
  final bool successful, aimRetained, accidentalSprint;
  final double? turnErrorDegrees, responseMs;
}

class MovementReport {
  MovementReport({required this.sampleCount, required this.spiderMovementScore,
    required this.sprintActivationReliability, required this.accidentalSprintRate,
    required this.directionChangeAccuracy, required this.turnOvershootDegrees,
    required this.aimRetention, required List<String> suggestions})
      : suggestions = List.unmodifiable(suggestions);
  final int sampleCount;
  final double? spiderMovementScore, sprintActivationReliability;
  final double accidentalSprintRate, aimRetention;
  final double? directionChangeAccuracy, turnOvershootDegrees;
  final List<String> suggestions;
}

class MovementCalibrationEngine {
  MovementCalibrationEngine(this.guard);
  final GameModeGuard guard;

  MovementReport analyze(List<MovementTrial> trials) {
    guard.requireAllowed();
    if (trials.isEmpty || trials.map((t) => t.id).toSet().length != trials.length) {
      throw ArgumentError('Supply independent, nonempty movement trials.');
    }
    final sprint = trials.where((t) => t.action == MovementAction.sprintActivation).toList();
    final direction = trials.where((t) => t.action == MovementAction.directionChange).toList();
    final turns = trials.where((t) => t.action == MovementAction.turn90 ||
      t.action == MovementAction.turn180).map((t) => t.turnErrorDegrees).whereType<double>().toList();
    double? success(List<MovementTrial> items) => items.isEmpty ? null :
      items.where((t) => t.successful).length / items.length * 100;
    final sprintRate = success(sprint);
    final directionRate = success(direction);
    final aim = trials.where((t) => t.aimRetained).length / trials.length * 100;
    final accidental = trials.where((t) => t.accidentalSprint).length / trials.length * 100;
    final turnError = turns.isEmpty ? null : turns.reduce((a, b) => a + b) / turns.length;
    // Descriptive score only: equal weight reliability, direction, aim retention,
    // intentional sprint control and turn precision. Missing subtest => UNKNOWN.
    final complete = sprint.length >= 3 && direction.length >= 3 && turns.length >= 3;
    final score = complete ? (sprintRate! + directionRate! + aim +
      (100 - accidental) + (100 * (1 - turnError! / 180))) / 5 : null;
    final suggestions = <String>[];
    if (sprint.length >= 3 && sprintRate! < 80) {
      suggestions.add('اختبر موضع وحجم عصا الحركة وتفعيل الركض في إعدادات PUBG الرسمية.');
    }
    if (trials.length >= 5 && accidental >= 20) {
      suggestions.add('تكرر الركض العرضي؛ جرّب موضعًا أو حجمًا مختلفًا لعصا الحركة بعد Backup وموافقة.');
    }
    if (trials.length >= 5 && aim < 80) {
      suggestions.add('اختبر ترتيب أزرار Peek وADS وثبات التصويب أثناء الحركة قبل تغيير الحساسية.');
    }
    return MovementReport(sampleCount: trials.length, spiderMovementScore: score,
      sprintActivationReliability: sprintRate, accidentalSprintRate: accidental,
      directionChangeAccuracy: directionRate, turnOvershootDegrees: turnError,
      aimRetention: aim, suggestions: suggestions);
  }
}
