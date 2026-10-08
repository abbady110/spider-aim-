import '../game_mode_recognition/automatic_mode_recognizer.dart';
import '../game_mode_recognition/recognition_models.dart';
import 'game_mode.dart';

export 'game_mode.dart';

/// Sole authorization boundary. A mode choice never grants permission: only
/// fresh, multi-frame evidence from an authorized native capture can unlock.
class GameModeGuard {
  GameModeGuard({DateTime Function()? now, AutomaticModeRecognizer? recognizer})
    : _recognizer = recognizer ?? AutomaticModeRecognizer(now: now);

  final AutomaticModeRecognizer _recognizer;
  RecognitionDecision get recognition => _recognizer.decision;
  GameMode get mode => recognition.mode;
  bool get allowed => recognition.allowed;
  bool get liveAllowed => allowed;
  bool get competitiveLatched => _recognizer.battleRoyaleLatched;

  /// Called by the capture controller after official screen consent succeeds.
  void beginCaptureSession(String id) => _recognizer.beginSession(id);
  RecognitionDecision observeFrame(ScreenFrameEvidence frame) =>
      _recognizer.ingest(frame);
  void stopCaptureSession() => _recognizer.stopSession();
  void invalidate() => stopCaptureSession();
  void invalidateEvidence(String reason) => _recognizer.invalidateEvidence(reason);

  /// Legacy callers cannot override UNKNOWN or COMPETITIVE. Kept as a no-op
  /// so this invariant remains explicit and regression-testable.
  void declareOfflineMode(GameMode mode) {}

  void requireAllowed([String operation = 'العملية']) {
    if (!allowed) {
      throw StateError('$operation مقفول: ${mode.code}. يلزم تحقق تلقائي حديث '
          'من وضع آمن، وليس تصريحًا يدويًا.');
    }
  }

  void requireLiveAllowed([String operation = 'التحليل المباشر']) =>
      requireAllowed(operation);
}
