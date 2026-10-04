import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/comic_seal.dart';
import 'package:jasmine/configs/categories_sort.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/browser_screen.dart';
import 'package:jasmine/screens/components/comic_list.dart';
import 'package:jasmine/screens/components/comic_loading.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/components/content_error.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Future<String> Function() categoriesLoad;
  late Future<String> Function(Map<String, dynamic>) comicsLoad;
  late List<String> calls;
  late List<Map<String, dynamic>> comicRequests;

  String reply(Object data) => jsonEncode({
        'error_message': '',
        'response_data': data is String ? data : jsonEncode(data),
      });

  String categoriesReply([List<String> slugs = const ['a', 'b']]) => reply({
        'categories': [
          for (var index = 0; index < slugs.length; index++)
            {
              'id': index + 1,
              'name': '分类 ${slugs[index].toUpperCase()}',
              'slug': slugs[index],
              'total_albums': 1,
            },
        ],
        'blocks': <Object>[],
      });

  String comicsReply(String slug) => reply({
        'search_query': '',
        'total': 1,
        'content': [
          {
            'id': slug.codeUnitAt(0),
            'name': 'Comic ${slug.toUpperCase()} result',
            'author': '',
            'description': '',
            'image': '',
          },
        ],
      });

  Future<void> configure(PagerControllerMode mode) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'] as String;
      calls.add(method);
      switch (method) {
        case 'load_property':
          return reply({
                'pager_controller_mode': mode.toString(),
                'pager_column_number': '3',
                'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
                'pager_view_mode': PagerViewMode.titleAndCover.toString(),
                'categoriesSort': '[]',
              }[request['params']] ??
              '');
        case 'categories':
          return categoriesLoad();
        case 'comics':
          final params =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          comicRequests.add(Map.of(params));
          return comicsLoad(params);
        default:
          throw StateError('Unexpected browser request: $method');
      }
    });
    await initPagerControllerMode();
    await initPagerColumnCount();
    await initPagerCoverRate();
    await initPagerViewMode();
    await initCategoriesSort();
    calls.clear();
  }

  Widget browser() => MaterialApp(
      home: BrowserScreen(searchBarController: FloatingSearchBarController()));

  setUp(() {
    calls = [];
    comicRequests = [];
    categoriesLoad = () async => categoriesReply();
    comicsLoad = (params) async => comicsReply(params['categories_slug']);
    // These tests exercise category/list loading, independently of file decode.
    updateComicSealRules(categories: [], titleWords: ['Comic ']);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    updateComicSealRules(categories: [], titleWords: []);
  });

  testWidgets('pending categories show a static list skeleton without covers',
      (tester) async {
    final pending = Completer<String>();
    categoriesLoad = () => pending.future;
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();

    expect(find.text('浏览'), findsOneWidget);
    expect(find.byType(ComicListPlaceholder), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ComicPager), findsNothing);
    expect(calls, ['categories']);
    final skeleton = tester.widget<ComicList>(find.byType(ComicList));
    expect(skeleton.data, isEmpty);
    expect(skeleton.placeholderCount, inInclusiveRange(1, 40));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(const SizedBox());
    pending.complete(categoriesReply());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final mode in PagerControllerMode.values) {
    testWidgets('$mode category switches ignore earlier comic responses',
        (tester) async {
      final earlier = Completer<String>();
      final latest = Completer<String>();
      comicsLoad = (params) =>
          params['categories_slug'] == 'a' ? earlier.future : latest.future;
      await configure(mode);
      await tester.pumpWidget(browser());
      await tester.pumpAndSettle();
      expect(comicRequests.map((request) => request['categories_slug']), ['a']);
      final previousPager = tester.widget<ComicPager>(find.byType(ComicPager));

      await tester.tap(find.text('分类 B'));
      await tester.pumpAndSettle();
      expect(comicRequests.map((request) => request['categories_slug']),
          ['a', 'b']);
      expect(find.byType(ComicListPlaceholder), findsOneWidget);
      latest.complete(comicsReply('b'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Comic B result'), findsOneWidget);

      earlier.complete(comicsReply('a'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Comic A result'), findsNothing);
      expect(find.textContaining('Comic B result'), findsOneWidget);

      // A captured callback remains bound to its category after parent state
      // changes; animations must not accidentally retarget an outgoing pager.
      final oldCategoryPage = await previousPager.onPage(2);
      expect(oldCategoryPage.list.single.name, 'Comic A result');
      expect(comicRequests.last, {
        'categories_slug': 'a',
        'sort_by': '',
        'page': 2,
      });
      expect(calls.where((method) => method.contains('cover')), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty category directory shows an explicit empty state',
      (tester) async {
    categoriesLoad = () async => categoriesReply([]);
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    expect(find.text('暂无分类'), findsOneWidget);
    expect(find.byType(ComicListPlaceholder), findsNothing);
    expect(find.byType(ComicPager), findsNothing);
    expect(comicRequests, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('failed category loading can retry through the skeleton',
      (tester) async {
    var attempts = 0;
    final retry = Completer<String>();
    categoriesLoad = () {
      attempts++;
      return attempts == 1
          ? Future.value(jsonEncode(
              {'error_message': 'test directory failure', 'response_data': ''}))
          : retry.future;
    };
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    expect(find.byType(ContentError), findsOneWidget);
    await tester.tap(find.text('(点击刷新)'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(ComicListPlaceholder), findsOneWidget);
    expect(find.byType(ContentError), findsNothing);
    retry.complete(categoriesReply(['b']));
    await tester.pumpAndSettle();
    expect(find.text('分类 B'), findsOneWidget);
    expect(find.textContaining('Comic B result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category sorting reload ignores a late older directory',
      (tester) async {
    final earlier = Completer<String>();
    final latest = Completer<String>();
    var attempts = 0;
    categoriesLoad = () => ++attempts == 1 ? earlier.future : latest.future;
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    categoriesSortEvent.broadcast();
    await tester.pumpAndSettle();
    latest.complete(categoriesReply(['b']));
    await tester.pumpAndSettle();
    earlier.complete(categoriesReply(['a']));
    await tester.pumpAndSettle();
    expect(find.text('分类 B'), findsOneWidget);
    expect(find.text('分类 A'), findsNothing);
    expect(find.textContaining('Comic B result'), findsOneWidget);
    expect(comicRequests.map((request) => request['categories_slug']), ['b']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an immediately failed directory retry keeps an error owner',
      (tester) async {
    categoriesLoad = () async => jsonEncode(
        {'error_message': 'immediate directory failure', 'response_data': ''});
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    await tester.tap(find.text('(点击刷新)'));
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'categories').length, 2);
    expect(find.byType(ContentError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an immediately failed sorting reload keeps an error owner',
      (tester) async {
    categoriesLoad = () async => categoriesReply([]);
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    categoriesLoad = () async => jsonEncode(
        {'error_message': 'immediate reload failure', 'response_data': ''});
    categoriesSortEvent.broadcast();
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'categories').length, 2);
    expect(find.byType(ContentError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category failure arriving after disposal has an error owner',
      (tester) async {
    final pending = Completer<String>();
    categoriesLoad = () => pending.future;
    await configure(PagerControllerMode.stream);
    await tester.pumpWidget(browser());
    await tester.pumpWidget(const SizedBox());
    pending.complete(jsonEncode(
        {'error_message': 'late directory failure', 'response_data': ''}));
    await tester.pumpAndSettle();
    categoriesSortEvent.broadcast();
    await tester.pump();
    expect(calls, ['categories']);
    expect(tester.takeException(), isNull);
  });
}
