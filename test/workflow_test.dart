import 'package:flutter_test/flutter_test.dart';
import 'package:spider_aim/core/calibration_workflow.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/storage/coach_store.dart';

const _context = 'M416|3x|Compensator|50';
const _key = '$_context::ads';
const _device = 'physical-phone-a';

Map<String, double> _metrics({bool improved = false}) => {
  'aimStability': improved ? 75 : 60,
  'hitRate': improved ? 65 : 55,
  'trackingScore': 65,
  'adsStability': 65,
  'movementRetention': 65,
  'fpsStability': 95,
  'sprayGrouping': 10,
  'overshootRate': 20,
  'undershootRate': 10,
  'acquisitionMs': 400,
  'thermalImpact': 1,
  'batteryDrain': 12,
};

Future<void> _baseline(CalibrationWorkflow workflow, {int count = 5}) async {
  await workflow.saveBaseline({_key: 31});
  for (var i = 0; i < count; i++) {
    await workflow.addObservation('aim', {'context': _context, 'metrics': _metrics()});
  }
}

Future<StateMap> _propose(CalibrationWorkflow workflow, {int samples = 5}) =>
  workflow.propose(key: _key, proposed: 30,
    reason: 'Repeated overshoot', evidence: 'Repeated manual training observations',
    sampleCount: samples, expected: 'Improved touch stability', risk: 'Slower acquisition');

StateMap _latestProposal(StateMap s) => (s['proposals'] as List).last as StateMap;
String _proposalId(StateMap s) => _latestProposal(s)['id'] as String;

class _FailingStore extends MemoryCoachStore {
  bool fail = false;
  void Function()? beforeMutation;
  @override
  Future<StateMap> transaction(String deviceId, StateMutation mutate) {
    beforeMutation?.call();
    return super.transaction(deviceId, (state) {
      mutate(state);
      if (fail) {
        throw StateError('Simulated durable write failure');
      }
    });
  }
}

void main() {
  late MemoryCoachStore store;
  late GameModeGuard guard;
  late CalibrationWorkflow workflow;

  setUp(() {
    store = MemoryCoachStore();
    guard = GameModeGuard()..declareOfflineMode(GameMode.warehouse);
    workflow = CalibrationWorkflow(store: store, guard: guard, deviceId: _device);
  });

  test('full approval cycle preserves baseline, backup and every explicit decision', () async {
    await _baseline(workflow);
    var state = await _propose(workflow);
    final id = _proposalId(state);
    expect(_latestProposal(state)['status'], 'PROPOSED');
    expect(state['testingId'], isNull);
    expect((state['backups'] as List), isEmpty);
    expect((state['approved'] as Map)['settings'], {_key: 31.0});
    expect((state['notifications'] as List).single['body'], contains('31.0 → 30.0'));

    state = await workflow.approveForTest(id);
    expect(state['testingId'], id);
    expect((state['approved'] as Map)['number'], 1);
    expect((state['approved'] as Map)['settings'], {_key: 31.0});
    final backup = (state['backups'] as List).single as StateMap;
    expect((backup['snapshot'] as Map)['settings'], {_key: 31.0});
    expect(backup['deviceId'], _device);
    final candidate = (state['versions'] as List).last as StateMap;
    expect(candidate['status'], 'TESTING');
    expect(candidate['settings'], {_key: 30.0});
    expect(candidate['backupId'], backup['id']);
    expect((_latestProposal(state)['history'] as List).map((e) => e['status']),
      ['PROPOSED', 'APPROVED_FOR_TEST', 'BACKED_UP', 'TESTING']);
    await expectLater(() => workflow.approveFinal(id), throwsStateError);

    state = await workflow.recordTest(id,
      {..._metrics(improved: true), 'sampleCount': 5}, manualApplied: true);
    expect(_latestProposal(state)['status'], 'PASSED');
    expect((state['approved'] as Map)['settings'], {_key: 31.0});

    state = await workflow.approveFinal(id);
    expect((state['approved'] as Map)['settings'], {_key: 30.0});
    expect((state['approved'] as Map)['number'], 2);
    expect((state['approved'] as Map)['status'], 'APPROVED_FINAL');
    expect(_latestProposal(state)['status'], 'APPROVED_FINAL');
    expect(state['testingId'], isNull);
    expect((state['backups'] as List).single, backup);

    state = await workflow.restore();
    expect((state['approved'] as Map)['settings'], {_key: 31.0});
    expect((state['approved'] as Map)['number'], 3);
    expect((state['approved'] as Map)['restoredFrom'], 1);
    expect(_latestProposal(state)['status'], 'ROLLED_BACK');
    expect((state['backups'] as List).length, 2);
    expect((state['versions'] as List).map((v) => v['number']), [1, 2, 3]);
    expect((state['versions'] as List).first['settings'], {_key: 31.0});
  });

  test('new context baseline import preserves a full prior backup', () async {
    await workflow.saveBaseline({_key: 31});
    const other = 'AKM|Red Dot|None|20::camera';
    final state = await workflow.saveBaseline({other: 42});
    expect((state['approved'] as Map)['settings'], {_key: 31.0, other: 42.0});
    expect(((state['backups'] as List).single['snapshot'] as Map)['settings'],
      {_key: 31.0});
    await expectLater(() => workflow.saveBaseline({_key: 30}), throwsStateError);
  });

  test('baseline extension can be restored and that restore can be undone', () async {
    const other = 'AKM|Red Dot|None|20::camera';
    await workflow.saveBaseline({_key: 31});
    final extended = await workflow.saveBaseline({other: 42});
    final originalBackup = cloneState((extended['backups'] as List).single as StateMap);
    expect((extended['approved'] as Map)['backupId'], originalBackup['id']);

    final restored = await workflow.restore();
    expect((restored['approved'] as Map)['settings'], {_key: 31.0});
    expect((restored['approved'] as Map)['restoredFrom'], 1);
    expect((restored['approved'] as Map)['backupId'],
      (restored['backups'] as List).last['id']);

    final undone = await workflow.restore();
    expect((undone['approved'] as Map)['settings'], {_key: 31.0, other: 42.0});
    expect((undone['approved'] as Map)['number'], 4);
    expect((undone['approved'] as Map)['restoredFrom'], 2);
    expect((undone['backups'] as List).first, originalBackup);
    expect((undone['backups'] as List).length, 3);
    expect((undone['versions'] as List).map((v) => v['number']), [1, 2, 3, 4]);
  });

  test('undo restore returns the tested approved settings, never a pending trial', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.approveForTest(id);
    await workflow.recordTest(id,
      {..._metrics(improved: true), 'sampleCount': 5}, manualApplied: true);
    await workflow.approveFinal(id);

    final restored = await workflow.restore();
    expect((restored['approved'] as Map)['settings'], {_key: 31.0});
    final undone = await workflow.restore();
    expect((undone['approved'] as Map)['settings'], {_key: 30.0});
    expect((undone['approved'] as Map)['status'], 'APPROVED_FINAL');
    expect((undone['approved'] as Map)['restoredFrom'], 2);
    expect((undone['approved'] as Map)['testResults'], isNotNull);
    expect(undone['testingId'], isNull);
  });

  test('same-timestamp observations, proposals and backups retain unique identities', () async {
    final fixedTime = DateTime.utc(2026, 10, 7);
    final fixedGuard = GameModeGuard(now: () => fixedTime)
      ..declareOfflineMode(GameMode.warehouse);
    final isolated = CalibrationWorkflow(store: MemoryCoachStore(),
      guard: fixedGuard, deviceId: _device, now: () => fixedTime);
    await _baseline(isolated);
    final id = _proposalId(await _propose(isolated));
    await isolated.approveForTest(id);
    final state = await isolated.restore();
    final identities = <Object?>[
      ...(state['observations'] as List).map((v) => v['id']),
      ...(state['proposals'] as List).map((v) => v['id']),
      ...(state['backups'] as List).map((v) => v['id']),
    ];
    expect(identities, hasLength(8));
    expect(identities.toSet(), hasLength(identities.length));
    expect((state['versions'] as List).map((v) => v['number']), [1, 2, 3]);
    expect((state['versions'] as List).every(
      (v) => v['timestamp'] == fixedTime.toIso8601String()), isTrue);
  });

  test('proposals require repeated observations from exactly their current context', () async {
    await _baseline(workflow, count: 4);
    await expectLater(() => _propose(workflow, samples: 4), throwsStateError);
    await workflow.addObservation('aim', {
      'context': 'AKM|3x|Compensator|50', 'metrics': _metrics(),
    });
    await expectLater(() => _propose(workflow), throwsStateError);
    await workflow.addObservation('aim', {'context': _context, 'metrics': _metrics()});
    await expectLater(() => _propose(workflow, samples: 6), throwsStateError);
    final state = await _propose(workflow);
    expect(_latestProposal(state)['sampleCount'], 5);
    expect((_latestProposal(state)['sampleIds'] as List).length, 5);
  });

  test('a new approved baseline invalidates samples from the older version', () async {
    await _baseline(workflow);
    await workflow.saveBaseline({'AKM|Red Dot|None|20::ads': 40});
    await expectLater(() => _propose(workflow), throwsStateError);
  });

  test('pending proposal cannot be tested after its approved base changes', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.saveBaseline({'AKM|Red Dot|None|20::ads': 40});
    await expectLater(() => workflow.approveForTest(id), throwsStateError);
  });

  test('a missing metric is not imputed and cannot support a proposal', () async {
    await workflow.saveBaseline({_key: 31});
    for (var i = 0; i < 5; i++) {
      await workflow.addObservation('aim', {
        'context': _context, 'metrics': _metrics()..remove('fpsStability'),
      });
    }
    await expectLater(() => _propose(workflow), throwsStateError);
  });

  test('proposal must explain evidence and use a small supported change', () async {
    await _baseline(workflow);
    Future<StateMap> propose({double value = 30, String reason = 'Overshoot'}) =>
      workflow.propose(key: _key, proposed: value, reason: reason,
        evidence: '5 samples', sampleCount: 5, expected: 'More stable', risk: 'Slower');
    await expectLater(() => propose(value: 31), throwsArgumentError);
    await expectLater(() => propose(value: 20), throwsArgumentError);
    await expectLater(() => propose(reason: ' '), throwsArgumentError);
    await expectLater(() => propose(value: double.nan), throwsArgumentError);
  });

  test('testing requires user confirmation and Warehouse or Unranked evidence', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.approveForTest(id);
    final metrics = {..._metrics(improved: true), 'sampleCount': 5.0};
    await expectLater(() => workflow.recordTest(id, metrics, manualApplied: false),
      throwsStateError);
    guard.declareOfflineMode(GameMode.training);
    await expectLater(() => workflow.recordTest(id, metrics, manualApplied: true),
      throwsStateError);
    guard.declareOfflineMode(GameMode.safeUnranked);
    final state = await workflow.recordTest(id, metrics, manualApplied: true);
    expect(_latestProposal(state)['status'], 'PASSED');
    expect((_latestProposal(state)['test'] as Map)['mode'], 'SAFE_UNRANKED');
  });

  test('failed comparison stays experimental and can be retested before approval', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.approveForTest(id);
    var state = await workflow.recordTest(id, {..._metrics(), 'sampleCount': 5},
      manualApplied: true);
    expect(_latestProposal(state)['status'], 'FAILED');
    expect((state['approved'] as Map)['settings'], {_key: 31.0});
    await expectLater(() => workflow.approveFinal(id), throwsStateError);
    state = await workflow.recordTest(id,
      {..._metrics(improved: true), 'sampleCount': 5}, manualApplied: true);
    expect(_latestProposal(state)['status'], 'PASSED');
    await workflow.approveFinal(id);
  });

  test('defer and reject do not change the approved settings', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    var state = await workflow.defer(id);
    expect(_latestProposal(state)['status'], 'DEFERRED');
    expect(state['testingId'], isNull);
    state = await workflow.reject(id);
    expect(_latestProposal(state)['status'], 'REJECTED');
    expect((state['approved'] as Map)['settings'], {_key: 31.0});
    expect(state['backups'], isEmpty);
    await expectLater(() => workflow.approveForTest(id), throwsStateError);
    await expectLater(() => workflow.reject(id), throwsStateError);
  });

  test('deferred proposal can enter testing only through explicit trial approval', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.defer(id);
    final state = await workflow.approveForTest(id);
    expect(_latestProposal(state)['status'], 'TESTING');
    expect((state['backups'] as List).length, 1);
  });

  test('rejecting or restoring a trial leaves no active experiment', () async {
    for (final restore in [false, true]) {
      final isolated = CalibrationWorkflow(store: MemoryCoachStore(),
        guard: guard, deviceId: _device);
      await _baseline(isolated);
      final id = _proposalId(await _propose(isolated));
      await isolated.approveForTest(id);
      final state = restore ? await isolated.restore() : await isolated.reject(id);
      expect(state['testingId'], isNull);
      expect((state['approved'] as Map)['settings'], {_key: 31.0});
      expect(_latestProposal(state)['status'], restore ? 'ROLLED_BACK' : 'REJECTED');
      await expectLater(() => isolated.approveFinal(id), throwsStateError);
    }
  });

  test('testing prevents competing changes and baseline writes', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.approveForTest(id);
    await expectLater(() => workflow.approveForTest(id), throwsStateError);
    await expectLater(() => _propose(workflow), throwsStateError);
    await expectLater(() => workflow.saveBaseline({'AKM|Red Dot|None|20::ads': 40}),
      throwsStateError);
    await expectLater(() => workflow.defer(id), throwsStateError);
  });

  test('missing backup blocks both recording a test and final approval', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.approveForTest(id);
    final metrics = {..._metrics(improved: true), 'sampleCount': 5.0};
    await workflow.recordTest(id, metrics, manualApplied: true);
    // Simulate corrupted persisted state; production SQLite disallows deletion.
    await store.transaction(_device, (s) => (s['backups'] as List).clear());
    await expectLater(() => workflow.recordTest(id, metrics, manualApplied: true),
      throwsStateError);
    await expectLater(() => workflow.approveFinal(id), throwsStateError);
    await expectLater(workflow.restore, throwsStateError);
  });

  test('all mutating operations fail closed in Ranked and unknown modes', () async {
    await _baseline(workflow);
    final id = _proposalId(await _propose(workflow));
    await workflow.approveForTest(id);
    final unchanged = await workflow.read();
    for (final mode in [GameMode.rankedBlocked, GameMode.unknownBlocked]) {
      guard.declareOfflineMode(mode);
      final operations = <Future<StateMap> Function()>[
        () => workflow.saveBaseline({'AKM|Red Dot|None|20::ads': 40}),
        () => workflow.addObservation('aim', {'context': _context, 'metrics': _metrics()}),
        () => _propose(workflow),
        () => workflow.approveForTest(id),
        () => workflow.recordTest(id, {..._metrics(improved: true), 'sampleCount': 5},
          manualApplied: true),
        () => workflow.approveFinal(id),
        () => workflow.reject(id),
        () => workflow.defer(id),
        workflow.restore,
      ];
      for (final operation in operations) {
        await expectLater(operation, throwsStateError, reason: mode.code);
        expect(await workflow.read(), unchanged);
      }
    }
  });

  test('trial and backup roll back together if persistence fails', () async {
    final failing = _FailingStore();
    final isolated = CalibrationWorkflow(store: failing, guard: guard, deviceId: _device);
    await _baseline(isolated);
    final id = _proposalId(await _propose(isolated));
    final before = await isolated.read();
    failing.fail = true;
    await expectLater(() => isolated.approveForTest(id), throwsStateError);
    expect(await isolated.read(), before);
    failing.fail = false;
    final state = await isolated.approveForTest(id);
    expect(state['testingId'], id);
    expect((state['backups'] as List).length, 1);
  });

  test('guard is checked again inside the write transaction', () async {
    final delayed = _FailingStore();
    final isolated = CalibrationWorkflow(store: delayed, guard: guard, deviceId: _device);
    delayed.beforeMutation = guard.invalidate;
    await expectLater(() => isolated.saveBaseline({_key: 31}), throwsStateError);
    expect((await isolated.read())['versions'], isEmpty);
  });

  test('device profiles cannot inherit settings or proposals from another device', () async {
    await _baseline(workflow);
    await _propose(workflow);
    final tablet = CalibrationWorkflow(store: store, guard: guard, deviceId: 'physical-ipad-b');
    final state = await tablet.read();
    expect((state['approved'] as Map)['settings'], isEmpty);
    expect(state['proposals'], isEmpty);
    await tablet.saveBaseline({_key: 55});
    expect(((await workflow.read())['approved'] as Map)['settings'], {_key: 31.0});
    expect(((await tablet.read())['approved'] as Map)['settings'], {_key: 55.0});
  });
}
