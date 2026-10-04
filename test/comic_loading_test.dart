import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/components/comic_list.dart';
import 'package:jasmine/screens/components/comic_loading.dart';
import 'package:jasmine/screens/components/fading_reader_image.dart';
import 'package:jasmine/screens/components/images.dart';

class _Probe extends StatefulWidget {
  const _Probe({
    required super.key,
    required this.onMount,
    required this.onDispose,
    required this.onTap,
  });
  final VoidCallback onMount;
  final VoidCallback onDispose;
  final VoidCallback onTap;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: widget.onTap,
          child: const Text('真实内容'),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var nativeCalls = 0;
  var mode = PagerViewMode.cover;
  var ratio = PagerCoverRate.rate3x4;
  var columns = 4;

  setUp(() {
    nativeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls++;
      final request = jsonDecode(call.arguments as String) as Map;
      expect(request['method'], 'load_property');
      final values = {
        'pager_column_number': '$columns',
        'pager_cover_rate': '$ratio',
        'pager_view_mode': '$mode',
      };
      return jsonEncode({
        'error_message': '',
        'response_data': values[request['params']] ?? '',
      });
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> configure(
      PagerViewMode nextMode, PagerCoverRate nextRatio, int nextColumns) async {
    mode = nextMode;
    ratio = nextRatio;
    columns = nextColumns;
    await initPagerColumnCount();
    await initPagerCoverRate();
    await initPagerViewMode();
    nativeCalls = 0;
  }

  Widget host(Widget child,
          {double width = 180,
          double height = 280,
          bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(800, 600), disableAnimations: reduceMotion),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, height: height, child: child),
            ),
          ),
        ),
      );

  ComicSimple sealedComic() => ComicSimple(
        id: 7,
        author: '',
        description: '',
        name: 'existing comic',
        image: '',
        category: ComicSimpleCategory(id: '1', title: 'test'),
        categorySub: ComicSimpleCategory(id: '1', title: 'test'),
        sealed: true,
      );

  testWidgets(
      'all modes and ratios use bounded native-free narrow placeholders',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (final nextMode in PagerViewMode.values) {
      for (final nextRatio in PagerCoverRate.values) {
        for (final nextColumns in [1, 10]) {
          await configure(nextMode, nextRatio, nextColumns);
          await tester.pumpWidget(host(ComicListPlaceholder(
              key: ValueKey('$nextMode/$nextRatio/$nextColumns'))));
          await tester.pump();
          final list = tester.widget<ComicList>(find.byType(ComicList));
          expect(list.data, isEmpty);
          expect(list.placeholderCount, inInclusiveRange(1, 40));
          expect(find.byType(ReaderImagePlaceholder).evaluate().length,
              inInclusiveRange(1, 40));
          expect(find.byType(JM3x4Cover), findsNothing);
          expect(find.byType(JMSquareCover), findsNothing);
          expect(find.bySemanticsLabel('图片加载中'), findsNothing);
          if (nextMode == PagerViewMode.info) {
            final view = tester.widget<ListView>(find.byType(ListView));
            expect(view.childrenDelegate, isA<SliverChildBuilderDelegate>());
          } else {
            final view = tester.widget<GridView>(find.byType(GridView));
            final delegate =
                view.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
            expect(delegate.crossAxisCount, nextColumns);
            final coverRatio =
                nextRatio == PagerCoverRate.rate3x4 ? 3 / 4 : 1.0;
            if (nextMode == PagerViewMode.titleAndCover) {
              final width = 160 / nextColumns;
              expect(delegate.childAspectRatio,
                  closeTo(width / (width / coverRatio + 50), 0.0001));
            } else {
              expect(delegate.childAspectRatio, coverRatio);
            }
          }
          expect(nativeCalls, 0);
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull,
              reason: '$nextMode / $nextRatio / $nextColumns columns');
        }
      }
    }
    semantics.dispose();
  });

  testWidgets('real cells, placeholders and appendices share the grid geometry',
      (tester) async {
    for (final nextMode in PagerViewMode.values) {
      for (final nextRatio in PagerCoverRate.values) {
        await configure(nextMode, nextRatio, 2);
        await tester.pumpWidget(host(ComicList(
          key: ValueKey('$nextMode/$nextRatio'),
          data: [sealedComic()],
          placeholderCount: 1,
          appendList: const [SizedBox(key: ValueKey('append'), height: 30)],
        )));
        await tester.pump();
        if (nextMode == PagerViewMode.info) {
          final view = tester.widget<ListView>(find.byType(ListView));
          expect(
              (view.childrenDelegate as SliverChildBuilderDelegate).childCount,
              3);
        } else {
          final view = tester.widget<GridView>(find.byType(GridView));
          expect(
              (view.childrenDelegate as SliverChildBuilderDelegate).childCount,
              3);
          final cards = find.byType(Card);
          expect(tester.getSize(cards.at(0)), tester.getSize(cards.at(1)));
          expect(tester.getTopLeft(cards.at(1)).dx, lessThan(180));
        }
        expect(find.byKey(const ValueKey('append')), findsOneWidget);
        expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
        expect(nativeCalls, 0);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('placeholder item count clamps without shifting real appendices',
      (tester) async {
    await configure(PagerViewMode.cover, PagerCoverRate.rate3x4, 4);
    for (final requested in [-20, 100000]) {
      await tester.pumpWidget(host(SingleChildScrollView(
        child: ComicList(
          data: [sealedComic()],
          inScroll: true,
          placeholderCount: requested,
          appendList: const [SizedBox(key: ValueKey('append'), height: 20)],
        ),
      )));
      final expected = requested < 0 ? 0 : 40;
      expect(find.byType(ReaderImagePlaceholder).evaluate().length, expected);
      expect(find.byKey(const ValueKey('append')), findsOneWidget);
      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.children.length, 1 + expected + 1);
      expect(tester.getSize(find.byType(Card).first).width, 45);
      expect(nativeCalls, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('placeholder listens to all settings and releases subscriptions',
      (tester) async {
    await configure(PagerViewMode.cover, PagerCoverRate.rate3x4, -10);
    await tester.pumpWidget(host(const ComicListPlaceholder()));
    expect(pagerColumnNumber, 1);
    final firstCount =
        tester.widget<ComicList>(find.byType(ComicList)).placeholderCount;
    await configure(PagerViewMode.cover, PagerCoverRate.rate3x4, 500);
    pageColumnEvent.broadcast();
    await tester.pump();
    expect(pagerColumnNumber, 10);
    expect(tester.widget<ComicList>(find.byType(ComicList)).placeholderCount,
        greaterThan(firstCount));
    expect(
        tester.widget<ComicList>(find.byType(ComicList)).placeholderCount, 40);
    await configure(PagerViewMode.titleAndCover, PagerCoverRate.rateSquare, 2);
    currentPagerViewModeEvent.broadcast();
    pagerCoverRateEvent.broadcast();
    pageColumnEvent.broadcast();
    await tester.pump();
    final delegate = tester.widget<GridView>(find.byType(GridView)).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.childAspectRatio, closeTo(80 / 130, 0.0001));
    expect(nativeCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    pageColumnEvent.broadcast();
    currentPagerViewModeEvent.broadcast();
    pagerCoverRateEvent.broadcast();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'loading fades without remounting or interacting with the content',
      (tester) async {
    var mounts = 0;
    var disposals = 0;
    var taps = 0;
    Widget page(bool loading) => host(ComicLoadingTransition(
          loading: loading,
          child: _Probe(
            key: const ValueKey('content'),
            onMount: () => mounts++,
            onDispose: () => disposals++,
            onTap: () => taps++,
          ),
          placeholder: const ColoredBox(
              key: ValueKey('placeholder'), color: Colors.grey),
        ));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(page(true));
    final element = tester.element(find.byType(_Probe));
    expect(mounts, 1);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    expect(find.bySemanticsLabel('真实内容'), findsNothing);
    await tester.tap(find.text('真实内容'), warnIfMissed: false);
    expect(taps, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(page(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final transitions = tester.widgetList<FadeTransition>(find.descendant(
        of: find.byType(ComicLoadingTransition),
        matching: find.byType(FadeTransition)));
    expect(transitions.first.opacity.value, inExclusiveRange(0, 1));
    expect(transitions.last.opacity.value,
        closeTo(1 - transitions.first.opacity.value, 0.0001));
    expect(tester.element(find.byType(_Probe)), same(element));
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(find.bySemanticsLabel('正在加载'), findsNothing);
    expect(mounts, 1);
    expect(disposals, 0);
    await tester.tap(find.text('真实内容'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    semantics.dispose();
  });

  testWidgets('new loading cancels a fade without retaining the previous child',
      (tester) async {
    var mounts = 0;
    var disposals = 0;
    Widget page(bool loading, int generation) => host(ComicLoadingTransition(
          loading: loading,
          child: _Probe(
            key: ValueKey(generation),
            onMount: () => mounts++,
            onDispose: () => disposals++,
            onTap: () {},
          ),
          placeholder: const ColoredBox(
              key: ValueKey('placeholder'), color: Colors.grey),
        ));
    await tester.pumpWidget(page(true, 1));
    await tester.pumpWidget(page(false, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(page(true, 2));
    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(mounts, 2);
    expect(disposals, 1);
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(page(false, 2));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposals, 2);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion and initially ready content show immediately',
      (tester) async {
    Widget page(bool loading, {bool reduceMotion = true}) => host(
          ComicLoadingTransition(
            loading: loading,
            child: const SizedBox.expand(key: ValueKey('content')),
            placeholder: const ColoredBox(
                key: ValueKey('placeholder'), color: Colors.grey),
          ),
          reduceMotion: reduceMotion,
        );
    await tester.pumpWidget(page(true));
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    await tester.pumpWidget(page(false));
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(false, reduceMotion: false));
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
