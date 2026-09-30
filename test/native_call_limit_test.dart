import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  const success = '{"error_message":"","response_data":""}';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native calls have four active slots and a bounded waiting queue',
      () async {
    final responses = <Completer<String>>[];
    var active = 0;
    var highestActive = 0;
    var started = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      final response = Completer<String>();
      responses.add(response);
      started++;
      active++;
      if (active > highestActive) highestActive = active;
      return response.future.whenComplete(() => active--);
    });

    final calls = List<Future<dynamic>>.generate(36, (_) => methods.init());
    await pumpEventQueue();
    expect(started, 4);
    await expectLater(methods.init(), throwsStateError);

    for (var i = 0; i < calls.length; i++) {
      await pumpEventQueue();
      expect(responses, isNotEmpty);
      responses.removeAt(0).complete(success);
    }
    await Future.wait(calls);
    expect(started, 36);
    expect(highestActive, 4);
  });

  test('a failed native call releases its slot', () async {
    final responses = <Completer<String>>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      final response = Completer<String>();
      responses.add(response);
      return response.future;
    });

    final active = List<Future<dynamic>>.generate(4, (_) => methods.init());
    await pumpEventQueue();
    final waiting = methods.init();
    expect(responses.length, 4);

    final failed = expectLater(active.first, throwsA(isA<PlatformException>()));
    responses.first.completeError(PlatformException(code: 'native_failure'));
    await failed;
    await pumpEventQueue();
    expect(responses.length, 5);

    for (final response in responses.skip(1)) {
      response.complete(success);
    }
    await Future.wait([...active.skip(1), waiting]);
  });
}
