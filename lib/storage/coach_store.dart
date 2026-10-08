import 'dart:async';
import 'dart:convert';

typedef StateMap = Map<String, dynamic>;
typedef StateMutation = void Function(StateMap state);
StateMap cloneState(StateMap state) => jsonDecode(jsonEncode(state)) as StateMap;

StateMap emptyState(String deviceId) => {
  'schemaVersion': 2,
  'deviceId': deviceId,
  'approved': {'number': 0, 'settings': <String, dynamic>{}, 'deviceId': deviceId, 'profile': 'NON_GYRO'},
  'versions': <dynamic>[], 'proposals': <dynamic>[], 'observations': <dynamic>[],
  'backups': <dynamic>[], 'notifications': <dynamic>[], 'testingId': null,
};

abstract interface class CoachStore {
  Future<StateMap> read(String deviceId);
  /// Recheck volatile permissions after preparation and immediately before
  /// committing. Throwing from [authorizeCommit] rolls back the whole mutation.
  Future<StateMap> transaction(String deviceId, StateMutation mutate,
    {void Function()? authorizeCommit});
  Future<void> saveDevice(String deviceId, Map<String, Object?> data);
  Future<void> close();
}

/// Used by unit/widget tests. The production entry point always uses SQLite.
class MemoryCoachStore implements CoachStore {
  final Map<String, StateMap> _states = {};
  Future<void> _tail = Future.value();
  @override
  Future<StateMap> read(String deviceId) async => cloneState(_states[deviceId] ?? emptyState(deviceId));
  @override
  Future<StateMap> transaction(String deviceId, StateMutation mutate,
    {void Function()? authorizeCommit}) {
    final result = Completer<StateMap>();
    _tail = _tail.then((_) {
      try {
        final next = cloneState(_states[deviceId] ?? emptyState(deviceId));
        mutate(next);
        final committed = cloneState(next);
        authorizeCommit?.call();
        _states[deviceId] = committed;
        result.complete(cloneState(committed));
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }
  @override
  Future<void> saveDevice(String deviceId, Map<String, Object?> data) async {}
  @override
  Future<void> close() async {}
}
