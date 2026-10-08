enum GameMode {
  trainingSafe,
  warehouseSafe,
  arenaSafe,
  safeUnranked,
  competitiveBlocked,
  unknownBlocked,
}

extension GameModeCode on GameMode {
  String get code => switch (this) {
    GameMode.trainingSafe => 'TRAINING_SAFE',
    GameMode.warehouseSafe => 'WAREHOUSE_SAFE',
    GameMode.arenaSafe => 'ARENA_SAFE',
    GameMode.safeUnranked => 'SAFE_UNRANKED',
    GameMode.competitiveBlocked => 'COMPETITIVE_BLOCKED',
    GameMode.unknownBlocked => 'UNKNOWN_BLOCKED',
  };
}
