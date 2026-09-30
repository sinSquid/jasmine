import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/components/comic_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('large comic lists build visible cells on demand',
      (tester) async {
    var viewMode = 'PagerViewMode.cover';
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'load_property');
      final values = {
        'pager_column_number': '3',
        'pager_cover_rate': 'PagerCoverRate.rate3x4',
        'pager_view_mode': viewMode,
      };
      return jsonEncode({
        'error_message': '',
        'response_data': values[request['params']] ?? '',
      });
    });

    await initPagerColumnCount();
    await initPagerCoverRate();
    final category = ComicSimpleCategory(id: '1', title: 'Test');
    final comics = List<ComicBasic>.generate(
      500,
      (index) => ComicSimple(
        id: index,
        author: '',
        description: '',
        name: 'Comic $index',
        image: '',
        category: category,
        categorySub: category,
        sealed: true,
      ),
    );

    for (final mode in PagerViewMode.values) {
      viewMode = mode.toString();
      await initPagerViewMode();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ComicList(key: ValueKey(mode), data: comics)),
      ));
      await tester.pump();
      if (mode == PagerViewMode.info) {
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
      } else {
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(grid.childrenDelegate, isA<SliverChildBuilderDelegate>());
      }
      expect(find.text('Comic 499'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
