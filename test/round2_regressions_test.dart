import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/native_call_scheduler.dart';
import 'package:jasmine/basic/reader_system_ui.dart';
import 'package:jasmine/screens/components/image_preloader.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';
import 'package:jasmine/screens/components/continue_read_button.dart';
import 'package:jasmine/screens/components/content_error.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/screens/downloads_exports_screen.dart';
import 'package:jasmine/screens/downloads_screen.dart';
import 'package:jasmine/screens/downloads_exports_screen2.dart';
import 'package:jasmine/screens/downloads_exporting_screen.dart';
import 'package:jasmine/screens/downloads_exporting_screen2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
      'same-key mutations wait for native completion after caller timeout',
      (tester) async {
    final scheduler = NativeCallScheduler();
    final firstNative = Completer<int>();
    final first = scheduler.run(() => firstNative.future,
        serialKey: 'setting', timeout: const Duration(milliseconds: 10));
    final timeout = expectLater(first, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(milliseconds: 11));
    await timeout;
    var secondStarted = false;
    final second = scheduler.run(() async {
      secondStarted = true;
      return 2;
    }, serialKey: 'setting');
    expect(await scheduler.run(() async => 3, serialKey: 'different'), 3);
    expect(secondStarted, isFalse);
    firstNative.complete(1);
    expect(await second, 2);
  });

  testWidgets(
      'full background queue does not reject an available foreground slot',
      (tester) async {
    final scheduler = NativeCallScheduler(maxWaiting: 1);
    final blocker = Completer<void>();
    final first = NativeCallScheduler.speculative(
        () => scheduler.run(() => blocker.future),
        isCancelled: () => false);
    final pending = NativeCallScheduler.speculative(
        () => scheduler.run(() async {}),
        isCancelled: () => false);
    expect(await scheduler.run(() async => 7), 7);
    blocker.complete();
    await Future.wait([first, pending]);
  });

  testWidgets('property writes serialize per key while unrelated keys run',
      (tester) async {
    final first = Completer<String>();
    final started = <String>[];
    const response = '{"error_message":"","response_data":""}';
    messenger.setMockMethodCallHandler(channel, (call) {
      final outer = jsonDecode(call.arguments as String) as Map;
      final params = jsonDecode(outer['params'] as String) as Map;
      started.add('${params['k']}:${params['v']}');
      return started.length == 1 ? first.future : Future.value(response);
    });
    final one = methods.saveProperty('a', '1');
    final two = methods.saveProperty('a', '2');
    final other = methods.saveProperty('b', '1');
    await tester.pump();
    expect(started, ['a:1', 'b:1']);
    first.complete(response);
    await Future.wait([one, two, other]);
    expect(started, ['a:1', 'b:1', 'a:2']);
  });

  for (final plan in <List<int>>[
    [1, 2],
    [3, 4, 5, 6, 1, 2],
  ]) {
    testWidgets('preload plan $plan retains still-needed queued images',
        (tester) async {
      final scheduler = NativeCallScheduler(maxBackground: 1);
      final blocker = Completer<void>();
      final busy = NativeCallScheduler.speculative(
          () => scheduler.run(() => blocker.future),
          isCancelled: () => false);
      final loaded = <int>[];
      final preloader = ImagePreloader((index) => scheduler.run(() async {
            loaded.add(index);
          }));
      preloader.schedule([1, 2]);
      preloader.schedule(plan);
      blocker.complete();
      await busy;
      await tester.pump();
      expect(loaded, plan.length == 2 ? [1, 2] : [1, 2, 3, 4, 5, 6]);
      preloader.dispose();
    });
  }

  test('replacing a fullscreen reader preserves the new route state', () {
    final changes = <bool>[];
    final ui = ReaderSystemUi(changes.add);
    final old = Object(), next = Object();
    ui.attach(old, true);
    ui.attach(next, true);
    ui.detach(old);
    expect(changes.last, isTrue);
    ui.detach(next);
    expect(changes.last, isFalse);
  });

  testWidgets('search controller detaches on replacement and disposal',
      (tester) async {
    final old = FloatingSearchBarController(),
        next = FloatingSearchBarController();
    Widget screen(FloatingSearchBarController controller) => MaterialApp(
        home: FloatingSearchBarScreen(
            controller: controller, child: const SizedBox()));
    await tester.pumpWidget(screen(old));
    await tester.pumpWidget(screen(next));
    old.display(modifyInput: 'stale');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    next.display(modifyInput: 'new');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    next.hide();
    next.display();
    old.display();
    expect(tester.takeException(), isNull);
  });

  testWidgets('download retry rejects duplicate taps and recovers from failure',
      (tester) async {
    final pending = Completer<String>();
    var renews = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'renew_all_downloads') {
        renews++;
        return pending.future;
      }
      return '{"error_message":"","response_data":"[]"}';
    });
    await tester.pumpWidget(const MaterialApp(home: DownloadsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.autorenew));
    await tester.tap(find.byIcon(Icons.autorenew));
    expect(renews, 1);
    pending.completeError(PlatformException(code: 'renew_failed'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.autorenew))
            .onPressed,
        isNotNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  AlbumResponse album(List<Series> series) => AlbumResponse(
      id: 7,
      name: '',
      author: [],
      images: [],
      description: '',
      totalViews: 0,
      likes: 0,
      series: series,
      seriesId: 7,
      commentTotal: 0,
      tags: [],
      works: [],
      relatedList: [],
      liked: false,
      isFavorite: false);
  for (final empty in [true, false]) {
    testWidgets(
        'continue reading falls back when chapter missing (empty=$empty)',
        (tester) async {
      final series = empty
          ? <Series>[]
          : [
              Series(id: 2, name: '', sort: '2'),
              Series(id: 1, name: '', sort: '1')
            ];
      int? chosen;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ContinueReadButton(
        album: album(series),
        viewFuture: Future.value(ViewLog(
            id: 7,
            author: '',
            description: '',
            name: '',
            lastViewTime: 0,
            lastViewChapterId: 99,
            lastViewPage: 5)),
        onChoose: (chapter, page) {
          chosen = chapter;
          expect(page, 0);
        },
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从头开始'));
      expect(chosen, empty ? 7 : 1);
      if (!empty) expect(series.first.id, 2);
    });
  }

  for (final second in [false, true]) {
    testWidgets(
        'export return handles refresh failure and retry (variant=$second)',
        (tester) async {
      var failQuery = false;
      final item = DownloadAlbum(
          id: 7,
          name: 'Test',
          author: '[]',
          tags: '[]',
          works: '[]',
          description: '',
          dlSquareCoverStatus: 1,
          dl_3x4CoverStatus: 1,
          dlStatus: 1,
          imageCount: 1,
          dledImageCount: 1);
      messenger.setMockMethodCallHandler(channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        var data = '';
        if (request['method'] == 'all_downloads') {
          if (failQuery) throw PlatformException(code: 'query_failed');
          data = jsonEncode([item.toJson()]);
        } else if (request['method'] == 'jm_3x4_cover') {
          data = File('lib/assets/0.png').absolute.path;
        }
        return jsonEncode({'error_message': '', 'response_data': data});
      });
      await tester.pumpWidget(MaterialApp(
          home: second
              ? const DownloadsExportScreen2()
              : const DownloadsExportScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test'));
      await tester.tap(find.byTooltip('确认导出'));
      await tester.pumpAndSettle();
      final route = find.byType(
          second ? DownloadsExportingScreen2 : DownloadsExportingScreen);
      expect(route, findsOneWidget);
      failQuery = true;
      Navigator.of(tester.element(route)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ContentError), findsOneWidget);
      expect(tester.takeException(), isNull);
      failQuery = false;
      await tester.widget<ContentError>(find.byType(ContentError)).onRefresh();
      await tester.pumpAndSettle();
      expect(find.byType(ContentError), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
