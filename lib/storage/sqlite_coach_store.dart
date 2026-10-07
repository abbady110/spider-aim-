import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'coach_store.dart';

/// SQLite transactions atomically persist approved, testing and backup pointers.
/// Approved backups have no deletion API; SQL triggers reject update/delete.
class SqliteCoachStore implements CoachStore {
  SqliteCoachStore(this.db);
  final Database db;
  static const schemaVersion = 2;
  static Future<SqliteCoachStore> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? '${await f.getDatabasesPath()}/spider_aim.db';
    final database = await f.openDatabase(dbPath, options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA synchronous = FULL');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _migrateV2(db);
      },
      onUpgrade: (db, old, current) async {
        if (old < 2) {
          await _migrateV2(db);
        }
      },
    ));
    return SqliteCoachStore(database);
  }
  static Future<void> _createV1(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE devices (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await db.execute('CREATE TABLE profiles (device_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await db.execute('CREATE TABLE backups (id TEXT PRIMARY KEY, device_id TEXT NOT NULL, payload TEXT NOT NULL)');
    await db.execute("CREATE TRIGGER protect_backup_delete BEFORE DELETE ON backups BEGIN SELECT RAISE(ABORT, 'Backup is immutable'); END");
    await db.execute("CREATE TRIGGER protect_backup_update BEFORE UPDATE ON backups BEGIN SELECT RAISE(ABORT, 'Backup is immutable'); END");
  }
  static Future<void> _migrateV2(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, timestamp TEXT NOT NULL, payload TEXT NOT NULL)');
    await db.execute('CREATE INDEX IF NOT EXISTS events_by_device ON events(device_id)');
  }
  @override
  Future<StateMap> read(String deviceId) async {
    final rows = await db.query('profiles', where: 'device_id = ?', whereArgs: [deviceId]);
    return rows.isEmpty ? emptyState(deviceId) : _decode(rows.first['payload'] as String, deviceId);
  }
  StateMap _decode(String payload, String deviceId) {
    final state = jsonDecode(payload) as StateMap;
    // Additive migration preserves all approved and testing state.
    state.putIfAbsent('notifications', () => <dynamic>[]);
    state['schemaVersion'] = schemaVersion;
    if (state['deviceId'] != deviceId) {
      throw StateError('Device profile mismatch');
    }
    return state;
  }
  @override
  Future<StateMap> transaction(String deviceId, StateMutation mutate) => db.transaction((txn) async {
    final rows = await txn.query('profiles', where: 'device_id = ?', whereArgs: [deviceId]);
    final next = rows.isEmpty ? emptyState(deviceId) : _decode(rows.first['payload'] as String, deviceId);
    mutate(next);
    final savedBackups = await txn.query('backups', where: 'device_id = ?', whereArgs: [deviceId]);
    final nextBackups = (next['backups'] as List).cast<Map<String, dynamic>>();
    if (nextBackups.map((b) => b['id']).toSet().length != nextBackups.length) {
      throw StateError('Duplicate backup identity');
    }
    for (final saved in savedBackups) {
      final matches = nextBackups.where((b) => b['id'] == saved['id']);
      if (matches.length != 1 || jsonEncode(matches.single) != saved['payload']) {
        throw StateError('An immutable backup cannot be removed or changed');
      }
    }
    for (final raw in next['backups'] as List) {
      final backup = raw as Map<String, dynamic>;
      if (backup['deviceId'] != deviceId) {
        throw StateError('Backup belongs to a different device');
      }
      final existing = await txn.query('backups', where: 'id = ?', whereArgs: [backup['id']]);
      final encoded = jsonEncode(backup);
      if (existing.isEmpty) {
        await txn.insert('backups', {'id': backup['id'], 'device_id': deviceId, 'payload': encoded});
      } else if (existing.first['payload'] != encoded) {
        throw StateError('Backup integrity violation');
      }
    }
    await txn.insert('profiles', {'device_id': deviceId, 'payload': jsonEncode(next)}, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('events', {'device_id': deviceId, 'timestamp': DateTime.now().toUtc().toIso8601String(), 'payload': jsonEncode({'approved': (next['approved'] as Map)['number'], 'testingId': next['testingId'], 'versions': (next['versions'] as List).length})});
    return cloneState(next);
  });
  @override
  Future<void> saveDevice(String deviceId, Map<String, Object?> data) async {
    await db.insert('devices', {'id': deviceId, 'payload': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  @override
  Future<void> close() => db.close();
}
