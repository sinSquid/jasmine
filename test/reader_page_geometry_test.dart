import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/basic/reader_image_dimensions.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/configs/reader_direction.dart';
import 'package:jasmine/configs/reader_type.dart';
import 'package:jasmine/screens/comic_reader_screen.dart';
import 'package:jasmine/screens/components/images.dart';
import 'package:jasmine/screens/components/reader_page_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dimensions reject invalid values and distinguish chapter image keys',
      () {
    final cache = ReaderImageDimensions();
    for (final size in [
      Size.zero,
      const Size(-1, 10),
      const Size(10, double.infinity),
      const Size(double.nan, 10),
    ]) {
      cache.put(1, 'a', size);
      expect(cache.get(1, 'a'), isNull);
    }
    cache.put(1, 'a', const Size(600, 800));
    cache.put(2, 'a', const Size(1200, 800));
    expect(cache.get(1, 'a'), const Size(600, 800));
    expect(cache.get(2, 'a'), const Size(1200, 800));
    expect(cache.get(1, 'b'), isNull);
  });

  test('dimensions have an LRU bound of 128 entries', () {
    final cache = ReaderImageDimensions();
    for (var page = 0; page < 128; page++) {
      cache.put(1, '$page', const Size(600, 800));
    }
    expect(cache.get(1, '0'), isNotNull);
    cache.put(1, '128', const Size(600, 800));
    expect(cache.get(1, '0'), isNotNull);
    expect(cache.get(1, '1'), isNull);
    expect(cache.get(1, '128'), isNotNull);
  });

  test('metadata reads do not extend the fixed monotonic two-minute TTL', () {
    var elapsed = Duration.zero;
    final cache = ReaderImageDimensions(elapsed: () => elapsed);
    cache.put(1, 'a', const Size(600, 800));
    elapsed = const Duration(seconds: 119);
    expect(cache.get(1, 'a'), isNotNull);
    elapsed = const Duration(minutes: 2);
    expect(cache.get(1, 'a'), isNull);
  });

  test('delete and clear invalidate late asynchronous metadata writes', () {
    final cache = ReaderImageDimensions();
    cache.put(1, 'a', const Size(600, 800));
    cache.put(1, 'b', const Size(600, 800));
    var generation = cache.generation;
    cache.invalidate(1, 'a');
    cache.put(1, 'a', const Size(800, 600), generation: generation);
    expect(cache.get(1, 'a'), isNull);
    expect(cache.get(1, 'b'), isNotNull);
    generation = cache.generation;
    cache.clear();
    cache.put(1, 'b', const Size(800, 600), generation: generation);
    expect(cache.get(1, 'b'), isNull);
  });

  test('portrait estimates and known vertical pages share the viewport width',
      () {
    const constraints = BoxConstraints(maxWidth: 300, maxHeight: 600);
    expect(
        readerPageRenderSize(
            constraints: constraints, scrollDirection: Axis.vertical),
        const Size(300, 400));
    expect(
        readerPageRenderSize(
            constraints: constraints,
            scrollDirection: Axis.vertical,
            imageSize: const Size(1200, 800)),
        const Size(300, 200));
  });

  test('horizontal unknown and known pages subtract identical chrome insets',
      () {
    Size render(Size? imageSize) => readerPageRenderSize(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        scrollDirection: Axis.horizontal,
        imageSize: imageSize,
        appBarHeight: 60,
        bottomBarHeight: 30,
        safeAreaBottom: 20);
    expect(render(null), const Size(367.5, 490));
    expect(render(const Size(1200, 800)), const Size(735, 490));
  });

  test('invalid metadata and insufficient layout space stay finite', () {
    expect(
        readerPageRenderSize(
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 600),
            scrollDirection: Axis.vertical,
            imageSize: const Size(0, 0)),
        const Size(300, 400));
    final cramped = readerPageRenderSize(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 20),
        scrollDirection: Axis.horizontal,
        appBarHeight: 60);
    expect(cramped.width.isFinite && cramped.width > 0, isTrue);
    expect(cramped.height, 1);
  });

  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String reply(String value) =>
      jsonEncode({'error_message': '', 'response_data': value});
  tearDown(() {
    readerImageDimensions.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native deletion and storage mutations clear dimension metadata',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => reply(''));
    readerImageDimensions.put(1, 'a', const Size(600, 800));
    readerImageDimensions.put(1, 'b', const Size(600, 800));
    await methods.deleteJmPageImageCache(1, 'a');
    expect(readerImageDimensions.get(1, 'a'), isNull);
    expect(readerImageDimensions.get(1, 'b'), isNotNull);
    for (final action in <Future<dynamic> Function()>[
      methods.cleanAllCache,
      methods.init,
      methods.init2,
      () => methods.setDownloadAndExportTo('/test-directory'),
    ]) {
      readerImageDimensions.put(1, 'a', const Size(600, 800));
      await action();
      expect(readerImageDimensions.get(1, 'a'), isNull);
    }
  });

  for (final mode in [ReaderType.webtoon, ReaderType.webToonFreeZoom]) {
    for (final direction in [
      ReaderDirection.topToBottom,
      ReaderDirection.leftToRight
    ]) {
      for (final cached in [false, true]) {
        testWidgets(
            '$mode $direction reserves ${cached ? "known" : "3:4"} size',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(800, 600);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final responses = <Completer<String>>[];
          final requests = <String>[];
          var finishing = false;
          messenger.setMockMethodCallHandler(channel, (call) async {
            final request = jsonDecode(call.arguments as String) as Map;
            switch (request['method']) {
              case 'load_property':
                return reply({
                      'readerType': '$mode',
                      'readerDirection': '$direction',
                      'ignoreVewLog': 'true'
                    }[request['params']] ??
                    '');
              case 'jm_page_image':
                if (finishing) return reply('/missing-geometry-fixture.png');
                requests.add(
                    jsonDecode(request['params'] as String)['image_name']
                        as String);
                final response = Completer<String>();
                responses.add(response);
                return response.future;
              default:
                return reply('');
            }
          });
          await methods.init();
          await initReaderType();
          await initReaderDirection();
          await initIgnoreVewLog();
          if (cached) {
            readerImageDimensions.put(702, '0', const Size(1200, 800));
          }
          await tester.pumpWidget(MaterialApp(
              home: ComicReaderScreen(
            comic: ComicBasic(
                id: 702, author: '', description: '', name: '', image: ''),
            series: const [],
            chapterId: 702,
            initRank: 0,
            loadChapter: (_) async => ChapterResponse(
                id: 702,
                series: const [],
                tags: '',
                name: '',
                images: List.generate(1000, (i) => '$i'),
                seriesId: 702,
                isFavorite: false,
                liked: false),
          )));
          await tester.pumpAndSettle();
          JMPageImage first() => tester
              .widgetList<JMPageImage>(find.byType(JMPageImage))
              .firstWhere((image) => image.imageName == '0');
          final before = first();
          expect(before.knownSize, cached ? const Size(1200, 800) : null);
          expect(before.width! / before.height!,
              closeTo(cached ? 1.5 : 0.75, 0.0001));
          if (!cached) {
            before.onTrueSize!(const Size(1200, 800));
            await tester.pump();
            final after = first();
            expect(after.knownSize, const Size(1200, 800));
            if (direction == ReaderDirection.topToBottom) {
              expect(after.width, before.width);
            } else {
              expect(after.height, before.height);
            }
          }
          expect(find.byType(JMPageImage).evaluate().length, lessThan(20));
          expect(requests.length, lessThan(20));
          finishing = true;
          await tester.pumpWidget(const SizedBox());
          for (final response in responses) {
            response.complete(reply('/missing-geometry-fixture.png'));
          }
          await tester.runAsync(() => pumpEventQueue());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
