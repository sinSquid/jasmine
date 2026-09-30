import 'dart:async';
import 'dart:collection';

/// Keeps speculative image work behind the visible page's requests.
class ImagePreloader {
  ImagePreloader(this._load);

  static const maxConcurrent = 2;
  static const maxPending = 4;

  final Future<void> Function(int index) _load;
  final Set<int> _active = <int>{};
  final Queue<int> _pending = Queue<int>();
  bool _disposed = false;

  void schedule(Iterable<int> indices) {
    if (_disposed) return;
    _pending.clear();
    for (final index in indices) {
      if (_pending.length >= maxPending) break;
      if (!_active.contains(index) && !_pending.contains(index)) {
        _pending.addLast(index);
      }
    }
    _drain();
  }

  void _drain() {
    while (
        !_disposed && _active.length < maxConcurrent && _pending.isNotEmpty) {
      final index = _pending.removeFirst();
      _active.add(index);
      unawaited(Future.sync(() => _load(index))
          .then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      )
          .whenComplete(() {
        _active.remove(index);
        _drain();
      }));
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
