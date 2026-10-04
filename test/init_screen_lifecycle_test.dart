import 'package:jasmine/screens/first_login_screen.dart';
import 'package:jasmine/screens/unlock_browser_screen.dart';
import 'package:jasmine/screens/calculator_screen.dart';
import 'package:jasmine/configs/DesktopAuthenticationScreen.dart';
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
  for (final password in ['', 'test-password']) {
    testWidgets(
        'startup ignores old browser flags and preserves authentication: ${password.isNotEmpty}',
        (tester) async {
      rootBundle.clear();
      final readKeys = <String>[];
      String reply(String value) =>
          jsonEncode({'error_message': '', 'response_data': value});
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'invoke') return null;
        final request = jsonDecode(call.arguments as String) as Map;
        if (request['method'] == 'load_property') {
          final key = request['params'] as String;
          readKeys.add(key);
          return reply({
                'passed': 'false',
                'alwaysEnterBrowser': 'true',
                'desktopAuthPassword': password,
                'checkVersionPeriod': '-1'
              }[key] ??
              '');
        }
        if (request['method'] == 'pre_login') {
          return reply(
              '{"pre_set":false,"pre_login":false,"self_info":null,"message":""}');
        }
        if (request['method'] == 'config_links') return reply('{}');
        return reply('');
      });
      await tester.pumpWidget(const MaterialApp(home: InitScreen()));
      for (var frame = 0; frame < 50; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        final destination = password.isEmpty
            ? find.byType(FirstLoginScreen)
            : find.byType(VerifyPassword);
        if (destination.evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(UnlockBrowserScreen), findsNothing);
      expect(find.byType(CalculatorScreen), findsNothing);
      expect(readKeys, isNot(contains('passed')));
      expect(readKeys, isNot(contains('alwaysEnterBrowser')));
      if (password.isEmpty) {
        expect(find.byType(FirstLoginScreen), findsOneWidget);
      } else {
        expect(find.byType(VerifyPassword), findsOneWidget,
            reason: 'Read config keys: $readKeys');
        expect(find.byType(FirstLoginScreen), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
