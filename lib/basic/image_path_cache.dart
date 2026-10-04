import 'dart:io';

/// Completed native image paths only; in-flight merging stays in the scheduler.
/// A hit performs one asynchronous existence check before bypassing native work.
class ImagePathCache<K extends Object> {
  ImagePathCache({
    this.capacity = 128,
    this.ttl = const Duration(minutes: 2),
    Future<bool> Function(String)? fileExists,
    Duration Function()? elapsed,
  })  : assert(capacity > 0),
        assert(ttl > Duration.zero),
        _fileExists = fileExists ?? _exists,
        _elapsed = elapsed ?? _monotonicClock();

  final int capacity;
  final Duration ttl;
  final Future<bool> Function(String) _fileExists;
  final Duration Function() _elapsed;
  final _entries = <K, _ImagePathEntry>{};
  int _generation = 0;
  int _mutations = 0;

  static Future<bool> _exists(String path) => File(path).exists();

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  Future<String> getOrLoad(K key, Future<String> Function() load) {
    final entry = _entries[key];
    if (entry != null) {
      if (_elapsed() < entry.expiresAt) {
        return _validate(key, entry, load);
      }
      _entries.remove(key);
    }
    // Do not merge here: every miss must reach the scheduler so visible work
    // can promote an existing background request and detach its cancellation.
    return _load(key, load);
  }

  Future<String> _validate(
      K key, _ImagePathEntry entry, Future<String> Function() load) async {
    bool exists;
    try {
      exists = await _fileExists(entry.path);
    } on FileSystemException {
      // Let native code resolve inaccessible/moved files or report its error.
      exists = false;
    }
    if (identical(_entries[key], entry)) {
      _entries.remove(key);
      if (exists && _elapsed() < entry.expiresAt) {
        _entries[key] = entry;
        return entry.path;
      }
    }
    // Invalidated while checking the disk: never return the old path.
    return _load(key, load);
  }

  Future<String> _load(K key, Future<String> Function() load) async {
    final generation = _generation;
    final path = await load();
    if (_mutations == 0 && generation == _generation && path.isNotEmpty) {
      _entries.remove(key);
      if (_entries.length >= capacity) {
        _entries.remove(_entries.keys.first);
      }
      _entries[key] = _ImagePathEntry(path, _elapsed() + ttl);
    }
    return path;
  }

  void invalidate(K key) {
    _entries.remove(key);
    // A single epoch avoids an unbounded map of deleted keys. Conservatively
    // discard all older pending writes, while preserving other completed hits.
    _generation++;
  }

  void clear() {
    _entries.clear();
    _generation++;
  }

  Future<T> invalidateDuring<T>(Future<T> Function() action) async {
    clear();
    _mutations++;
    try {
      return await action();
    } finally {
      _mutations--;
      clear();
    }
  }
}

class _ImagePathEntry {
  const _ImagePathEntry(this.path, this.expiresAt);
  final String path;
  final Duration expiresAt;
}
