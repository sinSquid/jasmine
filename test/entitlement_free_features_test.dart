import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/download_thread_count.dart';
import 'package:jasmine/configs/is_pro.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/components/comic_pager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('page 11 can be opened in both list paging modes without Pro',
      (tester) async {
    isPro = false;
    var mode = PagerControllerMode.stream;
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

    await initPagerColumnCount();
    await initPagerCoverRate();
    await initPagerViewMode();
    final category = ComicSimpleCategory(id: '1', title: 'Test');
    final requestedPages = <int>[];

    for (final pagingMode in PagerControllerMode.values) {
      mode = pagingMode;
      await initPagerControllerMode();
      requestedPages.clear();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ComicPager(
            key: ValueKey(pagingMode),
            onPage: (page) async {
              requestedPages.add(page);
              return InnerComicPage(
                total: 12,
                list: [
                  ComicSimple(
                    id: page,
                    author: '',
                    description: '',
                    name: 'Comic $page',
                    image: '',
                    category: category,
                    categorySub: category,
                    sealed: true,
                  ),
                ],
              );
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final pageLabel = pagingMode == PagerControllerMode.stream
          ? find.textContaining(' / 12 页')
          : find.text('第 1 / 12 页');
      await tester.tap(pageLabel);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '11');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(requestedPages, contains(11));
      expect(find.text('Comic 11'), findsOneWidget);
      expect(find.textContaining('发电'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('download concurrency can be set to five without Pro',
      (tester) async {
    isPro = false;
    final setValues = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'] as String;
      if (method == 'set_download_thread') {
        setValues.add(request['params'] as String);
      }
      return jsonEncode({
        'error_message': '',
        'response_data': method == 'load_download_thread' ? '1' : '',
      });
    });

    await initDownloadThreadCount();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: downloadThreadCountSetting()),
    ));
    await tester.tap(find.text('下载线程数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(setValues, ['5']);
    expect(downloadThreadCount, 5);
    expect(tester.takeException(), isNull);
  });
}
