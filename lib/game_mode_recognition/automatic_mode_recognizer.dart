import '../game_mode_guard/game_mode.dart';
import 'recognition_models.dart';

/// Temporal, fail-closed recognition from the native authorized capture stream.
/// Neither offline mode labels nor the absence of Battle Royale are evidence.
/// These rules are deliberately conservative until device/locale-specific
/// capture fixtures have validated the screen detectors in real gameplay.
class AutomaticModeRecognizer {
  AutomaticModeRecognizer({DateTime Function()? now, this.safeThreshold = .95})
    : _now = now ?? DateTime.now {
    if (!safeThreshold.isFinite || safeThreshold < .95 || safeThreshold > 1) {
      throw ArgumentError.value(safeThreshold, 'safeThreshold', 'minimum .95');
    }
  }

  static const verificationTtl = Duration(seconds: 12);
  static const minimumSpan = Duration(seconds: 6);
  static const minimumFrames = 4;
  static const _credibleHazard = .80;
  static const _ambiguousHazard = .50;
  static const _positiveCue = .95;
  static const _allowedPackages = {
    'com.tencent.ig',
    'com.pubg.krmobile',
    'com.vng.pubgmobile',
    'com.rekoo.pubgm',
    'com.pubg.imobile',
  };
  static const _hazards = {
    ScreenCueId.airplane,
    ScreenCueId.flightPath,
    ScreenCueId.jump,
    ScreenCueId.follow,
    ScreenCueId.freeFall,
    ScreenCueId.parachute,
    ScreenCueId.brMap,
    ScreenCueId.rankedLabel,
  };
  final DateTime Function() _now;
  final double safeThreshold;
  String? _sessionId;
  int? _lastSequence;
  DateTime? _latestTimestamp;
  bool _competitiveLatched = false;
  final List<_FrameProof> _proofs = [];
  final List<String> _recentFingerprints = [];
  bool get battleRoyaleLatched => _competitiveLatched;
  RecognitionDecision _decision = RecognitionDecision(
    mode: GameMode.unknownBlocked,
    confidence: 0,
    evidence: const ['لم تبدأ جلسة التقاط شاشة مصرح بها.'],
    lastVerified: null,
    sessionId: null,
    frameCount: 0,
  );

  RecognitionDecision get decision {
    if (!_competitiveLatched && _latestTimestamp != null) {
      final age = _now().difference(_latestTimestamp!);
      if (age.isNegative || age >= verificationTtl) {
        _block('انتهت صلاحية التحقق أو تغير وقت النظام؛ يلزم دليل حديث من الشاشة.');
      }
    }
    return _decision;
  }

  /// Only the native capture-session lifecycle may call this through the app
  /// controller. Reusing a session identifier cannot clear a competitive lock.
  void beginSession(String id) {
    if (id.isEmpty) {
      stopSession();
      return;
    }
    if (_sessionId == id) return;
    _sessionId = id;
    _lastSequence = null;
    _latestTimestamp = null;
    _competitiveLatched = false;
    _proofs.clear();
    _recentFingerprints.clear();
    _decision = _unknown('بانتظار عدة إطارات موثوقة من جلسة الالتقاط.');
  }

  void stopSession() {
    _sessionId = null;
    _lastSequence = null;
    _latestTimestamp = null;
    _competitiveLatched = false;
    _proofs.clear();
    _recentFingerprints.clear();
    _decision = _unknown('التقاط الشاشة متوقف؛ جميع العمليات مقفولة.');
  }

  /// Revokes stale safe authorization without clearing a competitive latch or
  /// replacing the native consent session. Lifecycle events can only lock.
  void invalidateEvidence(String reason) => _block(reason);

  RecognitionDecision ingest(ScreenFrameEvidence frame) {
    if (_sessionId == null || frame.sessionId != _sessionId) {
      return _block('إطار خارج جلسة الالتقاط الحالية؛ لم يُستخدم للتصنيف.');
    }
    if (_competitiveLatched) return _decision;
    final age = _now().difference(frame.timestamp);
    if (!frame.captureAuthorized ||
        !frame.foregroundVerified ||
        !_allowedPackages.contains(frame.foregroundPackage)) {
      return _block('إذن الالتقاط أو التحقق من تطبيق PUBG غير متاح.');
    }
    if (frame.error != null || frame.cues.any((cue) => !cue.valid)) {
      return _block('تعذر تحليل إطار الشاشة بشكل موثوق.');
    }
    if (frame.sequence < 0 ||
        frame.frameFingerprint.isEmpty ||
        _recentFingerprints.contains(frame.frameFingerprint) ||
        (_lastSequence != null && frame.sequence <= _lastSequence!) ||
        (_latestTimestamp != null &&
            !frame.timestamp.isAfter(_latestTimestamp!))) {
      return _block('إطار مكرر أو ترتيب زمني غير صالح؛ التحقق مقفول.');
    }
    if (age >= verificationTtl || age.isNegative) {
      return _block('الإطار قديم أو توقيته غير صالح؛ التحقق مقفول.');
    }
    _lastSequence = frame.sequence;
    _latestTimestamp = frame.timestamp;
    _recentFingerprints.add(frame.frameFingerprint);
    if (_recentFingerprints.length > 32) _recentFingerprints.removeAt(0);
    final cues = <String, ScreenCue>{};
    for (final cue in frame.cues) {
      final previous = cues[cue.id];
      // Duplicated cue boxes cannot increase the score or count as independent
      // indicators. Keep the weakest confidence if a detector repeats a cue.
      if (previous == null || cue.confidence < previous.confidence) {
        cues[cue.id] = cue;
      }
    }
    final hazards = cues.values
        .where(
          (cue) => _hazards.contains(cue.id) &&
              cue.confidence >= _credibleHazard,
        )
        .toList();
    if (hazards.isNotEmpty) {
      _competitiveLatched = true;
      _proofs.clear();
      _decision = RecognitionDecision(
        mode: GameMode.competitiveBlocked,
        confidence: hazards
            .map((cue) => cue.confidence)
            .reduce((a, b) => a > b ? a : b),
        evidence: [
          ...hazards.map((cue) => _cueLabel(cue.id)),
          'قفل فوري مستمر حتى إنهاء جلسة الالتقاط الحالية.',
        ],
        lastVerified: frame.timestamp,
        sessionId: _sessionId,
        frameCount: 1,
      );
      return _decision;
    }
    if (cues.values.any(
      (cue) =>
          _hazards.contains(cue.id) && cue.confidence >= _ambiguousHazard,
    )) {
      return _block('مؤشر محتمل لطائرة أو نزول أو وضع محظور؛ الأدلة متعارضة.');
    }
    final proof = _classifyFrame(cues, frame.timestamp);
    if (proof == null) {
      return _block('لا توجد تسمية وضع وأدلة مستقلة كافية؛ الوضع غير معروف.');
    }
    if (_proofs.isNotEmpty && _proofs.last.mode != proof.mode) {
      _proofs.clear();
    }
    _proofs.removeWhere(
      (sample) => _now().difference(sample.timestamp) >= verificationTtl,
    );
    _proofs.add(proof);
    final span = _proofs.last.timestamp.difference(_proofs.first.timestamp);
    final frameCoverage = (_proofs.length / minimumFrames).clamp(0.0, 1.0);
    final temporalCoverage =
        (span.inMilliseconds / minimumSpan.inMilliseconds).clamp(0.0, 1.0);
    final weakestConfidence = _proofs
        .map((sample) => sample.confidence)
        .reduce((a, b) => a < b ? a : b);
    final confidence = weakestConfidence * frameCoverage * temporalCoverage;
    final passed = _proofs.length >= minimumFrames &&
        span >= minimumSpan &&
        confidence >= safeThreshold;
    _decision = RecognitionDecision(
      mode: passed ? proof.mode : GameMode.unknownBlocked,
      confidence: confidence,
      evidence: [
        ...{for (final sample in _proofs) ...sample.evidence},
        '${_proofs.length} إطارات مستقلة خلال '
            '${(span.inMilliseconds / 1000).toStringAsFixed(1)} ثانية.',
        if (!passed) 'لم تكتمل شروط الثقة والتأكيد الزمني بعد.',
      ],
      lastVerified: frame.timestamp,
      sessionId: _sessionId,
      frameCount: _proofs.length,
    );
    return _decision;
  }

  _FrameProof? _classifyFrame(Map<String, ScreenCue> cues, DateTime timestamp) {
    final labels = <GameMode, List<String>>{
      GameMode.trainingSafe: [ScreenCueId.trainingLabel],
      GameMode.warehouseSafe: [ScreenCueId.warehouseLabel],
      GameMode.arenaSafe: [ScreenCueId.arenaLabel, ScreenCueId.tdmLabel],
    };
    final plausible = labels.entries
        .where((entry) => entry.value.any(
          (id) => (cues[id]?.confidence ?? 0) >= _ambiguousHazard,
        ))
        .toList();
    // Warehouse is a map within Arena/TDM; generic Arena labels may accompany
    // its specific label. They do not count as an independent HUD indicator.
    if (plausible.any((entry) => entry.key == GameMode.warehouseSafe)) {
      plausible.removeWhere((entry) => entry.key == GameMode.arenaSafe);
    }
    if (plausible.length > 1) return null;
    bool strong(String id) => (cues[id]?.confidence ?? 0) >= _positiveCue;
    final used = <String>[];
    GameMode mode;
    if (plausible.isEmpty) {
      if (!strong(ScreenCueId.unrankedLabel)) return null;
      mode = GameMode.safeUnranked;
      used.add(ScreenCueId.unrankedLabel);
      if (strong(ScreenCueId.targetPractice) &&
          strong(ScreenCueId.trainingControls)) {
        used.addAll([ScreenCueId.targetPractice, ScreenCueId.trainingControls]);
      } else if (strong(ScreenCueId.scoreHud) &&
          strong(ScreenCueId.roundTimer) &&
          strong(ScreenCueId.respawnTransition)) {
        used.addAll([
          ScreenCueId.scoreHud,
          ScreenCueId.roundTimer,
          ScreenCueId.respawnTransition,
        ]);
      } else {
        return null;
      }
    } else {
      final entry = plausible.single;
      mode = entry.key;
      final strongLabels = entry.value.where(strong).toList();
      if (strongLabels.isEmpty) return null;
      used.addAll(strongLabels);
      if (mode == GameMode.trainingSafe) {
        if (strong(ScreenCueId.targetPractice)) {
          used.add(ScreenCueId.targetPractice);
        } else if (strong(ScreenCueId.trainingControls)) {
          used.add(ScreenCueId.trainingControls);
        } else {
          return null;
        }
      } else if (strong(ScreenCueId.respawnTransition)) {
        used.add(ScreenCueId.respawnTransition);
      } else if (strong(ScreenCueId.scoreHud) &&
          strong(ScreenCueId.roundTimer)) {
        used.addAll([ScreenCueId.scoreHud, ScreenCueId.roundTimer]);
      } else {
        return null;
      }
    }
    return _FrameProof(
      mode: mode,
      timestamp: timestamp,
      confidence: used
          .map((id) => cues[id]!.confidence)
          .reduce((a, b) => a < b ? a : b),
      evidence: used.map(_cueLabel).toList(),
    );
  }

  RecognitionDecision _block(String reason) {
    if (_competitiveLatched) return _decision;
    _proofs.clear();
    _decision = _unknown(reason);
    return _decision;
  }

  RecognitionDecision _unknown(String reason) => RecognitionDecision(
    mode: GameMode.unknownBlocked,
    confidence: 0,
    evidence: [reason],
    lastVerified: _latestTimestamp,
    sessionId: _sessionId,
    frameCount: 0,
  );

  static String _cueLabel(String id) => switch (id) {
    ScreenCueId.trainingLabel => 'تسمية ساحة التدريب من الشاشة',
    ScreenCueId.warehouseLabel => 'تسمية Warehouse من الشاشة',
    ScreenCueId.arenaLabel => 'تسمية Arena من الشاشة',
    ScreenCueId.tdmLabel => 'تسمية TDM من الشاشة',
    ScreenCueId.unrankedLabel => 'تسمية Unranked صريحة من الشاشة',
    ScreenCueId.scoreHud => 'واجهة نقاط الفريقين',
    ScreenCueId.targetPractice => 'واجهة أهداف التدريب',
    ScreenCueId.trainingControls => 'عناصر تحكم خاصة بالتدريب',
    ScreenCueId.respawnCountdown => 'عداد إعادة الظهور',
    ScreenCueId.respawnTransition => 'انتقال إعادة ظهور مؤكد من الشاشة',
    ScreenCueId.roundTimer => 'مؤقت الجولة',
    ScreenCueId.airplane => 'مرحلة الطائرة',
    ScreenCueId.flightPath => 'مسار الطيران',
    ScreenCueId.jump => 'مؤشر القفز من الطائرة',
    ScreenCueId.follow => 'متابعة اللاعبين أثناء النزول',
    ScreenCueId.freeFall => 'مرحلة السقوط الحر',
    ScreenCueId.parachute => 'مرحلة المظلة',
    ScreenCueId.brMap => 'خريطة Battle Royale',
    ScreenCueId.rankedLabel => 'تسمية وضع مصنف',
    _ => id,
  };
}

class _FrameProof {
  const _FrameProof({
    required this.mode,
    required this.timestamp,
    required this.confidence,
    required this.evidence,
  });
  final GameMode mode;
  final DateTime timestamp;
  final double confidence;
  final List<String> evidence;
}
