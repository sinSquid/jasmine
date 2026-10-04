import 'dart:async';
import 'dart:collection';
import '../../basic/native_call_scheduler.dart';

/// Keeps speculative image work behind the visible page's requests.
class ImagePreloader {
  ImagePreloader(this._load);

  static const maxConcurrent = 2;
  static const maxPending = 4;

  final Future<void> Function(int index) _load;
  final Set<int> _active = <int>{};
  final Queue<int> _pending = Queue<int>();
  bool _disposed = false;
  final Set<int> _wanted = {};
  final Set<int> _completed = {};

  void schedule(Iterable<int> indices) {
    if (_disposed) return;
    _wanted
      ..clear()
      ..addAll(indices.take(maxPending + maxConcurrent));
    _completed.retainAll(_wanted);
    _pending.clear();
    for (final index in _wanted) {
      if (_pending.length < maxPending &&
          !_active.contains(index) &&
          !_completed.contains(index) &&
          !_pending.contains(index)) {
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
      unawaited(NativeCallScheduler.speculative(
          () => Future.sync(() => _load(index)),
          isCancelled: () => _disposed || !_wanted.contains(index)).then<void>(
        (_) {
          if (!_disposed && _wanted.contains(index)) _completed.add(index);
        },
        onError: (Object _, StackTrace __) {},
      ).whenComplete(() {
        _active.remove(index);
        _drain();
      }));
    }
  }

  void dispose() {
    _disposed = true;
    _wanted.clear();
    _completed.clear();
    _pending.clear();
  }
}
