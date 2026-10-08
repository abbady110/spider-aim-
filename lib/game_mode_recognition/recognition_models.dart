import '../game_mode_guard/game_mode.dart';

/// Cues describe evidence extracted from authorized screen pixels, never a
/// player's declaration. The native capture bridge supplies these values.
class ScreenCueId {
  static const trainingLabel = 'training_label';
  static const warehouseLabel = 'warehouse_label';
  static const arenaLabel = 'arena_label';
  static const tdmLabel = 'tdm_label';
  static const unrankedLabel = 'unranked_label';
  static const scoreHud = 'score_hud';
  static const targetPractice = 'target_practice';
  static const trainingControls = 'training_controls';
  static const respawnCountdown = 'respawn_countdown';
  static const respawnTransition = 'respawn_transition';
  static const roundTimer = 'round_timer';
  static const airplane = 'airplane';
  static const flightPath = 'flight_path';
  static const jump = 'jump';
  static const follow = 'follow';
  static const freeFall = 'free_fall';
  static const parachute = 'parachute';
  static const brMap = 'br_map';
  static const rankedLabel = 'ranked_label';
}

class ScreenCue {
  const ScreenCue({
    required this.id,
    required this.confidence,
    required this.region,
  });

  final String id;
  final double confidence;
  final String region;

  bool get valid =>
      id.isNotEmpty &&
      region.isNotEmpty &&
      confidence.isFinite &&
      confidence >= 0 &&
      confidence <= 1;
}

class ScreenFrameEvidence {
  ScreenFrameEvidence({
    required this.sessionId,
    required this.sequence,
    required this.timestamp,
    required this.captureAuthorized,
    required this.foregroundPackage,
    required this.foregroundVerified,
    required this.frameFingerprint,
    required List<ScreenCue> cues,
    this.error,
  }) : cues = List.unmodifiable(cues);

  /// Invalid/malformed bridge messages become blocked evidence. Parsing never
  /// manufactures confidence, permissions, a package name, or a timestamp.
  factory ScreenFrameEvidence.fromJson(Map<Object?, Object?> json) {
    var malformed = json['type'] != 'frame';
    final cues = <ScreenCue>[];
    final rawCues = json['cues'];
    if (rawCues is List) {
      for (final raw in rawCues) {
        if (raw is! Map ||
            raw['id'] is! String ||
            raw['region'] is! String ||
            raw['confidence'] is! num) {
          malformed = true;
          continue;
        }
        final cue = ScreenCue(
          id: raw['id'] as String,
          confidence: (raw['confidence'] as num).toDouble(),
          region: raw['region'] as String,
        );
        if (!cue.valid) malformed = true;
        cues.add(cue);
      }
    } else {
      malformed = true;
    }
    final rawTimestamp = json['timestampMs'];
    final rawSequence = json['sequence'];
    final rawSession = json['sessionId'];
    final rawFingerprint = json['frameFingerprint'];
    DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (rawTimestamp is int && rawTimestamp > 0) {
      try {
        timestamp = DateTime.fromMillisecondsSinceEpoch(
          rawTimestamp,
          isUtc: true,
        );
      } on ArgumentError {
        malformed = true;
      }
    } else {
      malformed = true;
    }
    if (rawSequence is! int || rawSequence < 0) malformed = true;
    if (rawSession is! String || rawSession.isEmpty) malformed = true;
    if (rawFingerprint is! String || rawFingerprint.isEmpty) malformed = true;
    final rawError = json['error'];
    if (rawError != null && rawError is! String) malformed = true;
    return ScreenFrameEvidence(
      sessionId: rawSession is String ? rawSession : '',
      sequence: rawSequence is int ? rawSequence : -1,
      timestamp: timestamp,
      captureAuthorized: json['captureAuthorized'] == true,
      foregroundPackage: json['foregroundPackage'] is String
          ? json['foregroundPackage'] as String
          : null,
      foregroundVerified: json['foregroundVerified'] == true,
      frameFingerprint: rawFingerprint is String ? rawFingerprint : '',
      cues: cues,
      error: malformed
          ? 'malformed_frame_evidence'
          : rawError as String?,
    );
  }

  final String sessionId;
  final int sequence;
  final DateTime timestamp;
  final bool captureAuthorized;
  final String? foregroundPackage;
  final bool foregroundVerified;
  /// Native sample hash of screen pixels. It must not be an event counter.
  final String frameFingerprint;
  final List<ScreenCue> cues;
  final String? error;
  int get timestampMs => timestamp.millisecondsSinceEpoch;
}

/// Confidence is a conservative heuristic evidence score. It has not been
/// empirically calibrated as the probability that PUBG is in the given mode.
class RecognitionDecision {
  RecognitionDecision({
    required this.mode,
    required this.confidence,
    required List<String> evidence,
    required this.lastVerified,
    required this.sessionId,
    required this.frameCount,
  }) : evidence = List.unmodifiable(evidence);

  final GameMode mode;
  final double confidence;
  final List<String> evidence;
  final DateTime? lastVerified;
  final String? sessionId;
  final int frameCount;

  bool get allowed => switch (mode) {
    GameMode.trainingSafe ||
    GameMode.warehouseSafe ||
    GameMode.arenaSafe ||
    GameMode.safeUnranked => true,
    GameMode.competitiveBlocked || GameMode.unknownBlocked => false,
  };
}
