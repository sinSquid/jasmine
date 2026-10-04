import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/components/comic_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> configure(PagerControllerMode mode) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'load_property');
      final values = {
        'pager_controller_mode': mode.toString(),
        'pager_column_number': '3',
        'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
        'pager_view_mode': PagerViewMode.info.toString(),
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

  Widget pager(Future<InnerComicPage> Function(int) onPage) => MaterialApp(
        home: Scaffold(body: ComicPager(onPage: onPage)),
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
    testWidgets('$mode ignores completion after disposal', (tester) async {
      await configure(mode);
      final pending = Completer<InnerComicPage>();
      await tester.pumpWidget(pager((_) => pending.future));
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(response(1));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode handles an empty page with a nonzero total',
        (tester) async {
      await configure(mode);
      var calls = 0;
      await tester.pumpWidget(pager((_) async {
        calls++;
        return InnerComicPage(total: 200, list: []);
      }));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining(' / 1 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stream jump ignores a late response from an earlier jump',
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
      // The existing page may still be loading, so do not wait for all spinners.
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
  testWidgets(
      'stream windows release previous records without limiting later pages',
      (tester) async {
    await configure(PagerControllerMode.stream);
    final calls = <int>[];
    await tester.pumpWidget(pager((page) async {
      calls.add(page);
      final base = response(page).list.first;
      return InnerComicPage(
          total: 3000,
          list: List.generate(
              1000,
              (i) => ComicSimple(
                    id: page * 1000 + i,
                    author: '',
                    description: '',
                    name: 'Window $page item $i',
                    image: '',
                    category: base.category!,
                    categorySub: base.categorySub!,
                    sealed: true,
                  )));
    }));
    await tester.pumpAndSettle();
    var list = tester.widget<ComicList>(find.byType(ComicList));
    expect(list.data.length, 1000);
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(calls, [1]);
    await tester.tap(find.text('继续浏览下一段'));
    await tester.pumpAndSettle();
    list = tester.widget<ComicList>(find.byType(ComicList));
    expect(list.data.length, 1000);
    expect(list.data.first.name, 'Window 2 item 0');
    await tester.tap(find.text('返回上一段'));
    await tester.pumpAndSettle();
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.first.name,
        'Window 1 item 0');
    expect(calls, [1, 2, 1]);
    expect(tester.takeException(), isNull);
  });
}
