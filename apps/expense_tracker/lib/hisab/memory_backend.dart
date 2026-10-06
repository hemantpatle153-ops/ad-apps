import 'dart:async';

import 'backend.dart';
import 'model.dart';

/// A database kept in memory, shared by any number of [MemoryHisabBackend]
/// "phones". Used by tests and the widget previews. It applies the same
/// read rule as the real database: a log is readable only by its members.
class MemoryDatabase {
  MemoryDatabase({int startMs = 1700000000000}) : nowMs = startMs;

  final Map<String, Object?> root = {};
  int nowMs;
  int _keys = 0;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Set to make every call fail as if offline.
  bool offline = false;

  /// Writes the next call should reject, as the security rules would.
  bool Function(Map<String, Object?> writes, String uid)? reject;

  int writes = 0;

  void advance(Duration d) {
    nowMs += d.inMilliseconds;
  }

  static List<String> _parts(String path) =>
      path.split('/').where((p) => p.isNotEmpty).toList();

  Object? read(String path) {
    Object? node = root;
    for (final p in _parts(path)) {
      if (node is! Map) return null;
      node = node[p];
    }
    return _copy(node);
  }

  static Object? _copy(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': _copy(e.value)} : v;

  Object? _resolve(Object? v) => switch (v) {
        ServerTime() => nowMs,
        Map() => {for (final e in v.entries) '${e.key}': _resolve(e.value)},
        _ => v,
      };

  void apply(Map<String, Object?> writes) {
    for (final w in writes.entries) {
      final parts = _parts(w.key);
      final value = _resolve(w.value);
      var node = root;
      for (final p in parts.take(parts.length - 1)) {
        final next = node[p];
        if (next is Map<String, Object?>) {
          node = next;
        } else {
          if (value == null) {
            node = <String, Object?>{};
            break;
          }
          final m = <String, Object?>{};
          node[p] = m;
          node = m;
        }
      }
      if (value == null || (value is Map && value.isEmpty)) {
        node.remove(parts.last);
      } else {
        node[parts.last] = value;
      }
    }
    _prune(root);
    this.writes++;
    _changes.add(null);
  }

  /// Like the real database: empty objects don't exist.
  static void _prune(Map<String, Object?> m) {
    for (final k in m.keys.toList()) {
      final v = m[k];
      if (v is Map<String, Object?>) {
        _prune(v);
        if (v.isEmpty) m.remove(k);
      }
    }
  }

  bool canRead(String path, String uid) {
    final parts = _parts(path);
    if (parts.length >= 2 && parts[0] == 'hisab') {
      final members = read('hisab/${parts[1]}/members');
      return members is Map && members.containsKey(uid);
    }
    return true;
  }

  String newKey() {
    _keys++;
    return '-K${nowMs.toRadixString(36)}${_keys.toString().padLeft(6, '0')}';
  }
}

class MemoryHisabBackend implements HisabBackend {
  MemoryHisabBackend(this.db, this.uid);
  final MemoryDatabase db;
  final String uid;

  void _check() {
    if (db.offline) throw HisabException.offline;
  }

  @override
  Future<String> signIn() async {
    _check();
    return uid;
  }

  @override
  Future<void> update(Map<String, Object?> writes) async {
    _check();
    if (db.reject?.call(writes, uid) ?? false) throw HisabException.denied;
    db.apply(writes);
  }

  @override
  Future<Object?> get(String path) async {
    _check();
    return db.canRead(path, uid) ? db.read(path) : null;
  }

  @override
  Stream<Object?> watch(String path) {
    late StreamController<Object?> c;
    StreamSubscription<void>? sub;
    Object? last = const _Unset();
    void emit() {
      final v = db.canRead(path, uid) ? db.read(path) : null;
      final s = '$v';
      if (s == '$last') return;
      last = v;
      c.add(v);
    }

    c = StreamController<Object?>(
      onListen: () {
        sub = db._changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  String newKey() => db.newKey();

  @override
  int nowMs() => db.nowMs;

  @override
  Future<List<String>> expired(int beforeMs) async {
    _check();
    final gc = db.read('hisabGc');
    if (gc is! Map) return [];
    final list = [
      for (final e in gc.entries)
        if (e.value is Map && ((e.value as Map)['t'] as num? ?? 0) <= beforeMs)
          (e.key as String, (e.value as Map)['t'] as num)
    ]..sort((x, y) => x.$2.compareTo(y.$2));
    return [for (final x in list.take(20)) x.$1];
  }
}

class _Unset {
  const _Unset();
  @override
  String toString() => '<unset>';
}
