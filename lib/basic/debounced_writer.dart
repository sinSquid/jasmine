import 'dart:async';

/// One write in flight and one latest pending value, regardless of event rate.
class DebouncedWriter<T> {
  DebouncedWriter(this.write,
      {this.delay = const Duration(milliseconds: 350), required this.onError});
  final Future<void> Function(T) write;
  final void Function(Object, StackTrace) onError;
  final Duration delay;
  Timer? _timer;
  T? _pending;
  bool _hasPending = false;
  Future<void>? _running;
  bool _closed = false;

  void add(T value) {
    if (_closed) return;
    _pending = value;
    _hasPending = true;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_running != null) {
      await _running;
      if (_hasPending) await flush();
      return;
    }
    if (!_hasPending) return;
    final value = _pending as T;
    _hasPending = false;
    final completion = Completer<void>();
    _running = completion.future;
    try {
      await write(value);
    } catch (e, st) {
      onError(e, st);
    } finally {
      _running = null;
      completion.complete();
    }
    if (_hasPending && !(_timer?.isActive ?? false)) await flush();
  }

  Future<void> close() async {
    _closed = true;
    await flush();
  }
}
