import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/images.dart';
import 'package:jasmine/screens/components/fading_reader_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('covers decode at display size and refresh when cells are reused',
      (tester) async {
    final directory = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('jasmine-cover-');
      final file = File('${directory.path}/cover.png');
      await file.writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC'));
      return directory;
    }))!;
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cover.png');

    final requested = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'jm_3x4_cover');
      requested.add(request['params'] as String);
      return jsonEncode({'error_message': '', 'response_data': file.path});
    });

    Widget cover(int id) => MaterialApp(
          home: Scaffold(
            body: JM3x4Cover(comicId: id, width: 100, height: 133),
          ),
        );

    await tester.pumpWidget(cover(1));
    await tester.pumpAndSettle();
    final image =
        tester.widget<FadingReaderImage>(find.byType(FadingReaderImage));
    expect(image.image, isA<BoundedFileImage>());
    expect((image.image as BoundedFileImage).targetWidth,
        (100 * tester.view.devicePixelRatio).ceil().clamp(1, 2048));

    await tester.pumpWidget(cover(2));
    await tester.pumpAndSettle();
    expect(requested, ['1', '2']);
    expect(tester.takeException(), isNull);
  });
}
