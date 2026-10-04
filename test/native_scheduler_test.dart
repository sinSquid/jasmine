import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/native_call_scheduler.dart';

void main() {
  testWidgets('timeout reports failure but retains the native permit',
      (tester) async {
    final scheduler = NativeCallScheduler(
        maxActive: 1, waitTimeout: const Duration(milliseconds: 20));
    final native = Completer<int>();
    final first = scheduler.run(() => native.future,
        timeout: const Duration(milliseconds: 10));
    final check = expectLater(first, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(milliseconds: 11));
    await check;
    var started = false;
    final queued = scheduler.run(() async {
      started = true;
      return 2;
    });
    final expired = expectLater(queued, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(milliseconds: 21));
    await expired;
    expect(started, isFalse);
    native.complete(1);
    await tester.pump();
    expect(await scheduler.run(() async => 3), 3);
  });

  testWidgets(
      'foreground goes before queued preloads and stale preload is dropped',
      (tester) async {
    final scheduler = NativeCallScheduler(maxActive: 2, maxBackground: 1);
    final running = Completer<int>();
    final first = NativeCallScheduler.speculative(
        () => scheduler.run(() => running.future),
        isCancelled: () => false);
    var cancelled = false;
    var staleStarted = false;
    final stale = NativeCallScheduler.speculative(
        () => scheduler.run(() async {
              staleStarted = true;
              return 2;
            }),
        isCancelled: () => cancelled);
    final staleCheck = expectLater(stale, throwsStateError);
    expect(await scheduler.run(() async => 3), 3);
    cancelled = true;
    running.complete(1);
    await first;
    await tester.pump();
    await staleCheck;
    expect(staleStarted, isFalse);
  });
}
