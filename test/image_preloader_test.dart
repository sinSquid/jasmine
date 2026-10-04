import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/image_preloader.dart';

void main() {
  test('preloads at most two images and replaces stale pending work', () async {
    final started = <int>[];
    final pending = <int, Completer<void>>{};
    var active = 0;
    var peakActive = 0;
    final preloader = ImagePreloader((index) {
      started.add(index);
      active++;
      if (active > peakActive) peakActive = active;
      final response = Completer<void>();
      pending[index] = response;
      return response.future.whenComplete(() => active--);
    });

    preloader.schedule([0, 1, 2, 3, 4, 5, 6]);
    expect(started, [0, 1]);
    preloader.schedule([9, 10, 11, 12, 13]);
    pending[0]!.complete();
    await pumpEventQueue();
    expect(started, [0, 1, 9]);

    for (final index in [1, 9, 10, 11, 12]) {
      pending[index]!.complete();
      await pumpEventQueue();
    }
    expect(started, [0, 1, 9, 10, 11, 12]);
    expect(peakActive, 2);
    expect(active, 0);
    preloader.dispose();
  });

  test('failed work frees a slot and dispose drops the queue', () async {
    final started = <int>[];
    final pending = <int, Completer<void>>{};
    final preloader = ImagePreloader((index) {
      started.add(index);
      final response = Completer<void>();
      pending[index] = response;
      return response.future;
    });

    preloader.schedule([0, 1, 2, 3]);
    pending[0]!.completeError(StateError('image unavailable'));
    await pumpEventQueue();
    expect(started, [0, 1, 2]);

    preloader.dispose();
    pending[1]!.complete();
    pending[2]!.complete();
    await pumpEventQueue();
    preloader.schedule([4]);
    expect(started, [0, 1, 2]);
  });
  test('repeated viewport updates do not reload completed nearby files',
      () async {
    final started = <int>[];
    final preloader = ImagePreloader((index) async {
      started.add(index);
    });
    for (var frame = 0; frame < 100; frame++) {
      preloader.schedule([1, 2, 3]);
      await pumpEventQueue();
    }
    expect(started, [1, 2, 3]);
    preloader.schedule([2, 3, 4]);
    await pumpEventQueue();
    expect(started, [1, 2, 3, 4]);
    preloader.dispose();
  });

  test('failed preloads remain retryable in the same viewport', () async {
    var attempts = 0;
    final preloader = ImagePreloader((index) async {
      if (++attempts == 1) throw StateError('temporary failure');
    });
    preloader.schedule([1]);
    await pumpEventQueue();
    preloader.schedule([1]);
    await pumpEventQueue();
    preloader.schedule([1]);
    await pumpEventQueue();
    expect(attempts, 2);
    preloader.dispose();
  });
}
