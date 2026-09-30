import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/web_dav_sync.dart';
import 'package:jasmine/configs/web_dav_password.dart';
import 'package:jasmine/configs/web_dav_url.dart';
import 'package:jasmine/configs/web_dav_username.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('WebDAV failures do not expose credentials in UI or logs',
      (tester) async {
    const password = 'test-webdav-secret';
    final previousDebugPrint = debugPrint;
    final logs = <String>[];
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previousDebugPrint);

    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'];
      if (method == 'load_property') {
        final values = {
          'WebDavUrl': 'https://example.invalid/webdav',
          'WebDavUserName': 'test-user',
          'WebDavPassword': password,
        };
        final value = values[request['params']] ?? '';
        return jsonEncode({'error_message': '', 'response_data': value});
      }
      expect(method, 'sync_webdav');
      return jsonEncode({
        'error_message': 'request failed with password=$password',
        'response_data': '',
      });
    });

    await initWebDavUrl();
    await initWebDavUserName();
    await initWebDavPassword();

    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const SizedBox.shrink();
      }),
    ));

    await webDavSync(context);
    debugPrint = previousDebugPrint;
    await tester.pump();
    expect(find.text('WebDav 同步失败'), findsOneWidget);
    expect(find.textContaining(password), findsNothing);
    expect(logs.join('\n'), isNot(contains(password)));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
