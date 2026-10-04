import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/Authentication.dart';
import 'package:jasmine/configs/DesktopAuthenticationScreen.dart';
import 'package:jasmine/configs/always_enter_browser.dart';
import 'package:jasmine/configs/categories_sort.dart';
import 'package:jasmine/configs/display_jmcode.dart';
import 'package:jasmine/configs/search_title_words.dart';
import 'package:jasmine/configs/using_right_click_pop.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/calculator_screen.dart';
import 'package:jasmine/screens/init_screen.dart';
import 'package:jasmine/screens/comic_download_screen.dart';
import 'package:jasmine/screens/week_screen.dart';
import 'package:jasmine/screens/components/comic_list.dart';
import 'package:jasmine/screens/components/types.dart';
import 'package:jasmine/screens/components/text_preview_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String reply(String value) =>
      jsonEncode({'error_message': '', 'response_data': value});
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'calculator handles decimals, zero, sign, percentage and chaining',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CalculatorScreen()));
    Future<void> press(List<String> labels) async {
      for (final label in labels) {
        await tester.tap(find.widgetWithText(MaterialButton, label));
        await tester.pump();
      }
    }

    final state = tester.state<ContentBodyState>(find.byType(ContentBody));
    await press(['1', '.', '5', '÷', '.', '5', '=']);
    expect(state.sums, '3');
    await press(['AC', '1', '.', '.', '5', '%']);
    expect(state.sums, '0.015');
    await press(['+/-']);
    expect(state.sums, '-0.015');
    await press(['AC', '8', '÷', '0', '=']);
    expect(state.sums, '错误');
    await press(['2', '+', '3', '+', '4', '=']);
    expect(state.sums, '9');
    await press(['AC', '2', '+', '×', '3', '=']);
    expect(state.sums, '6');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'activation routes through authentication before revealing content',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      return reply(
          request['params'] == 'desktopAuthPassword' ? 'test-password' : '');
    });
    await initAlwaysEnterBrowser();
    await initAuthentication();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => activateApp(context),
                    child: const Text('activate'))))));
    await tester.tap(find.text('activate'));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyPassword), findsOneWidget);
    expect(find.byType(AuthScreen, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'text preview really copies, and a clipboard failure is not success',
      (tester) async {
    final copied = <String>[];
    var failCopy = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (failCopy) throw PlatformException(code: 'clipboard_failure');
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    await tester
        .pumpWidget(const MaterialApp(home: TextPreviewScreen(text: '完整评论')));
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    expect(copied, ['完整评论']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    failCopy = true;
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pumpAndSettle();
    expect(find.text('复制失败，请重试'), findsOneWidget);
    expect(find.text('已复制到剪切板'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlapping input dialogs do not share text controllers',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      pageContext = context;
      return const Scaffold();
    })));
    final first =
        displayTextInputDialog(pageContext, src: 'first', isPasswd: true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'edited-first');
    final second = displayTextInputDialog(pageContext, src: 'second');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认').last);
    await tester.pumpAndSettle();
    expect(await second, 'second');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'edited-first');
    await tester.tap(find.text('确认').last);
    await tester.pumpAndSettle();
    expect(await first, 'edited-first');
    expect(tester.takeException(), isNull);
  });

  test('models retain optional fields and accept integer percentages', () {
    expect(SearchPage(searchQuery: 'q', total: 0).toJson()['redirect_aid'],
        isNull);
    expect(
        Categories.fromJson({
          'id': 1,
          'name': 'n',
          'slug': 's',
          'total_albums': 0,
          'type': 't'
        }).type,
        't');
    expect(GameCategory.fromJson({'name': 'n', 'slug': 's'}).toJson(),
        {'name': 'n', 'slug': 's'});
    expect(
        Expinfo.fromJson({
          'level_name': '',
          'level': 1,
          'nextLevelExp': 2,
          'exp': '1',
          'expPercent': 0,
          'uid': 1,
          'badges': []
        }).expPercent,
        0.0);
  });

  testWidgets(
      'category preferences survive a failed save and an unchanged panel',
      (tester) async {
    var stored = '[2,1]';
    var failSave = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'save_property') {
        if (failSave) throw PlatformException(code: 'save_failed');
        stored =
            (jsonDecode(request['params'] as String) as Map)['v'] as String;
      }
      return reply(request['method'] == 'load_property' ? stored : '');
    });
    await initCategoriesSort();
    await expectLater(
        saveCategoriesSort([1]), throwsA(isA<PlatformException>()));
    expect(getCategoriesSort(), [2, 1]);
    expect(() => getCategoriesSort().clear(), throwsUnsupportedError);
    final source = [
      Categories(id: 1, name: '', slug: 'one', totalAlbums: 0),
      Categories(id: 2, name: '二', slug: 'two', totalAlbums: 0)
    ];
    await tester.pumpWidget(MaterialApp(home: CategoriesSortPanel(source)));
    failSave = false;
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(jsonDecode(stored), [2, 1]);
    expect(source.map((e) => e.id), [1, 2]);
    stored = 'broken';
    await initCategoriesSort();
    expect(getCategoriesSort(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty weekly data renders an empty state', (tester) async {
    for (final data in [
      {'categories': [], 'type': []},
      {
        'categories': [],
        'type': [
          {'id': '1', 'title': '一'}
        ]
      },
      {
        'categories': [
          {'id': '1', 'time': 't', 'title': '一'}
        ],
        'type': []
      },
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: WeekContent(
                  key: UniqueKey(), data: WeekData.fromJson(data)))));
      expect(find.text('暂无每周必看内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'download query retries and submission is single flight after failure',
      (tester) async {
    var failQuery = true, submits = 0;
    final pending = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'download_by_id') {
        if (failQuery) throw PlatformException(code: 'query_failed');
        return reply('null');
      }
      if (request['method'] == 'create_download') {
        submits++;
        return pending.future;
      }
      return reply('');
    });
    await initDisplayJmcode();
    await initSearchTitleWords();
    await initUsingRightClickPop();
    final album = AlbumResponse(
        id: 7,
        name: 'download',
        author: [],
        images: [],
        description: '',
        totalViews: 0,
        likes: 0,
        series: [Series(id: 7, name: '', sort: '1')],
        seriesId: 7,
        commentTotal: 0,
        tags: [],
        works: [],
        relatedList: [],
        liked: false,
        isFavorite: false);
    await tester.pumpWidget(MaterialApp(home: ComicDownloadScreen(album)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
    failQuery = false;
    await tester.tap(find.byIcon(Icons.sync_problem));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.text('确定下载'));
    await tester.tap(find.text('确定下载'));
    await tester.pump();
    expect(submits, 1);
    pending.completeError(PlatformException(code: 'create_failed'));
    await tester.pumpAndSettle();
    expect(find.text('创建下载失败，请重试'), findsOneWidget);
    expect(
        tester
            .widget<MaterialButton>(find.widgetWithText(MaterialButton, '确定下载'))
            .onPressed,
        isNotNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'open long-press menu keeps the selected comic across list replacement',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final values = {
        'pager_view_mode': 'PagerViewMode.info',
        'pager_column_number': '3',
        'pager_cover_rate': 'PagerCoverRate.rate3x4'
      };
      return reply(values[request['params']] ?? '');
    });
    await initPagerViewMode();
    await initPagerColumnCount();
    await initPagerCoverRate();
    await initDisplayJmcode();
    await initSearchTitleWords();
    int? chosen;
    ComicSimple comic(int id) => ComicSimple(
        id: id,
        author: '',
        description: '',
        name: 'comic$id',
        image: '',
        category: ComicSimpleCategory(id: '', title: ''),
        categorySub: ComicSimpleCategory(id: '', title: ''));
    var data = [comic(1)];
    late StateSetter rebuild;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return Scaffold(
          body: ComicList(data: data, longPressMenuItems: [
        ComicLongPressMenuItem('删除', (item) => chosen = item.id)
      ]));
    })));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('comic1'));
    await tester.pumpAndSettle();
    rebuild(() => data = [comic(2)]);
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(chosen, 1);
    expect(tester.takeException(), isNull);
  });
}
