import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/screens/view_log_screen.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/components/comic_comments_list.dart';
import 'package:jasmine/screens/components/comic_floating_search_bar.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String reply(Object data) =>
      jsonEncode({'error_message': '', 'response_data': jsonEncode(data)});
  setUp(() async {
    messenger.setMockMethodCallHandler(channel,
        (_) async => jsonEncode({'error_message': '', 'response_data': ''}));
    await initPagerControllerMode();
    await initPagerColumnCount();
    await initPagerCoverRate();
    await initPagerViewMode();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    searchHistories = [];
  });

  for (final dispose in [false, true]) {
    testWidgets(
        'history delete handles failure, duplicate taps, dispose=$dispose',
        (tester) async {
      final pending = Completer<String>();
      var deletes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final method = jsonDecode(call.arguments as String)['method'];
        if (method == 'delete_view_log_by_comic_id') {
          deletes++;
          return pending.future;
        }
        return reply({'search_query': '', 'total': 0, 'content': []});
      });
      await tester.pumpWidget(const MaterialApp(home: ViewLogScreen()));
      await tester.pumpAndSettle();
      final pager = tester.widget<ComicPager>(find.byType(ComicPager));
      final action = pager.longPressMenuItems!.single.onChoose;
      final comic =
          ComicBasic(id: 1, author: '', description: '', name: '', image: '');
      final first = action(comic) as Future<void>;
      await action(comic);
      expect(deletes, 1);
      if (dispose) await tester.pumpWidget(const SizedBox());
      pending.completeError(PlatformException(code: 'failed'));
      await first;
      await tester.pump();
      if (dispose) {
        await action(comic);
        expect(deletes, 1);
      }
      expect(tester.takeException(), isNull);
      if (!dispose) {
        expect(
            tester.widget<ComicPager>(find.byType(ComicPager)).key, pager.key);
        expect(
            tester
                .widget<IconButton>(
                    find.widgetWithIcon(IconButton, Icons.auto_delete))
                .onPressed,
            isNotNull);
        await tester.pump(const Duration(seconds: 5));
      }
    });
  }

  testWidgets(
      'successful history delete reloads the pager without replacing the route',
      (tester) async {
    var pages = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (jsonDecode(call.arguments as String)['method'] == 'page_view_log') {
        pages++;
      }
      return reply({'search_query': '', 'total': 0, 'content': []});
    });
    await tester.pumpWidget(const MaterialApp(home: ViewLogScreen()));
    await tester.pumpAndSettle();
    final old = tester.widget<ComicPager>(find.byType(ComicPager));
    await old.longPressMenuItems!.single.onChoose(
        ComicBasic(id: 1, author: '', description: '', name: '', image: ''));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ComicPager>(find.byType(ComicPager)).key, isNot(old.key));
    expect(pages, 2);
    expect(find.byType(ViewLogScreen), findsOneWidget);
  });

  Future<void> showPanel(
      WidgetTester tester, FloatingSearchBarController controller) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ComicFloatingSearchBarScreen(
      controller: controller,
      child: const SizedBox(),
    ))));
    controller.display();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'search opens before history completes and survives history failure',
      (tester) async {
    final pending = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final controller = FloatingSearchBarController();
    await showPanel(tester, controller);
    final context = tester.element(find.byType(ComicFloatingSearchBarScreen));
    final future = showComicSearch(context, controller, keywords: 'query');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'query');
    pending.completeError(PlatformException(code: 'history_failed'));
    await future;
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'search history deletion owns completion after disposal, failure=$fails',
        (tester) async {
      searchHistories = [SearchHistory(searchQuery: 'old', lastSearchTime: 1)];
      final pending = Completer<String>();
      var clears = 0;
      messenger.setMockMethodCallHandler(channel, (_) {
        clears++;
        return pending.future;
      });
      final controller = FloatingSearchBarController();
      await showPanel(tester, controller);
      await tester.longPress(find.text('old'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('是'));
      await tester.pumpAndSettle();
      expect(clears, 1);
      await tester.pumpWidget(const SizedBox());
      if (fails) {
        pending.completeError(PlatformException(code: 'failed'));
      } else {
        pending.complete(reply(''));
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      await showPanel(tester, FloatingSearchBarController());
      expect(find.text('old'), fails ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('stale history read cannot restore a deleted entry',
      (tester) async {
    searchHistories = [SearchHistory(searchQuery: 'old', lastSearchTime: 1)];
    final pending = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (jsonDecode(call.arguments as String)['method'] ==
          'last_search_histories') {
        return pending.future;
      }
      return reply('');
    });
    final controller = FloatingSearchBarController();
    await showPanel(tester, controller);
    final future = showComicSearch(
        tester.element(find.byType(ComicFloatingSearchBarScreen)), controller,
        keywords: '');
    await tester.longPress(find.text('old'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('是'));
    await tester.pumpAndSettle();
    pending.complete(reply([
      {'search_query': 'old', 'last_search_time': 1}
    ]));
    await future;
    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
  });

  testWidgets('deleting history broadcasts to all mounted search panels',
      (tester) async {
    searchHistories = [SearchHistory(searchQuery: 'shared', lastSearchTime: 1)];
    messenger.setMockMethodCallHandler(channel, (_) async => reply(''));
    final controllers = [
      FloatingSearchBarController(),
      FloatingSearchBarController()
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      for (final controller in controllers)
        Expanded(
            child: ComicFloatingSearchBarScreen(
                controller: controller, child: const SizedBox())),
    ]))));
    for (final controller in controllers) {
      controller.display();
    }
    await tester.pumpAndSettle();
    expect(find.text('shared'), findsNWidgets(2));
    await tester.longPress(find.text('shared').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('是'));
    await tester.pumpAndSettle();
    expect(find.text('shared'), findsNothing);
  });

  testWidgets(
      'clear history respects cancellation and completion after disposal',
      (tester) async {
    final pending = Completer<String>();
    var clears = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (jsonDecode(call.arguments as String)['method'] == 'clear_view_log') {
        clears++;
        return pending.future;
      }
      return reply({'search_query': '', 'total': 0, 'content': []});
    });
    await tester.pumpWidget(const MaterialApp(home: ViewLogScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('否'));
    await tester.pumpAndSettle();
    expect(clears, 0);
    await tester.tap(find.byIcon(Icons.auto_delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('是'));
    await tester.pumpAndSettle();
    expect(clears, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(reply(''));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reused comment component reloads changed identity and ignores old response',
      (tester) async {
    final first = Completer<String>();
    final aids = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      final request = jsonDecode(call.arguments as String);
      final aid = jsonDecode(request['params'] as String)['aid'] as int;
      aids.add(aid);
      return aid == 1
          ? first.future
          : Future.value(reply({'total': 0, 'list': []}));
    });
    Widget screen(int aid) => MaterialApp(
        home: Scaffold(body: ComicCommentsList(mode: null, aid: aid)));
    await tester.pumpWidget(screen(1));
    await tester.pumpWidget(screen(2));
    await tester.pumpAndSettle();
    expect(aids, [1, 2]);
    first.complete(reply({'total': 999, 'list': []}));
    await tester.pumpAndSettle();
    expect(find.text('下一页'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
