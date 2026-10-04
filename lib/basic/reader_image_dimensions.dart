import 'dart:ui';

final readerImageDimensions = ReaderImageDimensions();

bool isValidReaderImageSize(Size? size) =>
    size != null &&
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

/// A small, short-lived metadata cache; it never owns decoded image pixels.
class ReaderImageDimensions {
  ReaderImageDimensions({
    this.capacity = 128,
    this.ttl = const Duration(minutes: 2),
    Duration Function()? elapsed,
  })  : assert(capacity > 0 && capacity <= 128),
        assert(ttl > Duration.zero && ttl <= const Duration(minutes: 2)),
        _elapsed = elapsed ?? _monotonicClock();

  final int capacity;
  final Duration ttl;
  final Duration Function() _elapsed;
  final _entries = <(int, String), _DimensionsEntry>{};
  int _generation = 0;

  /// Capture before asynchronous metadata reads and pass back to [put].
  int get generation => _generation;

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  Size? get(int id, String imageName) {
    final key = (id, imageName);
    final entry = _entries.remove(key);
    if (entry == null || _elapsed() >= entry.expiresAt) return null;
    _entries[key] = entry;
    return entry.size;
  }

  void put(int id, String imageName, Size size, {int? generation}) {
    if (!isValidReaderImageSize(size) ||
        (generation != null && generation != _generation)) {
      return;
    }
    final key = (id, imageName);
    _entries.remove(key);
    if (_entries.length >= capacity) _entries.remove(_entries.keys.first);
    _entries[key] = _DimensionsEntry(size, _elapsed() + ttl);
  }

  void invalidate(int id, String imageName) {
    _entries.remove((id, imageName));
    // One bounded epoch rejects stale pending writes without retaining a map
    // of every previously invalidated page.
    _generation++;
  }

  void clear() {
    _entries.clear();
    _generation++;
  }
}

class _DimensionsEntry {
  const _DimensionsEntry(this.size, this.expiresAt);
  final Size size;
  final Duration expiresAt;
}
