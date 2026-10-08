import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/game_mode_guard/game_mode.dart';
import 'package:spider_aim/game_mode_recognition/automatic_mode_recognizer.dart';
import 'package:spider_aim/game_mode_recognition/recognition_models.dart';

void main() {
  late DateTime now;
  late AutomaticModeRecognizer recognizer;

  setUp(() {
    now = DateTime.utc(2026, 10, 8, 12);
    recognizer = AutomaticModeRecognizer(now: () => now)
      ..beginSession('native-session');
  });

  ScreenFrameEvidence frame({
    int sequence = 1,
    DateTime? timestamp,
    List<ScreenCue>? cues,
    String session = 'native-session',
    bool authorized = true,
    bool foregroundVerified = true,
    String? package = 'com.tencent.ig',
    String? error,
    String? fingerprint,
  }) => ScreenFrameEvidence(
    sessionId: session,
    sequence: sequence,
    timestamp: timestamp ?? now,
    captureAuthorized: authorized,
    foregroundPackage: package,
    foregroundVerified: foregroundVerified,
    frameFingerprint: fingerprint ?? 'actual-test-pixels-$sequence',
    cues: cues ?? _warehouseCues,
    error: error,
  );

  RecognitionDecision recognizeSafe({List<ScreenCue>? cues}) {
    for (var index = 0; index < 4; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 6 - 2 * index)),
        cues: cues,
      ));
    }
    return recognizer.decision;
  }

  test('startup and capture lifecycle fail closed', () {
    expect(AutomaticModeRecognizer().decision.allowed, isFalse);
    expect(recognizer.decision.mode, GameMode.unknownBlocked);
    expect(recognizer.decision.frameCount, 0);
    recognizeSafe();
    recognizer.stopSession();
    expect(recognizer.decision.mode, GameMode.unknownBlocked);
    expect(recognizer.decision.sessionId, isNull);
  });

  test('one perfect Warehouse screenshot never unlocks calibration', () {
    final decision = recognizer.ingest(frame());
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.allowed, isFalse);
    expect(decision.frameCount, 1);
    expect(decision.confidence, 0);
  });

  test('four strong distinct frames spanning six seconds recognize Warehouse', () {
    final decision = recognizeSafe();
    expect(decision.mode, GameMode.warehouseSafe);
    expect(decision.allowed, isTrue);
    expect(decision.confidence, closeTo(.99, .000001));
    expect(decision.lastVerified, now);
    expect(decision.frameCount, 4);
    expect(decision.evidence, contains('واجهة نقاط الفريقين'));
    expect(decision.evidence, contains('مؤقت الجولة'));
  });

  test('four frames in three seconds remain blocked', () {
    for (var index = 0; index < 4; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 3 - index)),
      ));
    }
    expect(recognizer.decision.mode, GameMode.unknownBlocked);
    expect(recognizer.decision.confidence, closeTo(.495, .000001));
  });

  test('three frames over six seconds are not enough', () {
    for (var index = 0; index < 3; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 6 - 3 * index)),
      ));
    }
    expect(recognizer.decision.allowed, isFalse);
    expect(recognizer.decision.frameCount, 3);
  });

  test('the twelve-second window cannot reuse an expired early sample', () {
    for (var index = 0; index < 4; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 12 - 4 * index)),
      ));
    }
    expect(recognizer.decision.allowed, isFalse);
    expect(recognizer.decision.frameCount, 3);
  });

  test('an evidence frame never creates its own trusted capture session', () {
    recognizer.stopSession();
    expect(recognizer.ingest(frame()).allowed, isFalse);
    expect(recognizer.decision.sessionId, isNull);
  });

  test('Warehouse word alone cannot recognize safe mode', () {
    recognizeSafe(cues: [_cue(ScreenCueId.warehouseLabel)]);
    expect(recognizer.decision.allowed, isFalse);
  });

  test('a countdown is not proof of a respawn transition', () {
    recognizeSafe(cues: [
      _cue(ScreenCueId.warehouseLabel),
      _cue(ScreenCueId.respawnCountdown),
    ]);
    expect(recognizer.decision.allowed, isFalse);
  });

  test('actual respawn transitions corroborate Warehouse', () {
    final decision = recognizeSafe(cues: [
      _cue(ScreenCueId.warehouseLabel),
      _cue(ScreenCueId.respawnTransition),
    ]);
    expect(decision.mode, GameMode.warehouseSafe);
    expect(decision.allowed, isTrue);
  });

  test('Training needs its label and independent training activity', () {
    final decision = recognizeSafe(cues: [
      _cue(ScreenCueId.trainingLabel),
      _cue(ScreenCueId.targetPractice),
    ]);
    expect(decision.mode, GameMode.trainingSafe);
    expect(decision.allowed, isTrue);
  });

  test('TDM identifies Arena with points and timer HUD', () {
    final decision = recognizeSafe(cues: [
      _cue(ScreenCueId.tdmLabel),
      _cue(ScreenCueId.scoreHud),
      _cue(ScreenCueId.roundTimer),
    ]);
    expect(decision.mode, GameMode.arenaSafe);
    expect(decision.allowed, isTrue);
  });

  test('Warehouse and generic TDM labels are a valid mode hierarchy', () {
    final decision = recognizeSafe(cues: [
      ..._warehouseCues,
      _cue(ScreenCueId.tdmLabel),
    ]);
    expect(decision.mode, GameMode.warehouseSafe);
    expect(decision.allowed, isTrue);
  });

  test('explicit Unranked still requires non-BR activity proof', () {
    recognizeSafe(cues: [_cue(ScreenCueId.unrankedLabel)]);
    expect(recognizer.decision.allowed, isFalse);
    recognizer = AutomaticModeRecognizer(now: () => now)
      ..beginSession('native-session');
    final decision = recognizeSafe(cues: [
      _cue(ScreenCueId.unrankedLabel),
      _cue(ScreenCueId.targetPractice),
      _cue(ScreenCueId.trainingControls),
    ]);
    expect(decision.mode, GameMode.safeUnranked);
    expect(decision.allowed, isTrue);
  });

  test('conflicting training and combat mode labels revoke a safe session', () {
    recognizeSafe();
    now = now.add(const Duration(seconds: 2));
    final decision = recognizer.ingest(frame(
      sequence: 5,
      cues: [..._warehouseCues, _cue(ScreenCueId.trainingLabel)],
    ));
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.allowed, isFalse);
  });

  test('a safe mode change requires a fresh multi-frame confirmation', () {
    recognizeSafe();
    now = now.add(const Duration(seconds: 2));
    final decision = recognizer.ingest(frame(
      sequence: 5,
      cues: [_cue(ScreenCueId.trainingLabel), _cue(ScreenCueId.targetPractice)],
    ));
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.frameCount, 1);
  });

  for (final hazard in [
    ScreenCueId.airplane,
    ScreenCueId.flightPath,
    ScreenCueId.jump,
    ScreenCueId.follow,
    ScreenCueId.freeFall,
    ScreenCueId.parachute,
    ScreenCueId.brMap,
    ScreenCueId.rankedLabel,
  ]) {
    test('$hazard immediately locks even an already safe session', () {
      recognizeSafe();
      now = now.add(const Duration(seconds: 2));
      final decision = recognizer.ingest(frame(
        sequence: 5,
        cues: [..._warehouseCues, _cue(hazard, .80)],
      ));
      expect(decision.mode, GameMode.competitiveBlocked);
      expect(decision.allowed, isFalse);
    });
  }

  test('competitive evidence latches across later safe-looking frames', () {
    recognizer.ingest(frame(cues: [_cue(ScreenCueId.airplane, .9)]));
    for (var index = 2; index <= 8; index++) {
      now = now.add(const Duration(seconds: 2));
      recognizer.ingest(frame(sequence: index));
    }
    expect(recognizer.decision.mode, GameMode.competitiveBlocked);
    recognizer.beginSession('native-session');
    expect(recognizer.decision.mode, GameMode.competitiveBlocked);
    now = now.add(const Duration(hours: 1));
    expect(recognizer.decision.mode, GameMode.competitiveBlocked);
  });

  test('a genuinely new native capture session begins blocked', () {
    recognizer.ingest(frame(cues: [_cue(ScreenCueId.parachute)]));
    recognizer.stopSession();
    recognizer.beginSession('new-native-session');
    expect(recognizer.decision.mode, GameMode.unknownBlocked);
    expect(recognizer.decision.allowed, isFalse);
    expect(recognizer.decision.lastVerified, isNull);
  });

  test('ambiguous BR evidence revokes safety without claiming certainty', () {
    recognizeSafe();
    now = now.add(const Duration(seconds: 2));
    final decision = recognizer.ingest(frame(
      sequence: 5,
      cues: [..._warehouseCues, _cue(ScreenCueId.airplane, .70)],
    ));
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.allowed, isFalse);
  });

  test('no-BR absence never contributes positive evidence or confidence', () {
    for (var index = 0; index < 4; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 6 - 2 * index)),
        cues: const [],
      ));
    }
    expect(recognizer.decision.allowed, isFalse);
    expect(recognizer.decision.confidence, 0);
  });

  test('confidence uses weakest proof, not a fabricated percentage', () {
    final decision = recognizeSafe(cues: [
      _cue(ScreenCueId.warehouseLabel, .99),
      _cue(ScreenCueId.scoreHud, .96),
      _cue(ScreenCueId.roundTimer, .98),
    ]);
    expect(decision.confidence, closeTo(.96, .000001));
    expect(decision.allowed, isTrue);
  });

  test('weak independent evidence cannot pass high-quality labels', () {
    recognizeSafe(cues: [
      _cue(ScreenCueId.warehouseLabel),
      _cue(ScreenCueId.scoreHud, .90),
      _cue(ScreenCueId.roundTimer),
    ]);
    expect(recognizer.decision.allowed, isFalse);
  });

  test('one weaker positive frame bounds the whole temporal score', () {
    for (var index = 0; index < 4; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 6 - 2 * index)),
        cues: [
          _cue(ScreenCueId.warehouseLabel, index == 1 ? .95 : .99),
          _cue(ScreenCueId.scoreHud),
          _cue(ScreenCueId.roundTimer),
        ],
      ));
    }
    expect(recognizer.decision.confidence, closeTo(.95, .000001));
  });

  test('safety confidence threshold cannot be lowered by caller', () {
    expect(() => AutomaticModeRecognizer(safeThreshold: .5), throwsArgumentError);
    expect(() => AutomaticModeRecognizer(safeThreshold: double.nan), throwsArgumentError);
  });

  test('duplicate sequence immediately invalidates safe recognition', () {
    recognizeSafe();
    final decision = recognizer.ingest(frame(sequence: 4));
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.allowed, isFalse);
  });

  test('frozen pixels cannot be counted as distinct frames', () {
    for (var index = 0; index < 4; index++) {
      recognizer.ingest(frame(
        sequence: index + 1,
        timestamp: now.subtract(Duration(seconds: 6 - 2 * index)),
        fingerprint: 'same-screenshot',
      ));
    }
    expect(recognizer.decision.allowed, isFalse);
  });

  test('missing actual pixel fingerprint cannot authorize a frame', () {
    expect(recognizer.ingest(frame(fingerprint: '')).allowed, isFalse);
    expect(recognizer.decision.frameCount, 0);
  });

  test('duplicate timestamps fail even with new sequence and pixels', () {
    recognizer.ingest(frame(sequence: 1));
    final decision = recognizer.ingest(frame(sequence: 2));
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.frameCount, 0);
  });

  test('safe recognition expires at twelve seconds without new evidence', () {
    recognizeSafe();
    now = now.add(const Duration(seconds: 11, milliseconds: 999));
    expect(recognizer.decision.allowed, isTrue);
    now = now.add(const Duration(milliseconds: 1));
    expect(recognizer.decision.mode, GameMode.unknownBlocked);
    expect(recognizer.decision.allowed, isFalse);
  });

  test('a backward system clock change immediately revokes safe recognition', () {
    recognizeSafe();
    expect(recognizer.decision.allowed, isTrue);
    now = now.subtract(const Duration(seconds: 1));
    expect(recognizer.decision.mode, GameMode.unknownBlocked);
    expect(recognizer.decision.allowed, isFalse);
    expect(recognizer.decision.frameCount, 0);
  });

  test('old and future screen timestamps cannot establish safety', () {
    for (final timestamp in [
      now.subtract(const Duration(seconds: 12)),
      now.add(const Duration(milliseconds: 1)),
    ]) {
      final decision = recognizer.ingest(frame(timestamp: timestamp));
      expect(decision.allowed, isFalse);
    }
  });

  test('frames from a previous capture session revoke rather than unlock', () {
    recognizeSafe();
    final decision = recognizer.ingest(frame(session: 'old-session', sequence: 99));
    expect(decision.mode, GameMode.unknownBlocked);
    expect(decision.sessionId, 'native-session');
    expect(decision.frameCount, 0);
  });

  test('capture authorization and verified actual foreground are mandatory', () {
    final badFrames = [
      frame(authorized: false),
      frame(foregroundVerified: false),
      frame(package: null),
      frame(package: 'com.example.fakepubg'),
      frame(error: 'capture_revoked'),
    ];
    for (final badFrame in badFrames) {
      final decision = recognizer.ingest(badFrame);
      expect(decision.mode, GameMode.unknownBlocked);
      expect(decision.allowed, isFalse);
    }
  });

  test('nonfinite or out-of-range cue confidence fails closed', () {
    for (final confidence in [double.nan, double.infinity, -1.0, 1.1]) {
      final decision = recognizer.ingest(frame(cues: [
        _cue(ScreenCueId.warehouseLabel, confidence),
        _cue(ScreenCueId.scoreHud),
        _cue(ScreenCueId.roundTimer),
      ]));
      expect(decision.allowed, isFalse);
    }
  });

  test('repeated detector boxes cannot inflate confidence', () {
    recognizeSafe(cues: [
      ..._warehouseCues,
      _cue(ScreenCueId.scoreHud, .6),
    ]);
    expect(recognizer.decision.allowed, isFalse);
  });

  test('native frame parsing preserves actual metadata without invented values', () {
    final parsed = ScreenFrameEvidence.fromJson({
      'type': 'frame',
      'sessionId': 'native-session',
      'sequence': 42,
      'timestampMs': now.millisecondsSinceEpoch,
      'captureAuthorized': true,
      'foregroundPackage': 'com.tencent.ig',
      'foregroundVerified': true,
      'frameFingerprint': 'native-screen-hash',
      'cues': [
        {'id': 'warehouse_label', 'confidence': .98, 'region': 'top-left'},
      ],
    });
    expect(parsed.error, isNull);
    expect(parsed.timestamp, now);
    expect(parsed.sequence, 42);
    expect(parsed.cues.single.confidence, .98);
    expect(parsed.frameFingerprint, 'native-screen-hash');
  });

  test('malformed native payloads cannot be coerced into trusted evidence', () {
    final parsed = ScreenFrameEvidence.fromJson({
      'type': 'frame',
      'sessionId': 'native-session',
      'sequence': '42',
      'timestampMs': '2026-10-08',
      'captureAuthorized': 'true',
      'foregroundVerified': 'true',
      'cues': [
        {'id': 'warehouse_label', 'confidence': '0.99', 'region': 'top-left'},
      ],
    });
    expect(parsed.error, isNotNull);
    expect(parsed.captureAuthorized, isFalse);
    expect(parsed.foregroundVerified, isFalse);
    expect(recognizer.ingest(parsed).allowed, isFalse);
  });

  test('out-of-range native timestamps become blocked data, not crashes', () {
    final parsed = ScreenFrameEvidence.fromJson({
      'type': 'frame',
      'sessionId': 'native-session',
      'sequence': 1,
      'timestampMs': 9223372036854775807,
      'captureAuthorized': true,
      'foregroundPackage': 'com.tencent.ig',
      'foregroundVerified': true,
      'frameFingerprint': 'native-screen-hash',
      'cues': [
        {'id': 'warehouse_label', 'confidence': .99, 'region': 'top-left'},
      ],
    });
    expect(parsed.error, 'malformed_frame_evidence');
    expect(recognizer.ingest(parsed).allowed, isFalse);
  });

  test('screen evidence and decision collections are immutable', () {
    final source = [_cue(ScreenCueId.trainingLabel)];
    final evidence = frame(cues: source);
    source.clear();
    expect(evidence.cues, hasLength(1));
    expect(() => evidence.cues.clear(), throwsUnsupportedError);
    final decision = recognizeSafe();
    expect(() => decision.evidence.clear(), throwsUnsupportedError);
  });
}

ScreenCue _cue(String id, [double confidence = .99]) => ScreenCue(
  id: id,
  confidence: confidence,
  region: id.endsWith('_label') ? 'mode-label' : 'gameplay-hud',
);

final _warehouseCues = [
  _cue(ScreenCueId.warehouseLabel),
  _cue(ScreenCueId.scoreHud),
  _cue(ScreenCueId.roundTimer),
];
