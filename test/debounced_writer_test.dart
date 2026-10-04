import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/debounced_writer.dart';

void main() {
  testWidgets('coalesces bursts, serializes writes and flushes final value',
      (tester) async {
    final values = <int>[];
    final first = Completer<void>();
    var active = 0, peak = 0;
    final writer = DebouncedWriter<int>((value) async {
      active++;
      if (active > peak) peak = active;
      values.add(value);
      if (value == 99) await first.future;
      active--;
    }, onError: (e, st) => fail('$e'));
    for (var i = 0; i < 100; i++) {
      writer.add(i);
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(values, [99]);
    writer.add(100);
    writer.add(101);
    final closing = writer.close();
    first.complete();
    await closing;
    expect(values, [99, 101]);
    expect(peak, 1);
  });
}
