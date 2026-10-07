enum GameMode { safeUnranked, training, warehouse, rankedBlocked, unknownBlocked }

extension GameModeLabel on GameMode {
  String get code => switch (this) {
    GameMode.safeUnranked => 'SAFE_UNRANKED',
    GameMode.training => 'TRAINING',
    GameMode.warehouse => 'WAREHOUSE',
    GameMode.rankedBlocked => 'RANKED_BLOCKED',
    GameMode.unknownBlocked => 'UNKNOWN_BLOCKED',
  };
}

/// An offline session declaration is NOT verification of the active PUBG mode.
/// Live capture/analysis remains unavailable until a trusted integration exists.
class GameModeGuard {
  GameModeGuard({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  GameMode _mode = GameMode.unknownBlocked;
  DateTime? _declaredAt;
  GameMode get mode {
    if (_declaredAt != null &&
        _now().difference(_declaredAt!) >= const Duration(minutes: 20)) {
      invalidate();
    }
    return _mode;
  }
  bool get allowed => const {
    GameMode.safeUnranked, GameMode.training, GameMode.warehouse,
  }.contains(mode);
  bool get liveAllowed => false;
  void declareOfflineMode(GameMode value) {
    _mode = value;
    _declaredAt = _now();
  }
  void invalidate() {
    _mode = GameMode.unknownBlocked;
    _declaredAt = null;
  }
  void requireAllowed() {
    if (!allowed) {
      throw StateError('الوضع مصنف أو غير معروف. المراجعة متاحة لنتائج جلسة غير مصنفة فقط.');
    }
  }
  void requireLiveAllowed() {
    throw StateError('لا يوجد مصدر موثوق للتحقق من وضع PUBG؛ التحليل المباشر مقفول.');
  }
}
