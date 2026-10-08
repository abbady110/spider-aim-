import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/capture/capture_service.dart';
import 'package:spider_aim/core/coach_controller.dart';
import 'package:spider_aim/device/device_service.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/overlay/overlay_bridge.dart';
import 'package:spider_aim/overlay/overlay_service.dart';
import 'package:spider_aim/storage/coach_store.dart';

import 'support/recognized_guard.dart';

const _context = 'M416|3x|Compensator|50';
const _key = '$_context::ads';

class _Device extends DeviceService {
  const _Device();

  @override
  Future<DeviceSnapshot> read() async => const DeviceSnapshot(
    deviceId: 'overlay-phone', name: 'Physical Android fixture',
    supported: true, physicalDevice: true, batteryPercent: 80,
    charging: false, thermal: 'NOMINAL', details: {'platform': 'android'},
  );
}

class _Capture extends CaptureService {
  final frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  int _session = 0;
  int _sequence = 0;
  String get sessionId => 'overlay-capture-$_session';

  @override
  Stream<Map<String, dynamic>> get events => frames.stream;
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'supported': true, 'usageAccessGranted': true, 'platform': 'android',
  };
  @override
  Future<Map<String, dynamic>> start() async {
    _session++;
    _sequence = 0;
    return {'supported': true, 'started': true, 'sessionId': sessionId};
  }
  @override
  Future<void> stop() async {}

  void safeFrames(DateTime now) {
    for (var i = 0; i < 4; i++) {
      frames.add({
        'type': 'frame', 'sessionId': sessionId, 'sequence': ++_sequence,
        'frameFingerprint': 'synthetic-$sessionId-pixels-$_sequence',
        'timestampMs': now.subtract(Duration(seconds: 7 - i * 2)).millisecondsSinceEpoch,
        'captureAuthorized': true, 'foregroundVerified': true,
        'foregroundPackage': 'com.tencent.ig',
        'cues': safeScreenCues(GameMode.warehouseSafe).map((cue) => {
          'id': cue.id, 'confidence': cue.confidence, 'region': cue.region,
        }).toList(),
      });
    }
  }

  void competitiveFrame(DateTime now) {
    frames.add({
      'type': 'frame', 'sessionId': sessionId, 'sequence': ++_sequence,
      'frameFingerprint': 'synthetic-$sessionId-pixels-$_sequence',
      'timestampMs': now.millisecondsSinceEpoch,
      'captureAuthorized': true, 'foregroundVerified': true,
      'foregroundPackage': 'com.tencent.ig',
      'cues': [{'id': 'airplane', 'confidence': .99, 'region': 'center'}],
    });
  }
}

class _Overlay extends OverlayService {
  Future<Map<String, Object?>> Function(Map<String, Object?>)? handler;
  Map<String, Object?> lastState = {};

  @override
  Future<Map<String, Object?>> capabilities() async => {
    'supported': true, 'permissionGranted': true,
  };
  @override
  Future<Map<String, Object?>> requestPermission() => capabilities();
  @override
  Future<Map<String, Object?>> show() async => {'visible': true};
  @override
  Future<void> hide() async {}
  @override
  Future<void> updateState(Map<String, Object?> state) async {
    lastState = Map<String, Object?>.from(state);
  }
  @override
  void setRequestHandler(
    Future<Map<String, Object?>> Function(Map<String, Object?> request)? handler,
  ) {
    this.handler = handler;
  }
}

class _Harness {
  _Harness() {
    guard = GameModeGuard(now: () => now);
    controller = CoachController(store: MemoryCoachStore(),
      deviceService: const _Device(), gameModeGuard: guard,
      captureService: capture, overlayService: overlay);
    bridge = OverlayBridge(controller, now: () => now);
  }
  DateTime now = recognitionFixtureTime;
  final capture = _Capture();
  final overlay = _Overlay();
  late final GameModeGuard guard;
  late final CoachController controller;
  late final OverlayBridge bridge;

  Future<void> initialize({bool recognized = true}) async {
    await controller.initialize();
    bridge.attach();
    controller.disposeOverlayBridge = bridge.dispose;
    await controller.startAutomaticRecognition();
    if (recognized) {
      capture.safeFrames(now);
      expect(guard.mode, GameMode.warehouseSafe);
    }
  }

  Future<Map<String, Object?>> request(String action,
    [Map<String, Object?> payload = const {}]) => overlay.handler!({
      'action': action, 'payload': payload,
    });

  Future<Map<String, Object?>> submit(Map<String, Object?> response,
    Map<String, Object?> values) => request('submit', {
      'formId': (response['form'] as Map)['id'], 'values': values,
    });

  Future<void> close() async {
    controller.dispose();
    await capture.frames.close();
  }
}

Map<String, Object?> _baselineValues({bool confirmed = true}) => {
  'weapon': 'M416', 'scope': '3x', 'attachments': 'Compensator', 'distance': 50,
  'ads': 31, 'confirmCurrent': confirmed,
};

Map<String, Object?> _metrics({bool improved = false}) => {
  'aimStability': improved ? 75 : 60, 'hitRate': improved ? 65 : 55,
  'trackingScore': 65, 'adsStability': 65, 'movementRetention': 65,
  'fpsStability': 95, 'sprayGrouping': 10, 'overshootRate': 40,
  'undershootRate': 10, 'acquisitionMs': 400, 'thermalImpact': 1,
  'batteryDrain': 12,
};

Map<String, Object?> _aimValues() => {
  'weapon': 'M416', 'scope': '3x', 'attachments': 'Compensator', 'distance': 50,
  ..._metrics(), 'verticalRecoil': 12, 'horizontalDrift': 4,
  'firstShotStability': 80, 'adsStabilizationMs': 200,
  'fingerDragConsistency': 75, 'sprayConsistency': 80,
  'hits': 55, 'shots': 100, 'latencyMs': 30, 'jitterMs': 3,
  'packetLossPercent': 0, 'actualTest': true,
  'networkMetricsReliable': true, 'frameMetricsReliable': true,
};

Future<void> _saveBaseline(_Harness harness) async {
  final form = await harness.request('baseline');
  expect(form['ok'], isTrue);
  final saved = await harness.submit(form, _baselineValues());
  expect(saved['ok'], isTrue);
  expect((harness.controller.state['approved'] as Map)['settings'], {_key: 31.0});
}

Future<void> _saveAimSamples(_Harness harness, int count) async {
  for (var i = 0; i < count; i++) {
    final form = await harness.request('aim');
    expect(form['ok'], isTrue);
    final saved = await harness.submit(form, _aimValues());
    expect(saved['ok'], isTrue, reason: 'observation ${i + 1}');
  }
}

Future<Map<String, Object?>> _recommendationReview(_Harness harness) async {
  final choose = await harness.request('propose');
  expect(choose['ok'], isTrue);
  final review = await harness.submit(choose, {'context': _context});
  expect(review['ok'], isTrue);
  return review;
}

Future<String> _saveProposal(_Harness harness) async {
  await _saveBaseline(harness);
  await _saveAimSamples(harness, 5);
  final review = await _recommendationReview(harness);
  expect((await harness.submit(review, {'confirmProposal': true}))['ok'], isTrue);
  return (harness.controller.state['proposals'] as List).single['id'] as String;
}

Future<Map<String, Object?>> _proposalDecision(_Harness harness, String id) async {
  final choose = await harness.request('proposals');
  expect(choose['ok'], isTrue);
  final decision = await harness.submit(choose, {'proposalId': id});
  expect(decision['ok'], isTrue);
  return decision;
}

List<Object?> _decisionOptions(Map<String, Object?> response) {
  final fields = (response['form'] as Map)['fields'] as List;
  final decision = fields.cast<Map>().singleWhere((field) => field['key'] == 'decision');
  return (decision['options'] as List).map((option) => (option as Map)['value']).toList();
}

Future<String> _startTrial(_Harness harness) async {
  final id = await _saveProposal(harness);
  final decision = await _proposalDecision(harness, id);
  final result = await harness.submit(decision, {
    'decision': 'approveForTest', 'confirmDecision': true,
  });
  expect(result['ok'], isTrue);
  expect(harness.controller.state['testingId'], id);
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness harness;

  setUp(() {
    harness = _Harness();
  });
  tearDown(() async {
    await harness.close();
  });

  test('attached native request handler never unlocks unknown from manual payloads', () async {
    await harness.initialize(recognized: false);
    final before = harness.controller.state;
    for (final action in ['baseline', 'aim', 'propose', 'testing', 'restore']) {
      final response = await harness.request(action, {
        'mode': 'WAREHOUSE_SAFE', 'allowed': true, 'confidence': 1,
        'captureAuthorized': true, 'foregroundVerified': true,
      });
      expect(response['ok'], isFalse, reason: action);
      expect(harness.guard.mode, GameMode.unknownBlocked);
      expect(harness.controller.state, before);
    }
  });

  test('Battle Royale evidence blocks native requests and ignores manual safe claims', () async {
    await harness.initialize();
    harness.capture.competitiveFrame(harness.now);
    expect(harness.guard.mode, GameMode.competitiveBlocked);
    final before = harness.controller.state;
    for (final action in ['baseline', 'aim', 'propose', 'testing', 'restore']) {
      final response = await harness.request(action, {'mode': 'TRAINING_SAFE'});
      expect(response['ok'], isFalse, reason: action);
      expect(harness.controller.state, before);
    }
    expect(harness.guard.mode, GameMode.competitiveBlocked);
  });

  test('baseline requires explicit current-setting confirmation through the native form', () async {
    await harness.initialize();
    final before = harness.controller.state;
    for (final confirmation in [false, 'true', 1]) {
      final form = await harness.request('baseline');
      final response = await harness.submit(form,
        {..._baselineValues(), 'confirmCurrent': confirmation});
      expect(response['ok'], isFalse);
      expect(harness.controller.state, before);
    }
    await _saveBaseline(harness);
  });

  test('native callers cannot bypass forms with direct workflow commands', () async {
    await harness.initialize();
    final before = harness.controller.state;
    for (final action in ['saveBaseline', 'approveForTest', 'approveFinal', 'setMode']) {
      final response = await harness.request(action, {
        'settings': {_key: 99}, 'proposalId': 'invented',
        'confirmed': true, 'mode': 'WAREHOUSE_SAFE',
      });
      expect(response['ok'], isFalse, reason: action);
      expect(harness.controller.state, before);
    }
    final unknownForm = await harness.request('submit', {
      'formId': 'not-issued-by-the-bridge', 'values': _baselineValues(),
    });
    expect(unknownForm['ok'], isFalse);
    expect(harness.controller.state, before);
  });

  test('a successfully consumed form cannot be replayed with different settings', () async {
    await harness.initialize();
    final form = await harness.request('baseline');
    expect((await harness.submit(form, _baselineValues()))['ok'], isTrue);
    final before = harness.controller.state;
    final replay = await harness.submit(form, {
      ..._baselineValues(), 'weapon': 'AKM', 'ads': 88,
    });
    expect(replay['ok'], isFalse);
    expect(harness.controller.state, before);
  });

  test('simultaneous native submissions cannot double-apply a reviewed form', () async {
    await harness.initialize();
    final form = await harness.request('baseline');
    final first = harness.submit(form, _baselineValues());
    final second = harness.submit(form, _baselineValues());
    final responses = await Future.wait([first, second]);
    expect(responses.where((response) => response['ok'] == true), hasLength(1));
    expect(responses.where((response) => response['ok'] == false), hasLength(1));
    expect(harness.controller.state['versions'], hasLength(1));
    expect((harness.controller.state['approved'] as Map)['settings'], {_key: 31.0});
  });

  test('a stale form cannot regain authority from new safe evidence after expiration', () async {
    await harness.initialize();
    final form = await harness.request('baseline');
    harness.now = harness.now.add(const Duration(minutes: 6));
    harness.capture.safeFrames(harness.now);
    expect(harness.guard.mode, GameMode.warehouseSafe);
    final before = harness.controller.state;
    final expired = await harness.submit(form, _baselineValues());
    expect(expired['ok'], isFalse);
    expect(harness.controller.state, before);
  });

  test('form authorization is bound to the capture session that issued it', () async {
    await harness.initialize();
    final form = await harness.request('baseline');
    final oldSession = harness.capture.sessionId;
    await harness.controller.stopAutomaticRecognition();
    await harness.controller.startAutomaticRecognition();
    harness.capture.safeFrames(harness.now);
    expect(harness.capture.sessionId, isNot(oldSession));
    expect(harness.guard.allowed, isTrue);
    final before = harness.controller.state;
    final response = await harness.submit(form, _baselineValues());
    expect(response['ok'], isFalse);
    expect(harness.controller.state, before);
  });

  test('a form is invalidated if the approved version changes before submission', () async {
    await harness.initialize();
    final stale = await harness.request('baseline');
    final other = await harness.request('baseline');
    final saved = await harness.submit(other,
      {..._baselineValues(), 'weapon': 'AKM', 'ads': 40});
    expect(saved['ok'], isTrue);
    final before = harness.controller.state;
    final rejected = await harness.submit(stale, _baselineValues());
    expect(rejected['ok'], isFalse);
    expect(harness.controller.state, before);
    expect(((before['approved'] as Map)['settings'] as Map).containsKey(_key), isFalse);
  });

  test('capture revocation closes an already-open baseline form without a write', () async {
    await harness.initialize();
    final form = await harness.request('baseline');
    final before = harness.controller.state;
    await harness.controller.stopAutomaticRecognition();
    final response = await harness.submit(form, _baselineValues());
    expect(response['ok'], isFalse);
    expect(harness.controller.state, before);
  });

  test('aim entry requires actual-test confirmation and finite measured values', () async {
    await harness.initialize();
    await _saveBaseline(harness);
    final before = harness.controller.state;
    for (final invalid in [
      {..._aimValues(), 'actualTest': false},
      {..._aimValues(), 'aimStability': double.nan},
      {..._aimValues(), 'hits': 101},
    ]) {
      final form = await harness.request('aim');
      final response = await harness.submit(form, invalid);
      expect(response['ok'], isFalse);
      expect(harness.controller.state, before);
    }
    await _saveAimSamples(harness, 1);
    expect((harness.controller.state['observations'] as List).length, 1);
  });

  test('proposal review derives values and evidence from five real submitted observations', () async {
    await harness.initialize();
    await _saveBaseline(harness);
    await _saveAimSamples(harness, 4);
    final earlyChoice = await harness.request('propose');
    final early = await harness.submit(earlyChoice, {'context': _context});
    expect(early['ok'], isFalse);
    expect(harness.controller.state['proposals'], isEmpty);

    await _saveAimSamples(harness, 1);
    final review = await _recommendationReview(harness);
    final notice = (review['form'] as Map)['notice'] as String;
    expect(notice, contains('31.0'));
    expect(notice, contains('30'));
    expect(notice, contains('5/5'));
    final before = harness.controller.state;
    final unconfirmed = await harness.submit(review, {'confirmProposal': false});
    expect(unconfirmed['ok'], isFalse);
    final tampered = await harness.submit(review, {
      'confirmProposal': true, 'proposed': 399, 'sampleCount': 999,
      'key': 'GYROSCOPE', 'evidence': 'invented native evidence',
    });
    expect(tampered['ok'], isFalse);
    expect(harness.controller.state, before);

    final saved = await harness.submit(review, {'confirmProposal': true});
    expect(saved['ok'], isTrue);
    final state = harness.controller.state;
    final proposal = (state['proposals'] as List).single as Map;
    expect(proposal['status'], 'PROPOSED');
    expect(proposal['sampleCount'], 5);
    expect((proposal['sampleIds'] as List).toSet(), hasLength(5));
    expect(proposal['key'], _key);
    expect(proposal['proposed'], 30);
    expect((state['approved'] as Map)['settings'], {_key: 31.0});
    expect(state['backups'], isEmpty);
    expect(state['testingId'], isNull);
  });

  test('adding observations invalidates an already reviewed recommendation', () async {
    await harness.initialize();
    await _saveBaseline(harness);
    await _saveAimSamples(harness, 5);
    final review = await _recommendationReview(harness);
    await _saveAimSamples(harness, 1);
    final before = harness.controller.state;
    final stale = await harness.submit(review, {'confirmProposal': true});
    expect(stale['ok'], isFalse);
    expect(harness.controller.state, before);
    expect(harness.controller.state['proposals'], isEmpty);
  });

  test('proposal decision form permits consented trial only and preserves the approved snapshot', () async {
    await harness.initialize();
    final id = await _saveProposal(harness);
    final decision = await _proposalDecision(harness, id);
    expect(_decisionOptions(decision), contains('approveForTest'));
    expect(_decisionOptions(decision), isNot(contains('approveFinal')));
    final before = harness.controller.state;
    final premature = await harness.submit(decision, {
      'decision': 'approveFinal', 'confirmDecision': true,
    });
    expect(premature['ok'], isFalse);
    final unconfirmed = await harness.submit(decision, {
      'decision': 'approveForTest', 'confirmDecision': false,
    });
    expect(unconfirmed['ok'], isFalse);
    expect(harness.controller.state, before);

    final approved = await harness.submit(decision, {
      'decision': 'approveForTest', 'confirmDecision': true,
    });
    expect(approved['ok'], isTrue);
    final testing = harness.controller.state;
    expect(testing['testingId'], id);
    expect((testing['proposals'] as List).single['status'], 'TESTING');
    expect((testing['approved'] as Map)['settings'], {_key: 31.0});
    expect((testing['versions'] as List).last['settings'], {_key: 30});
    expect(((testing['backups'] as List).single['snapshot'] as Map)['settings'],
      {_key: 31.0});
    final replay = await harness.submit(decision, {
      'decision': 'approveForTest', 'confirmDecision': true,
    });
    expect(replay['ok'], isFalse);
    expect(harness.controller.state, testing);
  });

  test('test and final decision use separate forms with explicit consent and guarded restore', () async {
    await harness.initialize();
    await _startTrial(harness);
    final testForm = await harness.request('testing');
    final before = harness.controller.state;
    final notApplied = await harness.submit(testForm, {
      ..._metrics(improved: true), 'sampleCount': 5,
      'actualTest': true, 'manualApplied': false,
    });
    expect(notApplied['ok'], isFalse);
    expect(harness.controller.state, before);
    final compared = await harness.submit(testForm, {
      ..._metrics(improved: true), 'sampleCount': 5,
      'actualTest': true, 'manualApplied': true,
    });
    expect(compared['ok'], isTrue);
    expect(_decisionOptions(compared), contains('approveFinal'));
    expect((harness.controller.state['proposals'] as List).single['status'], 'PASSED');
    expect((harness.controller.state['approved'] as Map)['settings'], {_key: 31.0});
    final unconfirmed = await harness.submit(compared, {
      'decision': 'approveFinal', 'confirmDecision': false,
    });
    expect(unconfirmed['ok'], isFalse);
    final approved = await harness.submit(compared, {
      'decision': 'approveFinal', 'confirmDecision': true,
    });
    expect(approved['ok'], isTrue);
    expect((harness.controller.state['approved'] as Map)['settings'], {_key: 30});

    final restore = await harness.request('restore');
    expect((await harness.submit(restore, {'confirmRestore': false}))['ok'], isFalse);
    expect((await harness.submit(restore, {'confirmRestore': true}))['ok'], isTrue);
    expect((harness.controller.state['approved'] as Map)['settings'], {_key: 31.0});
    expect(harness.controller.state['testingId'], isNull);
  });

  test('failed comparison never offers or accepts final approval through a form', () async {
    await harness.initialize();
    await _startTrial(harness);
    final testForm = await harness.request('testing');
    final failed = await harness.submit(testForm, {
      ..._metrics(), 'sampleCount': 5, 'actualTest': true, 'manualApplied': true,
    });
    expect(failed['ok'], isTrue);
    expect(_decisionOptions(failed), isNot(contains('approveFinal')));
    expect(_decisionOptions(failed), contains('retest'));
    final before = harness.controller.state;
    final attempted = await harness.submit(failed, {
      'decision': 'approveFinal', 'confirmDecision': true,
    });
    expect(attempted['ok'], isFalse);
    expect(harness.controller.state, before);
    expect((before['approved'] as Map)['settings'], {_key: 31.0});
  });

  test('Battle Royale revokes an open final-approval form after a passing test', () async {
    await harness.initialize();
    await _startTrial(harness);
    final testForm = await harness.request('testing');
    final passed = await harness.submit(testForm, {
      ..._metrics(improved: true), 'sampleCount': 5,
      'actualTest': true, 'manualApplied': true,
    });
    expect(_decisionOptions(passed), contains('approveFinal'));
    final before = harness.controller.state;
    harness.capture.competitiveFrame(harness.now);
    final denied = await harness.submit(passed, {
      'decision': 'approveFinal', 'confirmDecision': true,
    });
    expect(denied['ok'], isFalse);
    expect(harness.guard.mode, GameMode.competitiveBlocked);
    expect(harness.controller.state, before);
  });

  test('a proposal decision cannot be reused after another form changes its status', () async {
    await harness.initialize();
    final id = await _saveProposal(harness);
    final stale = await _proposalDecision(harness, id);
    final current = await _proposalDecision(harness, id);
    final deferred = await harness.submit(current, {
      'decision': 'defer', 'confirmDecision': true,
    });
    expect(deferred['ok'], isTrue);
    final before = harness.controller.state;
    final attempted = await harness.submit(stale, {
      'decision': 'approveForTest', 'confirmDecision': true,
    });
    expect(attempted['ok'], isFalse);
    expect(harness.controller.state, before);
    expect(before['testingId'], isNull);
  });

  test('disposing the native bridge removes its handler and rejects retained requests', () async {
    await harness.initialize();
    final retained = harness.overlay.handler!;
    harness.bridge.dispose();
    expect(harness.overlay.handler, isNull);
    final response = await retained({'action': 'baseline', 'payload': <String, Object?>{}});
    expect(response['ok'], isFalse);
    expect(harness.controller.state['versions'], isEmpty);
  });

  test('native responses include current authorization after request busy state clears', () async {
    await harness.initialize();
    final opened = await harness.request('baseline');
    expect((opened['state'] as Map)['allowed'], isTrue);
    expect((opened['state'] as Map)['busy'], isFalse);
    harness.capture.competitiveFrame(harness.now);
    final denied = await harness.submit(opened, _baselineValues());
    final state = denied['state'] as Map;
    expect(state['allowed'], isFalse);
    expect(state['busy'], isFalse);
    expect(state['mode'], 'COMPETITIVE_BLOCKED');
  });

  test('the safe hide action works while locked without authorizing or mutating settings', () async {
    await harness.initialize(recognized: false);
    await harness.controller.showOverlay();
    expect(harness.controller.overlayVisible, isTrue);
    final before = harness.controller.state;
    final hidden = await harness.request('hideOverlay');
    expect(hidden['ok'], isTrue);
    expect(harness.controller.overlayVisible, isFalse);
    expect(harness.guard.mode, GameMode.unknownBlocked);
    expect(harness.controller.state, before);
    final invalid = await harness.request('hideOverlay', {'mode': 'WAREHOUSE_SAFE'});
    expect(invalid['ok'], isFalse);
    expect(harness.controller.state, before);
  });
}
