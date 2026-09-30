import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/app_font_size.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/versions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('invalid saved settings use safe startup defaults',
      (tester) async {
    final values = <String, String>{
      'checkVersionPeriod': 'invalid',
      'pager_column_number': 'invalid',
      'FontSizeAdjustType.fontSizeAdjustCommentContent': 'invalid',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'load_property');
      return jsonEncode({
        'error_message': '',
        'response_data': values[request['params']] ?? '',
      });
    });

    await initVersion();
    await initPagerColumnCount();
    await initFontSizeAdjust();
    expect(pagerColumnNumber, 4);
    expect(
        currentFontSizeAdjust(FontSizeAdjustType.fontSizeAdjustCommentContent),
        0);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          autoUpdateCheckSetting(),
          fontSizeAdjustSetting(
              FontSizeAdjustType.fontSizeAdjustCommentContent),
        ]),
      ),
    ));
    expect(find.text('自动检查更新已开启'), findsOneWidget);
    expect(tester.takeException(), isNull);

    values['pager_column_number'] = '99';
    values['FontSizeAdjustType.fontSizeAdjustCommentContent'] = '-99';
    await initPagerColumnCount();
    await initFontSizeAdjust();
    expect(pagerColumnNumber, 10);
    expect(
        currentFontSizeAdjust(FontSizeAdjustType.fontSizeAdjustCommentContent),
        -5);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
