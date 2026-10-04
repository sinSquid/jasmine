import 'dart:async';
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

  testWidgets('reused page cells ignore stale image dimensions',
      (tester) async {
    final directory = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('jasmine-page-');
      await File('${directory.path}/page.png').writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC'));
      return directory;
    }))!;
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/page.png';
    final oldResponse = Completer<String>();
    final dimensions = <Size>[];
    final requests = <String>[];

    messenger.setMockMethodCallHandler(channel, (call) {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'jm_page_image') {
        final params = jsonDecode(request['params'] as String) as Map;
        final name = params['image_name'] as String;
        requests.add(name);
        if (name == 'old') return oldResponse.future;
        return Future.value(
            jsonEncode({'error_message': '', 'response_data': path}));
      }
      expect(request['method'], 'image_size');
      return Future.value(jsonEncode({
        'error_message': '',
        'response_data': jsonEncode({'w': 1, 'h': 1}),
      }));
    });

    Widget page(String name) => MaterialApp(
          home: Scaffold(
            body: JMPageImage(
              1,
              name,
              width: 100,
              height: 100,
              onTrueSize: dimensions.add,
              decodeToDisplayWidth: true,
            ),
          ),
        );

    await tester.pumpWidget(page('old'));
    await tester.pumpWidget(page('new'));
    await tester.pumpAndSettle();
    oldResponse
        .complete(jsonEncode({'error_message': '', 'response_data': path}));
    await tester.pumpAndSettle();

    expect(requests, ['old', 'new']);
    expect(dimensions, [const Size(1, 1)]);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<BoundedFileImage>());
    expect((image.image as BoundedFileImage).targetWidth,
        (100 * tester.view.devicePixelRatio).ceil().clamp(1, 4096));
    expect(tester.takeException(), isNull);
  });
  testWidgets('prefetched dimensions avoid another native size request',
      (tester) async {
    final requests = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      requests.add(request['method'] as String);
      return jsonEncode(
          {'error_message': '', 'response_data': '/missing-test-image.png'});
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: JMPageImage(
      1,
      'known',
      width: 100,
      height: 200,
      knownSize: const Size(100, 200),
      onTrueSize: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(requests, ['jm_page_image']);
    expect(tester.takeException(), isNull);
  });
}
