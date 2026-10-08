import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/game_mode_recognition/recognition_models.dart';

/// Synthetic capture fixtures exercise the real recognition pipeline. They are
/// never included in the application and do not override guard decisions.
final recognitionFixtureTime = DateTime.utc(2026, 10, 8);

List<ScreenCue> safeScreenCues(GameMode mode, {double confidence = .99}) {
  final ids = switch (mode) {
    GameMode.trainingSafe => ['training_label', 'target_practice', 'training_controls'],
    GameMode.warehouseSafe => ['warehouse_label', 'score_hud', 'round_timer'],
    GameMode.arenaSafe => ['arena_label', 'tdm_label', 'score_hud', 'round_timer'],
    GameMode.safeUnranked => ['unranked_label', 'target_practice', 'training_controls'],
    _ => throw ArgumentError('A safe mode is required for positive fixtures.'),
  };
  return ids.map((id) => ScreenCue(id: id, confidence: confidence, region: 'top_hud')).toList();
}

ScreenFrameEvidence screenFrame({
  required String sessionId,
  required int sequence,
  required DateTime timestamp,
  required List<ScreenCue> cues,
  bool captureAuthorized = true,
  bool foregroundVerified = true,
  String? foregroundPackage = 'com.tencent.ig',
}) => ScreenFrameEvidence(
  sessionId: sessionId,
  sequence: sequence,
  frameFingerprint: 'synthetic-$sessionId-pixels-$sequence',
  timestamp: timestamp,
  captureAuthorized: captureAuthorized,
  foregroundPackage: foregroundPackage,
  foregroundVerified: foregroundVerified,
  cues: cues,
);

void observeSafeSession(GameModeGuard guard, {
  GameMode mode = GameMode.warehouseSafe,
  String sessionId = 'safe-capture-fixture',
  DateTime? now,
  double confidence = .99,
  int frames = 4,
  bool captureAuthorized = true,
  bool foregroundVerified = true,
}) {
  final at = now ?? recognitionFixtureTime;
  guard.stopCaptureSession();
  guard.beginCaptureSession(sessionId);
  for (var i = 0; i < frames; i++) {
    guard.observeFrame(screenFrame(
      sessionId: sessionId,
      sequence: i + 1,
      timestamp: at.subtract(Duration(seconds: 7 - i * 2)),
      captureAuthorized: captureAuthorized,
      foregroundVerified: foregroundVerified,
      cues: safeScreenCues(mode, confidence: confidence),
    ));
  }
}

GameModeGuard recognizedGuard({GameMode mode = GameMode.warehouseSafe}) {
  final guard = GameModeGuard(now: () => recognitionFixtureTime);
  observeSafeSession(guard, mode: mode);
  return guard;
}

void observeCompetitiveSession(GameModeGuard guard, {
  DateTime? now,
  String sessionId = 'competitive-capture-fixture',
}) {
  guard.beginCaptureSession(sessionId);
  guard.observeFrame(screenFrame(
    sessionId: sessionId,
    sequence: 1,
    timestamp: now ?? recognitionFixtureTime,
    cues: [ScreenCue(id: 'airplane', confidence: .99, region: 'center')],
  ));
}
