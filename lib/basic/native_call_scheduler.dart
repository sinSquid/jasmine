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
  final Map<Object, _SharedCall> _shared = {};

  // Cache invalidation starts a new generation; existing callers still finish.
  void invalidateShared(Object key) => _shared.remove(key);

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
      {Duration timeout = const Duration(seconds: 60),
      Object? serialKey,
      Object? sharedKey}) {
    final background = Zone.current[_backgroundKey] == true;
    final cancelled = Zone.current[_cancelledKey] as bool Function()?;
    if (cancelled?.call() == true) {
      return Future.error(StateError('预加载已取消'));
    }
    final existing = sharedKey == null ? null : _shared[sharedKey];
    if (existing != null) {
      // Multiple owners must not inherit the first owner's cancellation.
      existing.call.cancelled = null;
      if (!background && _background.remove(existing.call)) {
        existing.call.background = false;
        _foreground.addLast(existing.call);
      }
      _drain();
      return existing.future.then((value) => value as T);
    }
    _drain();
    final result = Completer<T>();
    late _Call call;
    void forget() {
      if (sharedKey != null && identical(_shared[sharedKey]?.call, call)) {
        _shared.remove(sharedKey);
      }
    }

    call = _Call(background, serialKey, cancelled, () {
      _active++;
      if (serialKey != null) _activeKeys.add(serialKey);
      final runningBackground = call.background;
      if (runningBackground) _activeBackground++;
      final native = Future<T>.sync(action);
      void release() {
        forget();
        _release(runningBackground, serialKey);
      }

      native.then<void>((_) => release(),
          onError: (Object _, StackTrace __) => release());
      native.timeout(timeout, onTimeout: () {
        throw TimeoutException('操作超时，结果尚未确认；请勿重复提交，持续无响应时重启应用', timeout);
      }).then(result.complete, onError: result.completeError);
    }, (Object error) {
      forget();
      if (!result.isCompleted) result.completeError(error);
    });
    if (sharedKey != null) {
      _shared[sharedKey] = _SharedCall(call, result.future);
    }
    if (_active < maxActive &&
        (!background || _activeBackground < maxBackground) &&
        (serialKey == null || !_activeKeys.contains(serialKey))) {
      call.start();
    } else {
      if (_foreground.length + _background.length >= maxWaiting) {
        forget();
        return Future.error(StateError('原生调用繁忙，请稍后重试'));
      }
      final queue = background ? _background : _foreground;
      queue.addLast(call);
      call.timer = Timer(waitTimeout, () {
        if (_foreground.remove(call) || _background.remove(call)) {
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
  bool background;
  bool Function()? cancelled;
  final void Function() start;
  final void Function(Object) fail;
  Timer? timer;
}

class _SharedCall {
  _SharedCall(this.call, this.future);
  final _Call call;
  final Future<dynamic> future;
}
