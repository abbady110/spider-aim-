import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';

void main() {
  test('unknown is the fail-safe startup mode', () {
    final guard = GameModeGuard();
    expect(guard.mode, GameMode.unknownBlocked);
    expect(guard.allowed, isFalse);
    expect(guard.requireAllowed, throwsStateError);
  });

  test('only declared offline unranked contexts permit coaching', () {
    final guard = GameModeGuard();
    for (final mode in GameMode.values) {
      guard.declareOfflineMode(mode);
      final expected = {
        GameMode.safeUnranked,
        GameMode.training,
        GameMode.warehouse,
      }.contains(mode);
      expect(guard.allowed, expected, reason: mode.code);
      if (expected) {
        expect(guard.requireAllowed, returnsNormally);
      } else {
        expect(guard.requireAllowed, throwsStateError);
      }
    }
  });

  test('offline declaration never authorizes live capture or analysis', () {
    final guard = GameModeGuard();
    for (final mode in GameMode.values) {
      guard.declareOfflineMode(mode);
      expect(guard.liveAllowed, isFalse, reason: mode.code);
      expect(guard.requireLiveAllowed, throwsStateError);
    }
  });

  test('declaration expires exactly at twenty minutes and stays blocked', () {
    var now = DateTime.utc(2026, 10, 7);
    final guard = GameModeGuard(now: () => now);
    guard.declareOfflineMode(GameMode.warehouse);
    now = now.add(const Duration(minutes: 19, seconds: 59));
    expect(guard.allowed, isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(guard.mode, GameMode.unknownBlocked);
    expect(guard.requireAllowed, throwsStateError);
    now = now.add(const Duration(hours: 1));
    expect(guard.allowed, isFalse);
  });

  test('lifecycle invalidation revokes even an unexpired declaration', () {
    final guard = GameModeGuard()
      ..declareOfflineMode(GameMode.safeUnranked);
    guard.invalidate();
    expect(guard.mode, GameMode.unknownBlocked);
    expect(guard.allowed, isFalse);
    guard.declareOfflineMode(GameMode.training);
    expect(guard.allowed, isTrue);
  });
}
