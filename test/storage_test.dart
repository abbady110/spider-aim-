import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spider_aim/core/calibration_workflow.dart';
import 'package:spider_aim/game_mode_guard/game_mode_guard.dart';
import 'package:spider_aim/storage/coach_store.dart';
import 'package:spider_aim/storage/sqlite_coach_store.dart';

const _device = 'phone-a';
const _context = 'M416|3x|Compensator|50';
const _key = '$_context::ads';

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

Future<String> _startTrial(CalibrationWorkflow workflow) async {
  await workflow.saveBaseline({_key: 31});
  for (var i = 0; i < 5; i++) {
    await workflow.addObservation('aim', {'context': _context, 'metrics': _metrics()});
  }
  final state = await workflow.propose(key: _key, proposed: 30,
    reason: 'Overshoot', evidence: '5 manual observations', sampleCount: 5,
    expected: 'Better stability', risk: 'Slower target acquisition');
  final id = (state['proposals'] as List).last['id'] as String;
  await workflow.approveForTest(id);
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  final openStores = <SqliteCoachStore>[];

  Future<SqliteCoachStore> open() async {
    final store = await SqliteCoachStore.open(path: path, factory: databaseFactoryFfi);
    openStores.add(store);
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('spider-aim-storage-test-');
    path = '${directory.path}/coach.db';
  });
  tearDown(() async {
    for (final store in openStores) {
      if (store.db.isOpen) {
        await store.close();
      }
    }
    openStores.clear();
    await directory.delete(recursive: true);
  });

  test('SQLite schema and device reports persist with separate profiles', () async {
    final store = await open();
    expect(await store.db.getVersion(), 2);
    await store.saveDevice(_device, {'name': 'Phone', 'touchSamplingRateHz': null});
    await store.saveDevice('tablet-b', {'name': 'Tablet'});
    final phone = CalibrationWorkflow(store: store,
      guard: GameModeGuard()..declareOfflineMode(GameMode.warehouse), deviceId: _device);
    final tablet = CalibrationWorkflow(store: store,
      guard: GameModeGuard()..declareOfflineMode(GameMode.warehouse), deviceId: 'tablet-b');
    await phone.saveBaseline({_key: 31});
    expect(((await tablet.read())['approved'] as Map)['settings'], isEmpty);
    await tablet.saveBaseline({_key: 55});
    expect(((await phone.read())['approved'] as Map)['settings'], {_key: 31.0});
    expect(((await tablet.read())['approved'] as Map)['settings'], {_key: 55.0});
    expect((await store.db.query('devices')).length, 2);
    expect((await store.db.query('profiles')).length, 2);
  });

  test('reopening mid-trial retains approved, testing and immutable backup pointers', () async {
    var store = await open();
    var guard = GameModeGuard()..declareOfflineMode(GameMode.warehouse);
    var workflow = CalibrationWorkflow(store: store, guard: guard, deviceId: _device);
    final id = await _startTrial(workflow);
    final before = await workflow.read();
    await store.close();

    store = await open();
    guard = GameModeGuard();
    workflow = CalibrationWorkflow(store: store, guard: guard, deviceId: _device);
    expect(await workflow.read(), before);
    expect((before['approved'] as Map)['settings'], {_key: 31.0});
    expect(before['testingId'], id);
    expect((before['backups'] as List).length, 1);
    expect((before['versions'] as List).last['status'], 'TESTING');
    await expectLater(() => workflow.approveFinal(id), throwsStateError);
    guard.declareOfflineMode(GameMode.warehouse);
    await expectLater(() => workflow.approveFinal(id), throwsStateError);

    await workflow.recordTest(id,
      {..._metrics(improved: true), 'sampleCount': 5}, manualApplied: true);
    await workflow.approveFinal(id);
    await store.close();
    store = await open();
    final reopened = await store.read(_device);
    expect((reopened['approved'] as Map)['settings'], {_key: 30.0});
    expect(reopened['testingId'], isNull);
    expect((reopened['backups'] as List).length, 1);
    expect((await store.db.query('events')).isNotEmpty, isTrue);
  });

  test('SQLite triggers prohibit direct backup modification and deletion', () async {
    final store = await open();
    final workflow = CalibrationWorkflow(store: store,
      guard: GameModeGuard()..declareOfflineMode(GameMode.warehouse), deviceId: _device);
    await _startTrial(workflow);
    final rows = await store.db.query('backups');
    final id = rows.single['id'];
    await expectLater(() => store.db.delete('backups', where: 'id = ?', whereArgs: [id]),
      throwsA(isA<DatabaseException>()));
    await expectLater(() => store.db.update('backups', {'payload': '{}'},
      where: 'id = ?', whereArgs: [id]), throwsA(isA<DatabaseException>()));
    expect(await store.db.query('backups'), rows);
  });

  test('restore undo link survives closing and reopening SQLite', () async {
    var store = await open();
    final guard = GameModeGuard()..declareOfflineMode(GameMode.warehouse);
    var workflow = CalibrationWorkflow(store: store, guard: guard, deviceId: _device);
    await workflow.saveBaseline({_key: 31});
    const other = 'AKM|Red Dot|None|20::ads';
    await workflow.saveBaseline({other: 45});
    final restored = await workflow.restore();
    expect((restored['approved'] as Map)['settings'], {_key: 31.0});
    await store.close();

    store = await open();
    workflow = CalibrationWorkflow(store: store, guard: guard, deviceId: _device);
    final undone = await workflow.restore();
    expect((undone['approved'] as Map)['settings'], {_key: 31.0, other: 45.0});
    expect((undone['approved'] as Map)['restoredFrom'], 2);
    expect((undone['backups'] as List).length, 3);
    expect((await store.db.query('backups')).length, 3);
  });

  test('backup edits or removal through profile transactions are rejected atomically', () async {
    final store = await open();
    final workflow = CalibrationWorkflow(store: store,
      guard: GameModeGuard()..declareOfflineMode(GameMode.warehouse), deviceId: _device);
    await _startTrial(workflow);
    final before = await workflow.read();
    await expectLater(() => store.transaction(_device, (state) {
      final backup = (state['backups'] as List).first as StateMap;
      ((backup['snapshot'] as Map)['settings'] as Map)[_key] = 999;
    }), throwsStateError);
    expect(await workflow.read(), before);
    await expectLater(() => store.transaction(_device, (state) {
      (state['backups'] as List).clear();
    }), throwsStateError);
    expect(await workflow.read(), before);
  });

  test('failed transaction commits neither profile nor audit event', () async {
    final store = await open();
    await store.transaction(_device, (state) {
      state['testingId'] = null;
    });
    final before = await store.read(_device);
    final events = await store.db.query('events');
    await expectLater(() => store.transaction(_device, (state) {
      (state['approved'] as Map)['settings'] = {_key: 999};
      state['testingId'] = 'uncommitted';
      throw StateError('Simulated interruption');
    }), throwsStateError);
    expect(await store.read(_device), before);
    expect(await store.db.query('events'), events);
  });

  test('schema v1 migrates additively without dropping approved or trial state', () async {
    final legacy = emptyState(_device)
      ..['schemaVersion'] = 1
      ..remove('notifications');
    legacy['approved'] = {
      'number': 1, 'settings': {_key: 31.0}, 'deviceId': _device,
      'profile': 'NON_GYRO', 'status': 'APPROVED_FINAL',
    };
    legacy['versions'] = [cloneState(legacy['approved'] as StateMap)];
    legacy['testingId'] = 'legacy-trial';
    final previous = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('CREATE TABLE devices (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
        await db.execute('CREATE TABLE profiles (device_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
        await db.execute('CREATE TABLE backups (id TEXT PRIMARY KEY, device_id TEXT NOT NULL, payload TEXT NOT NULL)');
        await db.execute("CREATE TRIGGER protect_backup_delete BEFORE DELETE ON backups BEGIN SELECT RAISE(ABORT, 'Backup is immutable'); END");
        await db.execute("CREATE TRIGGER protect_backup_update BEFORE UPDATE ON backups BEGIN SELECT RAISE(ABORT, 'Backup is immutable'); END");
      }));
    await previous.insert('profiles', {'device_id': _device, 'payload': jsonEncode(legacy)});
    await previous.close();
    final store = await open();
    final migrated = await store.read(_device);
    expect(await store.db.getVersion(), 2);
    expect(migrated['schemaVersion'], 2);
    expect(migrated['notifications'], isEmpty);
    expect(migrated['approved'], legacy['approved']);
    expect(migrated['versions'], legacy['versions']);
    expect(migrated['testingId'], 'legacy-trial');
    await store.transaction(_device, (state) {});
    expect((await store.db.query('events')).length, 1);
    final indexes = await store.db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
    expect(indexes.map((row) => row['name']), contains('events_by_device'));
  });

  test('corrupted cross-device profile identity is refused on read', () async {
    final store = await open();
    await store.db.insert('profiles', {
      'device_id': _device,
      'payload': jsonEncode(emptyState('different-device')),
    });
    await expectLater(() => store.read(_device), throwsStateError);
  });

  test('read results are detached from persisted state', () async {
    final store = await open();
    await store.transaction(_device, (state) {
      (state['approved'] as Map)['settings'] = {_key: 31.0};
    });
    final detached = await store.read(_device);
    ((detached['approved'] as Map)['settings'] as Map)[_key] = 999;
    expect(((await store.read(_device))['approved'] as Map)['settings'], {_key: 31.0});
  });
}
