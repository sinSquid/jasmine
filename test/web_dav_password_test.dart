import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/web_dav_password.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('WebDAV password is hidden in settings and in the editor',
      (tester) async {
    const password = 'test-webdav-secret';
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'load_property');
      expect(request['params'], 'WebDavPassword');
      return jsonEncode({
        'error_message': '',
        'response_data': password,
      });
    });
    await initWebDavPassword();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: webDavPasswordSetting()),
    ));
    expect(find.text(password), findsNothing);
    expect(find.text('已设置'), findsOneWidget);

    await tester.tap(find.text('WebDAV密码'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });
}
