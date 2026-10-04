import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/components/comic_list.dart';
import 'package:jasmine/screens/components/comic_loading.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/components/content_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> configure(PagerControllerMode mode,
      {PagerViewMode viewMode = PagerViewMode.info,
      PagerCoverRate coverRate = PagerCoverRate.rate3x4,
      int columns = 3}) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final values = {
        'pager_controller_mode': mode.toString(),
        'pager_column_number': '$columns',
        'pager_cover_rate': coverRate.toString(),
        'pager_view_mode': viewMode.toString(),
      };
      return jsonEncode({
        'error_message': '',
        'response_data': values[request['params']] ?? '',
      });
    });
    await initPagerControllerMode();
    await initPagerColumnCount();
    await initPagerCoverRate();
    await initPagerViewMode();
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Widget pager(Future<InnerComicPage> Function(int) onPage,
          {String source = 'source'}) =>
      MaterialApp(
        home: Scaffold(
            body: ComicPager(
          key: ValueKey(source),
          smoothLoading: true,
          onPage: onPage,
        )),
      );

  InnerComicPage response(int page) {
    final category = ComicSimpleCategory(id: '1', title: 'Test');
    return InnerComicPage(
      total: 200,
      list: List.generate(
        10,
        (index) => ComicSimple(
          id: page * 10 + index,
          author: '',
          description: '',
          name: 'Page $page item $index',
          image: '',
          category: category,
          categorySub: category,
          sealed: true,
        ),
      ),
    );
  }

  for (final mode in PagerControllerMode.values) {
    testWidgets('$mode shows static placeholders and keeps its bar during fade',
        (tester) async {
      await configure(mode);
      final pending = Completer<InnerComicPage>();
      var calls = 0;
      await tester.pumpWidget(pager((_) {
        calls++;
        return pending.future;
      }));
      await tester.pump();
      expect(find.byType(ComicListPlaceholder), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(calls, 1);
      final transition = tester.state(find.byType(ComicLoadingTransition));
      final bar = find.byWidgetPredicate((widget) =>
          widget is PreferredSize &&
          widget.preferredSize.height ==
              (mode == PagerControllerMode.stream ? 30 : 50));
      final before = tester.getRect(bar);
      pending.complete(response(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
          tester
              .widget<ComicLoadingTransition>(
                  find.byType(ComicLoadingTransition))
              .loading,
          isFalse);
      expect(
          identical(
              transition, tester.state(find.byType(ComicLoadingTransition))),
          isTrue);
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), before);
      expect(find.text('Page 1 item 0'), findsOneWidget);
      expect(calls, 1,
          reason: 'Changing the loading UI must not prefetch pages');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$mode shows errors, retries and renders an explicit empty state',
        (tester) async {
      await configure(mode);
      final first = Completer<InnerComicPage>();
      final retry = Completer<InnerComicPage>();
      var calls = 0;
      await tester
          .pumpWidget(pager((_) => ++calls == 1 ? first.future : retry.future));
      first.completeError(StateError('test failure'));
      await tester.pumpAndSettle();
      if (mode == PagerControllerMode.stream) {
        await tester.tap(find.text('出错, 点击重试'));
      } else {
        expect(find.byType(ContentError), findsOneWidget);
        await tester.tap(find.text('(点击刷新)'));
      }
      await tester.pump();
      expect(find.byType(ComicListPlaceholder), findsOneWidget);
      expect(calls, 2);
      retry.complete(InnerComicPage(total: 0, list: []));
      await tester.pumpAndSettle();
      expect(find.text('暂无漫画'), findsOneWidget);
      expect(find.textContaining(' / 1 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode source replacement ignores a late previous result',
        (tester) async {
      await configure(mode);
      final first = Completer<InnerComicPage>();
      final latest = Completer<InnerComicPage>();
      await tester.pumpWidget(pager((_) => first.future, source: 'old'));
      await tester.pumpWidget(pager((_) => latest.future, source: 'new'));
      latest.complete(response(2));
      await tester.pumpAndSettle();
      first.complete(response(1));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 item 0'), findsOneWidget);
      expect(find.text('Page 1 item 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stream append keeps loaded cells, list state and scroll offset',
      (tester) async {
    await configure(PagerControllerMode.stream);
    final next = Completer<InnerComicPage>();
    final calls = <int>[];
    await tester.pumpWidget(pager((page) {
      calls.add(page);
      return page == 1 ? Future.value(response(1)) : next.future;
    }));
    await tester.pumpAndSettle();
    final listState = tester.state(find.byType(ComicList));
    final list = tester.widget<ComicList>(find.byType(ComicList));
    final controller = list.controller!;
    controller.jumpTo(controller.position.maxScrollExtent - 20);
    final offset = controller.offset;
    await tester.pumpAndSettle();
    expect(calls, [1, 2]);
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 10);
    expect(find.text('Page 1 item 9'), findsOneWidget);
    expect(tester.widget<ComicList>(find.byType(ComicList)).appendList,
        hasLength(1));
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(
        tester
            .widget<ComicLoadingTransition>(find.byType(ComicLoadingTransition))
            .loading,
        isFalse);
    expect(identical(listState, tester.state(find.byType(ComicList))), isTrue);
    next.complete(response(2));
    await tester.pumpAndSettle();
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 20);
    expect(identical(listState, tester.state(find.byType(ComicList))), isTrue);
    expect(
        identical(controller,
            tester.widget<ComicList>(find.byType(ComicList)).controller),
        isTrue);
    expect(controller.offset, offset);
    expect(calls, [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pager keeps controls while waiting and suppresses repeat clicks',
      (tester) async {
    await configure(PagerControllerMode.pager);
    final next = Completer<InnerComicPage>();
    final calls = <int>[];
    await tester.pumpWidget(pager((page) {
      calls.add(page);
      return page == 1 ? Future.value(response(1)) : next.future;
    }));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.text('下一页'));
    await tester.tap(find.text('下一页'));
    await tester.tap(find.text('下一页'));
    await tester.pump();
    expect(calls, [1, 2]);
    expect(tester.getRect(find.text('下一页')), before);
    expect(find.text('Page 1 item 0'), findsNothing);
    expect(find.byType(ComicListPlaceholder), findsOneWidget);
    expect(
        tester
            .widget<MaterialButton>(find.ancestor(
                of: find.text('下一页'), matching: find.byType(MaterialButton)))
            .onPressed,
        isNull);
    next.complete(response(2));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 item 0'), findsOneWidget);
    expect(find.text('第 2 / 20 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream rapid jumps keep the latest page when responses race',
      (tester) async {
    await configure(PagerControllerMode.stream);
    final earlier = Completer<InnerComicPage>();
    final latest = Completer<InnerComicPage>();
    await tester.pumpWidget(pager((page) {
      if (page == 10) return earlier.future;
      if (page == 15) return latest.future;
      return Future.value(response(page));
    }));
    await tester.pumpAndSettle();
    Future<void> jump(int page) async {
      await tester.tap(find.textContaining(' / 20 页'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '$page');
      await tester.tap(find.text('确定'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await jump(10);
    await jump(15);
    latest.complete(response(15));
    await tester.pumpAndSettle();
    earlier.complete(response(10));
    await tester.pumpAndSettle();
    expect(find.text('已加载 15 / 20 页'), findsOneWidget);
    expect(find.text('Page 15 item 0'), findsOneWidget);
    expect(find.text('Page 10 item 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow ten-column tail loading and retry stay inside their cell',
      (tester) async {
    await configure(PagerControllerMode.stream,
        viewMode: PagerViewMode.cover,
        coverRate: PagerCoverRate.rateSquare,
        columns: 10);
    final next = Completer<InnerComicPage>();
    final retry = Completer<InnerComicPage>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 300,
      height: 240,
      child: ComicPager(
          smoothLoading: true,
          onPage: (_) {
            calls++;
            if (calls == 1) {
              return Future.value(InnerComicPage(
                  total: 200,
                  list: List.generate(100, (i) => response(1).list[i % 10])));
            }
            return calls == 2 ? next.future : retry.future;
          }),
    )))));
    await tester.pumpAndSettle();
    final list = tester.widget<ComicList>(find.byType(ComicList));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(calls, 2);
    // Appending the tail adds one grid row below the previous scroll extent.
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('加载中'), findsOneWidget);
    expect(tester.takeException(), isNull);
    next.completeError(StateError('test append failure'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(calls, 3);
    retry.complete(InnerComicPage(total: 200, list: []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
