import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/reader_type.dart';
import 'package:jasmine/configs/reader_direction.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/screens/comic_reader_screen.dart';
import 'package:jasmine/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String reply(String value) =>
      jsonEncode({'error_message': '', 'response_data': value});
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final mode in [ReaderType.webtoon, ReaderType.webToonFreeZoom]) {
    testWidgets(
        '$mode updates only its image cell and preloads outside the viewport',
        (tester) async {
      final dimensions = <String, Completer<String>>{};
      final requested = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        switch (request['method']) {
          case 'load_property':
            return reply({
                  'readerType': '$mode',
                  'readerDirection': 'ReaderDirection.topToBottom',
                  'ignoreVewLog': 'true'
                }[request['params']] ??
                '');
          case 'jm_page_image':
            final name =
                jsonDecode(request['params'] as String)['image_name'] as String;
            requested.add(name);
            return reply('/reader-test-$name.png');
          case 'image_size':
            return dimensions
                .putIfAbsent(request['params'] as String, Completer<String>.new)
                .future;
          default:
            return reply('');
        }
      });
      await initReaderType();
      await initReaderDirection();
      await initIgnoreVewLog();
      await tester.pumpWidget(MaterialApp(
          home: ComicReaderScreen(
        comic:
            ComicBasic(id: 1, author: '', description: '', name: '', image: ''),
        series: [],
        chapterId: 1,
        initRank: 0,
        loadChapter: (_) async => ChapterResponse(
            id: 1,
            series: [],
            tags: '',
            name: '',
            images: List.generate(1000, (i) => '$i'),
            seriesId: 1,
            isFavorite: false,
            liked: false),
      )));
      await tester.pumpAndSettle();
      final cells =
          tester.widgetList<JMPageImage>(find.byType(JMPageImage)).toList();
      expect(cells.length, greaterThan(1));
      expect(cells.length, lessThan(20));
      final second = cells[1];
      cells.first.onTrueSize!(const Size(1000, 500));
      await tester.pump();
      final secondAfter = tester
          .widgetList<JMPageImage>(find.byType(JMPageImage))
          .firstWhere((image) => image.imageName == second.imageName);
      expect(identical(second, secondAfter), isTrue,
          reason: 'A size update must not rebuild neighboring image widgets');
      for (var step = 0; step < 8; step++) {
        for (final pending in dimensions.values.toList()) {
          if (!pending.isCompleted)
            pending.complete(reply('{"w":1000,"h":500}'));
        }
        await tester.pump();
      }
      // The viewport is 600 pixels high: index 0/1 fill it. Warmup also fetches
      // subsequent pages while keeping a 1000-page chapter lazy.
      expect(requested.toSet().contains('3'), isTrue);
      expect(requested.toSet().length, lessThan(20));
      await tester.pumpWidget(const SizedBox());
      for (final pending in dimensions.values) {
        if (!pending.isCompleted) pending.complete(reply('{"w":1000,"h":500}'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
