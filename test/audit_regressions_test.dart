import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/network_api_host.dart';
import 'package:jasmine/configs/network_cdn_host.dart' as cdn;
import 'package:jasmine/configs/reader_zoom_scale.dart';
import 'package:jasmine/configs/reader_type.dart';
import 'package:jasmine/configs/reader_direction.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/screens/network_setting_screen.dart';
import 'package:jasmine/screens/download_album_screen.dart';
import 'package:jasmine/screens/downloads_screen.dart';
import 'package:jasmine/screens/comic_reader_screen.dart';
import 'package:jasmine/screens/components/content_error.dart';
import 'package:jasmine/screens/components/comic_comments_list.dart';
import 'package:jasmine/screens/components/images.dart';
import 'package:jasmine/basic/entities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, String> properties = {};
  String reply(String data) =>
      jsonEncode({'error_message': '', 'response_data': data});
  setUp(() {
    properties = {};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'];
      if (method == 'load_property') {
        return reply(properties[request['params']] ?? '');
      }
      if (method == 'jm_page_image' || method == 'jm_3x4_cover') {
        return reply(File('lib/assets/0.png').absolute.path);
      }
      if (method == 'image_size') return reply('{"w":1,"h":1}');
      if (method == 'all_downloads') return reply('[]');
      if (method == 'forum') return reply('{"total":10,"list":[]}');
      if ('$method'.contains('ping')) return reply('10');
      return reply('');
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('recovery page renders before config initialization',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NetworkSettingScreen()));
    expect(find.text('网络设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reinitialization does not duplicate API or CDN hosts; cancel is safe',
      (tester) async {
    await initApiHost();
    await initApiHost();
    await cdn.initCdnHost();
    await cdn.initCdnHost();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: Column(children: [
                    TextButton(
                        onPressed: () => chooseApiDialog(context),
                        child: const Text('API')),
                    TextButton(
                        onPressed: () => cdn.chooseCdnDialog(context),
                        child: const Text('CDN')),
                  ]),
                ))));
    await tester.tap(find.text('API'));
    await tester.pumpAndSettle();
    expect(find.byType(ApiOptionRow), findsNWidgets(4));
    await tester.tap(find.text('手动输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CDN'));
    await tester.pumpAndSettle();
    expect(find.byType(cdn.CdnOptionRow), findsNWidgets(9));
  });

  testWidgets('zoom one and non-finite values always produce valid sliders',
      (tester) async {
    for (final value in ['1', 'NaN', 'Infinity', '-2']) {
      properties = {
        'readerZoomMaxScale': value,
        'readerZoomDoubleTapScale': 'NaN'
      };
      await initReaderZoomScale();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        readerZoomMinScaleSetting(),
        readerZoomMaxScaleSetting(),
        readerZoomDoubleTapScaleSetting(),
      ]))));
      expect(readerZoomDoubleTapScale.isFinite, isTrue);
      expect(readerZoomDoubleTapScale, lessThanOrEqualTo(readerZoomMaxScale));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'failed downloads display retry and ignore completion after disposal',
      (tester) async {
    var failQuery = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (failQuery) throw PlatformException(code: 'query_failed');
      return reply('[]');
    });
    await tester.pumpWidget(const MaterialApp(home: DownloadsScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(ContentError), findsOneWidget);
    failQuery = false;
    await tester.widget<ContentError>(find.byType(ContentError)).onRefresh();
    await tester.pumpAndSettle();
    expect(find.byType(ContentError), findsNothing);
    final pending = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    await tester.pumpWidget(
        const MaterialApp(home: DownloadsScreen(key: ValueKey('pending'))));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(reply('[]'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reader retries the injected offline loader and handles empty chapter',
      (tester) async {
    await initReaderType();
    await initReaderDirection();
    await initIgnoreVewLog();
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: ComicReaderScreen(
      comic:
          ComicBasic(id: 1, author: '', description: '', name: '', image: ''),
      series: [],
      chapterId: 1,
      initRank: 999,
      loadChapter: (_) async {
        loads++;
        if (loads == 1) throw StateError('local file unavailable');
        return ChapterResponse(
            id: 1,
            series: [],
            tags: '',
            name: '',
            images: [],
            seriesId: 1,
            isFavorite: false,
            liked: false);
      },
    )));
    await tester.pumpAndSettle();
    await tester.widget<ContentError>(find.byType(ContentError)).onRefresh();
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.textContaining('章节暂无图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comments tolerate empty results with nonzero total',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ComicCommentsList(mode: null, aid: 1))));
    await tester.pumpAndSettle();
    expect(find.byType(ContentError), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download without chapters opens its album fallback',
      (tester) async {
    final queried = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      switch (request['method']) {
        case 'download_by_id':
          return reply(jsonEncode(DownloadCreate(
              album: DownloadCreateAlbum(
                id: 7,
                name: 'Offline',
                author: [],
                tags: [],
                works: [],
                description: '',
              ),
              chapters: []).toJson()));
        case 'find_view_log':
          return reply('null');
        case 'dl_image_by_chapter_id':
          queried.add(int.parse('${request['params']}'));
          return reply('[]');
        default:
          return reply('');
      }
    });
    final album = DownloadAlbum(
        id: 7,
        name: 'Offline',
        author: '[]',
        tags: '[]',
        works: '[]',
        description: '',
        dlSquareCoverStatus: 1,
        dl_3x4CoverStatus: 1,
        dlStatus: 1,
        imageCount: 0,
        dledImageCount: 0);
    await tester.pumpWidget(MaterialApp(home: DownloadAlbumScreen(album)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从头开始').first);
    await tester.pumpAndSettle();
    expect(find.byType(ComicReaderScreen), findsOneWidget);
    expect(queried, [7]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reader clamps obsolete history and tolerates nonnumeric chapter sort',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ComicReaderScreen(
      comic:
          ComicBasic(id: 1, author: '', description: '', name: '', image: ''),
      series: [],
      chapterId: 1,
      initRank: 999,
      loadChapter: (_) async => ChapterResponse(
          id: 1,
          series: [
            Series(id: 1, name: 'extra', sort: 'bonus'),
            Series(id: 2, name: 'two', sort: '2'),
          ],
          tags: '',
          name: '',
          images: ['page.png'],
          seriesId: 1,
          isFavorite: false,
          liked: false),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('page decode size has bounded memory and preserves aspect ratio', () {
    final tall = boundedPageImageSize(8000, 32000);
    expect(tall.width! * tall.height!, lessThanOrEqualTo(16 * 1024 * 1024));
    expect(tall.width, lessThanOrEqualTo(4096));
    expect(tall.height! / tall.width!, closeTo(4, 0.01));
    expect(boundedPageImageSize(20, 30).width, 20);
  });
}
