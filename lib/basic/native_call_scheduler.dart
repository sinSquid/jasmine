import 'dart:async';
import 'dart:collection';

/// Timeouts bound caller latency, not native execution. A timed-out running
/// operation retains its permit until the platform actually completes it.
class NativeCallScheduler {
  NativeCallScheduler({
    this.maxActive = 4,
    this.maxWaiting = 32,
    this.maxBackground = 1,
    this.waitTimeout = const Duration(seconds: 30),
  });

  final int maxActive, maxWaiting, maxBackground;
  final Duration waitTimeout;
  final _foreground = Queue<_Call>();
  final _background = Queue<_Call>();
  int _active = 0, _activeBackground = 0;
  final Set<Object> _activeKeys = {};
  static final _backgroundKey = Object();
  static final _cancelledKey = Object();

  static Future<T> speculative<T>(Future<T> Function() action,
      {required bool Function() isCancelled}) {
    return runZoned(action, zoneValues: {
      _backgroundKey: true,
      _cancelledKey: isCancelled,
    });
  }

  Future<T> run<T>(Future<T> Function() action,
      {Duration timeout = const Duration(seconds: 60), Object? serialKey}) {
    final background = Zone.current[_backgroundKey] == true;
    final cancelled = Zone.current[_cancelledKey] as bool Function()?;
    if (cancelled?.call() == true) {
      return Future.error(StateError('预加载已取消'));
    }
    _drain();
    final result = Completer<T>();
    late _Call call;
    call = _Call(background, serialKey, cancelled, () {
      _active++;
      if (serialKey != null) _activeKeys.add(serialKey);
      if (background) _activeBackground++;
      final native = Future<T>.sync(action);
      native.then<void>((_) => _release(background, serialKey),
          onError: (Object _, StackTrace __) =>
              _release(background, serialKey));
      native.timeout(timeout, onTimeout: () {
        throw TimeoutException('操作超时，结果尚未确认；请勿重复提交，持续无响应时重启应用', timeout);
      }).then(result.complete, onError: result.completeError);
    }, (Object error) {
      if (!result.isCompleted) result.completeError(error);
    });
    if (_active < maxActive &&
        (!background || _activeBackground < maxBackground) &&
        (serialKey == null || !_activeKeys.contains(serialKey))) {
      call.start();
    } else {
      if (_foreground.length + _background.length >= maxWaiting) {
        return Future.error(StateError('原生调用繁忙，请稍后重试'));
      }
      final queue = background ? _background : _foreground;
      queue.addLast(call);
      call.timer = Timer(waitTimeout, () {
        if (queue.remove(call)) {
          call.fail(TimeoutException('等待操作超时，请稍后重试', waitTimeout));
        }
      });
      _drain();
    }
    return result.future;
  }

  void _release(bool background, Object? serialKey) {
    _active--;
    if (background) _activeBackground--;
    if (serialKey != null) _activeKeys.remove(serialKey);
    _drain();
  }

  _Call? _takeEligible(Queue<_Call> queue) {
    // At most maxWaiting entries: blocked keys cannot stall unrelated work.
    for (final call in queue.toList(growable: false)) {
      if (call.cancelled?.call() == true) {
        queue.remove(call);
        call.timer?.cancel();
        call.fail(StateError('预加载已取消'));
      } else if (call.serialKey == null ||
          !_activeKeys.contains(call.serialKey)) {
        queue.remove(call);
        return call;
      }
    }
    return null;
  }

  void _drain() {
    while (_active < maxActive) {
      final call = _takeEligible(_foreground) ??
          (_activeBackground < maxBackground
              ? _takeEligible(_background)
              : null);
      if (call == null) return;
      call.timer?.cancel();
      call.start();
    }
  }
}

class _Call {
  _Call(this.background, this.serialKey, this.cancelled, this.start, this.fail);
  final Object? serialKey;
  final bool background;
  final bool Function()? cancelled;
  final void Function() start;
  final void Function(Object) fail;
  Timer? timer;
}
