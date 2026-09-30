import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/init_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('disposed init screen stops its remaining native calls',
      (tester) async {
    final firstResponse = Completer<String>();
    final calledMethods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      final method = request['method'] as String;
      calledMethods.add(method);
      if (method == 'init_dart') return firstResponse.future;
      return Future.value('{"error_message":"","response_data":""}');
    });

    await tester.pumpWidget(const MaterialApp(home: InitScreen()));
    expect(calledMethods, ['init_dart']);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    firstResponse.complete('{"error_message":"","response_data":""}');
    await tester.pump();

    expect(calledMethods, ['init_dart']);
    expect(tester.takeException(), isNull);
  });
}
