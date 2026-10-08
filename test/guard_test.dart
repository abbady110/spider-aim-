import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/game_mode_recognition/recognition_models.dart';

import 'support/recognized_guard.dart';

void main() {
  test('unknown is the fail-safe startup mode', () {
    final guard = GameModeGuard(now: () => recognitionFixtureTime);
    expect(guard.mode, GameMode.unknownBlocked);
    expect(guard.allowed, isFalse);
    expect(guard.liveAllowed, isFalse);
    expect(guard.requireAllowed, throwsStateError);
    expect(guard.requireLiveAllowed, throwsStateError);
  });

  test('no manual declaration can unlock unknown even when capture has started', () {
    final guard = GameModeGuard(now: () => recognitionFixtureTime);
    for (final withCapture in [false, true]) {
      if (withCapture) {
        guard.beginCaptureSession('manual-cannot-verify');
      }
      for (final mode in GameMode.values) {
        guard.declareOfflineMode(mode);
        expect(guard.mode, GameMode.unknownBlocked, reason: mode.code);
        expect(guard.allowed, isFalse);
        expect(guard.liveAllowed, isFalse);
        expect(guard.requireAllowed, throwsStateError);
        expect(guard.requireLiveAllowed, throwsStateError);
      }
    }
  });

  test('manual safe declarations cannot clear automatically recognized competition', () {
    final guard = GameModeGuard(now: () => recognitionFixtureTime);
    observeCompetitiveSession(guard);
    expect(guard.mode, GameMode.competitiveBlocked);
    for (final mode in GameMode.values) {
      guard.declareOfflineMode(mode);
      expect(guard.mode, GameMode.competitiveBlocked, reason: mode.code);
      expect(guard.allowed, isFalse);
      expect(guard.liveAllowed, isFalse);
      expect(guard.requireAllowed, throwsStateError);
    }
  });

  test('four independent trusted frames unlock only recognized safe modes', () {
    for (final mode in [GameMode.trainingSafe, GameMode.warehouseSafe,
      GameMode.arenaSafe, GameMode.safeUnranked]) {
      final guard = recognizedGuard(mode: mode);
      expect(guard.mode, mode);
      expect(guard.allowed, isTrue);
      expect(guard.liveAllowed, isTrue);
      expect(guard.requireAllowed, returnsNormally);
      expect(guard.requireLiveAllowed, returnsNormally);
    }
  });

  test('single frame, low confidence or unauthorized capture cannot unlock', () {
    for (final frames in [1, 2, 3]) {
      final guard = GameModeGuard(now: () => recognitionFixtureTime);
      observeSafeSession(guard, frames: frames);
      expect(guard.allowed, isFalse);
    }
    for (final confidence in [0.0, .7, .94]) {
      final guard = GameModeGuard(now: () => recognitionFixtureTime);
      observeSafeSession(guard, confidence: confidence);
      expect(guard.allowed, isFalse);
    }
    for (final captureAuthorized in [false, true]) {
      final guard = GameModeGuard(now: () => recognitionFixtureTime);
      observeSafeSession(guard, captureAuthorized: captureAuthorized,
        foregroundVerified: false);
      expect(guard.allowed, isFalse);
    }
    final unauthorized = GameModeGuard(now: () => recognitionFixtureTime);
    observeSafeSession(unauthorized, captureAuthorized: false);
    expect(unauthorized.allowed, isFalse);
  });

  test('even convincing frames are rejected without an active capture session', () {
    final guard = GameModeGuard(now: () => recognitionFixtureTime);
    for (var i = 0; i < 4; i++) {
      guard.observeFrame(screenFrame(
        sessionId: 'not-an-active-session', sequence: i + 1,
        timestamp: recognitionFixtureTime.subtract(Duration(seconds: 7 - i * 2)),
        cues: safeScreenCues(GameMode.warehouseSafe),
      ));
    }
    expect(guard.mode, GameMode.unknownBlocked);
    expect(guard.requireAllowed, throwsStateError);
    expect(guard.requireLiveAllowed, throwsStateError);
  });

  test('recognized permission expires when evidence is no longer fresh', () {
    var now = recognitionFixtureTime;
    final guard = GameModeGuard(now: () => now);
    observeSafeSession(guard, now: now);
    expect(guard.allowed, isTrue);
    now = now.add(const Duration(seconds: 13));
    expect(guard.mode, GameMode.unknownBlocked);
    expect(guard.requireAllowed, throwsStateError);
    expect(guard.requireLiveAllowed, throwsStateError);
    guard.declareOfflineMode(GameMode.warehouseSafe);
    expect(guard.allowed, isFalse);
  });

  test('stopping capture or lifecycle invalidation revokes a safe decision', () {
    for (final stopCapture in [false, true]) {
      final guard = recognizedGuard();
      if (stopCapture) {
        guard.stopCaptureSession();
      } else {
        guard.invalidate();
      }
      expect(guard.mode, GameMode.unknownBlocked);
      expect(guard.allowed, isFalse);
      expect(guard.liveAllowed, isFalse);
      guard.declareOfflineMode(GameMode.trainingSafe);
      expect(guard.allowed, isFalse);
    }
  });

  test('competitive visual evidence immediately revokes a recognized safe session', () {
    final guard = recognizedGuard();
    guard.observeFrame(screenFrame(
      sessionId: 'safe-capture-fixture', sequence: 5,
      timestamp: recognitionFixtureTime,
      cues: [ScreenCue(id: 'airplane', confidence: .99, region: 'center')],
    ));
    expect(guard.mode, GameMode.competitiveBlocked);
    expect(guard.requireAllowed, throwsStateError);
    expect(guard.requireLiveAllowed, throwsStateError);
  });
}
