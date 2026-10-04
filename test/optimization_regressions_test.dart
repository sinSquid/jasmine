import 'package:file_picker/file_picker.dart';
import 'package:jasmine/screens/downloads_exporting_screen.dart';
import 'package:jasmine/screens/downloads_exporting_screen2.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/reader_type.dart';
import 'package:jasmine/configs/reader_direction.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/screens/comic_reader_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/ui_action.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/configs/daily_sign.dart';
import 'package:jasmine/configs/app_font_size.dart';
import 'package:jasmine/configs/using_right_click_pop.dart';
import 'package:jasmine/configs/DesktopAuthenticationScreen.dart';
import 'package:jasmine/configs/display_jmcode.dart';
import 'package:jasmine/configs/search_title_words.dart';
import 'package:jasmine/screens/components/comic_info_card.dart';
import 'package:jasmine/screens/components/images.dart';
import 'package:jasmine/screens/network_setting_screen.dart';
import 'package:jasmine/screens/downloads_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String reply(String data) =>
      jsonEncode({'error_message': '', 'response_data': data});
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('UI action owns errors and suppresses duplicate pending actions',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const Scaffold();
    })));
    final pending = Completer<void>();
    var calls = 0;
    final first = runUiAction(context, () async {
      calls++;
      await pending.future;
    });
    await runUiAction(context, () {
      calls++;
    });
    expect(calls, 1);
    pending.completeError(StateError('private details'));
    await first;
    await tester.pump();
    expect(find.text('操作失败，请重试'), findsOneWidget);
    expect(find.textContaining('private details'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings persist completion after disposal without rebuilding',
      (tester) async {
    final pending = Completer<void>();
    var saved = false;
    Future<void>? operation;
    await tester.pumpWidget(MaterialApp(
        home: SettingsBuilder(
            builder: (context, update) => TextButton(
                  onPressed: () {
                    operation = runUiAction(context, () async {
                      await pending.future;
                      update(() => saved = true);
                    });
                  },
                  child: const Text('save'),
                ))));
    await tester.tap(find.text('save'));
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await operation;
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('font drag only persists at release and rolls back failed save',
      (tester) async {
    var saves = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String);
      if (request['method'] == 'save_property') {
        saves++;
        throw PlatformException(code: 'disk_full');
      }
      return reply('0');
    });
    await initFontSizeAdjust();
    const type = FontSizeAdjustType.fontSizeAdjustCommentContent;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: fontSizeAdjustSetting(type))));
    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1);
    slider.onChanged!(2);
    slider.onChanged!(3);
    await tester.pump();
    expect(saves, 0);
    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(3);
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(currentFontSizeAdjust(type), 0);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    expect(find.text('字体设置保存失败，请重试'), findsOneWidget);
  });

  testWidgets('offline recovery rejects failed authentication settings read',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async => reply(''));
    await initUsingRightClickPop();
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'storage_failed');
    });
    await tester.pumpWidget(const MaterialApp(home: NetworkSettingScreen()));
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsNothing);
    expect(find.text('无法验证身份，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'offline recovery requires existing desktop password and respects cancel',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async => reply(''));
    await initUsingRightClickPop();
    messenger.setMockMethodCallHandler(
        channel, (call) async => reply('test-password'));
    await tester.pumpWidget(const MaterialApp(home: NetworkSettingScreen()));
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyPassword), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    final context = tester.element(find.byType(VerifyPassword));
    Navigator.of(context).pop(false);
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsNothing);
    expect(find.byType(NetworkSettingScreen), findsOneWidget);
  });

  test('duplicate folder names remain selectable by stable ID', () {
    favData = [
      FavoriteFolderItem(fid: 1, uid: 7, name: 'same'),
      FavoriteFolderItem(fid: 2, uid: 7, name: 'same')
    ];
    expect(favoriteFolderChoices().values.toSet(), {0, 1, 2});
    favData = [];
  });

  testWidgets(
      'late favorite and sign replies cannot restore previous account state',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const Scaffold();
    })));
    final oldFavorites = Completer<String>();
    final oldDaily = Completer<String>();
    var loginCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String);
      switch (request['method']) {
        case 'login':
          if (++loginCalls > 1) throw PlatformException(code: 'login_failed');
          return reply(jsonEncode(SelfInfo(
                  uid: 1,
                  username: 'test',
                  email: '',
                  emailverified: '',
                  photo: '',
                  fname: '',
                  gender: '',
                  message: '',
                  coin: 0,
                  albumFavorites: 0,
                  s: '',
                  levelName: '',
                  level: 0,
                  nextLevelExp: 0,
                  exp: '',
                  expPercent: 0,
                  badges: [],
                  albumFavoritesMax: 0)
              .toJson()));
        case 'favorite':
          return oldFavorites.future;
        case 'daily':
          return oldDaily.future;
        default:
          throw PlatformException(code: 'unavailable');
      }
    });
    final first = login('test', 'one', context);
    await tester.pump();
    await first;
    expect(loginStatus, LoginStatus.loginSuccess);
    final second = login('test2', 'two', context);
    await tester.pump();
    await second;
    oldFavorites.complete(reply(jsonEncode({
      'total': 0,
      'count': 0,
      'list': [],
      'folder_list': [
        {'FID': 1, 'UID': 1, 'name': 'old'}
      ]
    })));
    oldDaily.complete(reply('signed'));
    await tester.pumpAndSettle();
    expect(loginStatus, LoginStatus.loginField);
    expect(favData, isEmpty);
    expect(dailySignStatus, DailySignStatus.unchecked);
    expect(loginMessage, isNotEmpty);
  });

  testWidgets(
      'linked title preserves leading and adjacent brackets across rebuild',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async => reply('true'));
    await initSearchTitleWords();
    await initDisplayJmcode();
    final comic = ComicBasic(
        id: 5, name: '[one][two]title', author: '', description: '', image: '');
    Widget card() =>
        MaterialApp(home: Scaffold(body: ComicInfoCard(comic, link: true)));
    await tester.pumpWidget(card());
    final titles = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText());
    expect(titles.any((text) => text.contains('[one][two]title')), isTrue);
    await tester.pumpWidget(card());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('extreme tall-image budget preserves a finite bounded decode size', () {
    for (final size in [
      const Size(4000, 100000),
      const Size(12000, 12000),
      const Size(300, 500)
    ]) {
      final result =
          boundedPageImageSize(size.width.toInt(), size.height.toInt());
      expect(
          result.width! * result.height!, lessThanOrEqualTo(16 * 1024 * 1024));
      expect(result.width!, lessThanOrEqualTo(4096));
      expect(result.width!, lessThanOrEqualTo(size.width));
    }
  });
  testWidgets('history clear waits for an in-flight progress write',
      (tester) async {
    final blocked = Completer<String>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final name = jsonDecode(call.arguments as String)['method'] as String;
      calls.add(name);
      if (name == 'update_view_log') return blocked.future;
      return reply('');
    });
    final write = methods.updateViewLog(1, 2, 3);
    await tester.pump();
    final clear = methods.clearViewLog();
    await tester.pump();
    expect(calls, ['update_view_log']);
    blocked.complete(reply(''));
    await tester.pump();
    await Future.wait([write, clear]);
    expect(calls, ['update_view_log', 'clear_view_log']);
  });

  testWidgets(
      'two-page keyboard navigation advances a spread and stops at the final page',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String);
      if (request['method'] == 'load_property') {
        return reply({
              'readerType': 'ReaderType.twoPageGallery',
              'readerDirection': 'ReaderDirection.leftToRight',
              'ignoreVewLog': 'true'
            }[request['params']] ??
            '');
      }
      return reply('');
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
      initRank: 1,
      loadChapter: (_) async => ChapterResponse(
          id: 1,
          series: [],
          tags: '',
          name: '',
          images: ['a', 'b', 'c', 'd', 'e'],
          seriesId: 1,
          isFavorite: false,
          liked: false),
    )));
    await tester.pumpAndSettle();
    double page() =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    expect(page(), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(page(), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(page(), 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(page(), 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(page(), 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final variant in [1, 2]) {
    testWidgets(
        'export $variant locks during folder selection and cancellation stops export',
        (tester) async {
      final picker = _PendingDirectoryPicker();
      FilePicker.platform = picker;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(jsonDecode(call.arguments as String)['method'] as String);
        return reply('');
      });
      await initUsingRightClickPop();
      await tester.pumpWidget(MaterialApp(
          home: variant == 1
              ? const DownloadsExportingScreen(idList: [1])
              : const DownloadsExportingScreen2(idList: [1])));
      final label = variant == 1 ? '分别导出JMI' : '导出成文件夹';
      final button = tester.widget<MaterialButton>(find
          .ancestor(of: find.text(label), matching: find.byType(MaterialButton))
          .first);
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(picker.calls, 1);
      picker.result.complete(null);
      await tester.pumpAndSettle();
      expect(calls.where((name) => name.startsWith('export_')), isEmpty);
      expect(find.text('导出确认'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page retry deletes the failed cache before loading again',
      (tester) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final name = jsonDecode(call.arguments as String)['method'] as String;
      calls.add(name);
      if (name == 'jm_page_image') throw PlatformException(code: 'bad_cache');
      return reply('');
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: JMPageImage(1, 'a', width: 100, height: 100))));
    await tester.pumpAndSettle();
    await tester.longPress(find.byIcon(Icons.error_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(calls,
        ['jm_page_image', 'delete_jm_page_image_cache', 'jm_page_image']);
    expect(tester.takeException(), isNull);
  });
}

class _PendingDirectoryPicker extends FilePicker {
  final result = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> getDirectoryPath(
      {String? dialogTitle,
      bool lockParentWindow = false,
      String? initialDirectory}) {
    calls++;
    return result.future;
  }
}
