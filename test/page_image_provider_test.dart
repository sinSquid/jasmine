import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('page provider decodes a native file path', (tester) async {
    final directory = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('jasmine-codec-');
      await File('${directory.path}/page.png').writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC'));
      return directory;
    }))!;
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/page.png';

    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'jm_page_image');
      return jsonEncode({'error_message': '', 'response_data': path});
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Image(image: PageImageProvider(7, 'page.png'))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
