import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/basic/native_call_scheduler.dart';
import 'package:jasmine/configs/reader_type.dart';
import 'package:jasmine/configs/reader_direction.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/screens/comic_reader_screen.dart';
import 'package:jasmine/screens/components/images.dart';
import 'package:jasmine/screens/components/fading_reader_image.dart';
import 'package:jasmine/screens/file_photo_view_screen.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String reply(String value) =>
      jsonEncode({'error_message': '', 'response_data': value});
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('viewport decoding preserves aspect ratio, native size and pixel budget',
      () {
    final full =
        fittedPageImageSize(4000, 6000, targetWidth: 1080, targetHeight: 2400);
    expect(full.width, 1080);
    expect(full.height, 1620);
    final half =
        fittedPageImageSize(4000, 6000, targetWidth: 540, targetHeight: 2400);
    expect(half.width, 540);
    expect(half.height, 810);
    final small =
        fittedPageImageSize(100, 200, targetWidth: 1080, targetHeight: 2400);
    expect(small.width, 100);
    expect(small.height, 200);
    final tall = fittedPageImageSize(4000, 100000);
    expect(tall.width! * tall.height!, lessThanOrEqualTo(16 * 1024 * 1024));
    expect(viewportImagePixels(400, 2), viewportImagePixels(401, 2));
    expect(PageImageProvider(1, 'a', targetWidth: 400),
        isNot(PageImageProvider(1, 'a', targetWidth: 800)));
  });

  test('retry evicts all resolutions of its page without affecting other pages',
      () async {
    final cache = PaintingBinding.instance.imageCache;
    final low = PageImageProvider(100, 'a', targetWidth: 400);
    final high = PageImageProvider(100, 'a');
    final other = PageImageProvider(100, 'b');
    for (final provider in [low, high, other]) {
      await provider.obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(provider,
          () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future));
    }
    await PageImageProvider.evictPage(100, 'a');
    expect(cache.containsKey(low), isFalse);
    expect(cache.containsKey(high), isFalse);
    expect(cache.containsKey(other), isTrue);
    cache.evict(other);
  });

  test(
      'visible image joins and promotes queued preload despite cancelled owner',
      () async {
    final scheduler = NativeCallScheduler(maxActive: 2, maxBackground: 1);
    final blocked = Completer<int>();
    final first = NativeCallScheduler.speculative(
        () => scheduler.run(() => blocked.future),
        isCancelled: () => false);
    var stale = false;
    var calls = 0;
    final image = Completer<int>();
    final preload = NativeCallScheduler.speculative(
        () => scheduler.run(() {
              calls++;
              return image.future;
            }, sharedKey: 'image'),
        isCancelled: () => stale);
    expect(calls, 0);
    stale = true;
    final visible = scheduler.run<int>(() async {
      throw StateError('duplicate native call');
    }, sharedKey: 'image');
    expect(calls, 1);
    image.complete(7);
    expect(await visible, 7);
    expect(await preload, 7);
    blocked.complete(1);
    await first;
    // Promotion must not leak the background permit.
    expect(
        await NativeCallScheduler.speculative(
            () => scheduler.run(() async => 8),
            isCancelled: () => false),
        8);
  });

  testWidgets('shared timeout retains operation until native completion',
      (tester) async {
    final scheduler = NativeCallScheduler();
    final native = Completer<int>();
    final first = scheduler.run(() => native.future,
        sharedKey: 'image', timeout: const Duration(milliseconds: 10));
    final check = expectLater(first, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(milliseconds: 11));
    await check;
    var duplicates = 0;
    await expectLater(
        scheduler.run(() async {
          duplicates++;
          return 2;
        }, sharedKey: 'image'),
        throwsA(isA<TimeoutException>()));
    expect(duplicates, 0);
    native.complete(1);
    await tester.pump();
    expect(await scheduler.run(() async => 3, sharedKey: 'image'), 3);
  });

  testWidgets('promoted queue timeout removes the call and allows retry',
      (tester) async {
    final scheduler = NativeCallScheduler(
        maxActive: 1, waitTimeout: const Duration(milliseconds: 10));
    final native = Completer<int>();
    final running = scheduler.run(() => native.future);
    var calls = 0;
    final preload = NativeCallScheduler.speculative(
        () => scheduler.run(() async {
              calls++;
              return 2;
            }, sharedKey: 'queued'),
        isCancelled: () => false);
    final visible = scheduler.run(() async => 3, sharedKey: 'queued');
    final checks = [
      expectLater(preload, throwsA(isA<TimeoutException>())),
      expectLater(visible, throwsA(isA<TimeoutException>()))
    ];
    await tester.pump(const Duration(milliseconds: 11));
    await Future.wait(checks);
    native.complete(1);
    await tester.pump();
    await running;
    expect(calls, 0);
    expect(await scheduler.run(() async => 4, sharedKey: 'queued'), 4);
  });

  test('same-image requests share failures and allow a new retry', () async {
    var calls = 0;
    final response = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls++;
      return response.future;
    });
    final first = methods.jmPageImage(91, 'same');
    final second = methods.jmPageImage(91, 'same');
    final checks = [
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError)
    ];
    await pumpEventQueue();
    expect(calls, 1);
    response
        .complete(jsonEncode({'error_message': 'failed', 'response_data': ''}));
    await Future.wait(checks);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return reply('/new');
    });
    expect(await methods.jmPageImage(91, 'same'), '/new');
    expect(calls, 2);
  });

  test('delete invalidates shared image and runs before new generation',
      () async {
    final calls = <String>[];
    final responses = <Completer<String>>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(jsonDecode(call.arguments as String)['method']);
      final response = Completer<String>();
      responses.add(response);
      return response.future;
    });
    final old = methods.jmPageImage(92, 'same');
    await pumpEventQueue();
    final deletion = methods.deleteJmPageImageCache(92, 'same');
    final fresh = NativeCallScheduler.speculative(
        () => methods.jmPageImage(92, 'same'),
        isCancelled: () => false);
    final visible = methods.jmPageImage(92, 'same');
    await pumpEventQueue();
    expect(calls, ['jm_page_image']);
    responses[0].complete(reply('/old'));
    expect(await old, '/old');
    await pumpEventQueue();
    expect(calls, ['jm_page_image', 'delete_jm_page_image_cache']);
    responses[1].complete(reply(''));
    await deletion;
    await pumpEventQueue();
    expect(calls.last, 'jm_page_image');
    expect(calls.length, 3);
    responses[2].complete(reply('/new'));
    expect(await fresh, '/new');
    expect(await visible, '/new');
  });

  testWidgets(
      'viewport image keeps transition identity while increasing decode resolution',
      (tester) async {
    final response = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) => response.future);
    Widget screen(double scale) => MaterialApp(
        home: SizedBox(
            width: 400,
            height: 600,
            child: ViewportPageImage(
                id: 93, imageName: 'page', decodeScale: scale)));
    await tester.pumpWidget(screen(1));
    final lowWidget =
        tester.widget<FadingReaderImage>(find.byType(FadingReaderImage));
    final low = lowWidget.image as PageImageProvider;
    final state = tester.state(find.byType(FadingReaderImage));
    expect(low.targetWidth, isNotNull);
    await tester.pumpWidget(screen(2));
    final highWidget =
        tester.widget<FadingReaderImage>(find.byType(FadingReaderImage));
    final high = highWidget.image as PageImageProvider;
    expect(highWidget.identity, lowWidget.identity);
    expect(
        identical(state, tester.state(find.byType(FadingReaderImage))), isTrue);
    expect(high.targetWidth!, greaterThan(low.targetWidth!));
    response.complete(reply('/nonexistent-test-file'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'single file preview increases quality after pinch without replacing PhotoView',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: FilePhotoViewScreen('/nonexistent-preview')));
    final before = tester.state(find.byType(PhotoView));
    final low = tester
        .widget<FadingReaderImage>(find.byType(FadingReaderImage))
        .image as BoundedFileImage;
    expect(low.targetWidth, isNotNull);
    final photo = tester.widget<PhotoView>(find.byType(PhotoView));
    photo.scaleStateChangedCallback!(PhotoViewScaleState.originalSize);
    photo.scaleStateChangedCallback!(PhotoViewScaleState.initial);
    await tester.pump(const Duration(milliseconds: 140));
    final cancelledUpgrade = tester
        .widget<FadingReaderImage>(find.byType(FadingReaderImage))
        .image as BoundedFileImage;
    expect(cancelledUpgrade.targetWidth, low.targetWidth);
    photo.onScaleEnd!(
        tester.element(find.byType(PhotoView)),
        ScaleEndDetails(),
        const PhotoViewControllerValue(
            position: Offset.zero,
            scale: 2,
            rotation: 0,
            rotationFocusPoint: null));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump();
    final high = tester
        .widget<FadingReaderImage>(find.byType(FadingReaderImage))
        .image as BoundedFileImage;
    expect(high.targetWidth!, greaterThan(low.targetWidth!));
    expect(identical(before, tester.state(find.byType(PhotoView))), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'single file preview double tap still zooms and requests high quality',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: FilePhotoViewScreen('/nonexistent-double-tap-preview')));
    await tester.tap(find.byType(PhotoView));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(PhotoView));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final image = tester
        .widget<FadingReaderImage>(find.byType(FadingReaderImage))
        .image as BoundedFileImage;
    expect(image.targetWidth!, greaterThan(viewportImagePixels(800, 3)));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final mode in [ReaderType.gallery, ReaderType.twoPageGallery]) {
    testWidgets('$mode uses viewport decode and upgrades the zoomed page',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final imageRequests = <Completer<String>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        switch (request['method']) {
          case 'load_property':
            return reply({
                  'readerType': '$mode',
                  'readerDirection': 'ReaderDirection.leftToRight',
                  'ignoreVewLog': 'true'
                }[request['params']] ??
                '');
          case 'jm_page_image':
            final response = Completer<String>();
            imageRequests.add(response);
            return response.future;
          default:
            return reply('');
        }
      });
      await initReaderType();
      await initReaderDirection();
      await initIgnoreVewLog();
      await tester.pumpWidget(MaterialApp(
          home: ComicReaderScreen(
        comic:
            ComicBasic(id: 1, author: '', description: '', name: '', image: ''),
        series: const [],
        chapterId: 1,
        initRank: 0,
        loadChapter: (_) async => ChapterResponse(
            id: 1,
            series: const [],
            tags: '',
            name: '',
            images: List.generate(1000, (i) => '$i'),
            seriesId: 1,
            isFavorite: false,
            liked: false),
      )));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      final images = tester
          .widgetList<FadingReaderImage>(find.byType(FadingReaderImage))
          .where((i) => i.image is PageImageProvider)
          .toList();
      expect(images.length, greaterThan(0));
      expect(images.length, lessThan(10));
      final provider = images.first.image as PageImageProvider;
      expect(provider.targetWidth, mode == ReaderType.gallery ? 832 : 448);
      expect(images.first.statusScale, 2);
      if (mode == ReaderType.twoPageGallery) {
        expect(images.take(2).map((image) => image.alignment),
            [Alignment.centerRight, Alignment.centerLeft]);
      }
      final gallery =
          tester.widget<PhotoViewGallery>(find.byType(PhotoViewGallery));
      gallery.scaleStateChangedCallback!(PhotoViewScaleState.covering);
      gallery.scaleStateChangedCallback!(PhotoViewScaleState.initial);
      await tester.pump(const Duration(milliseconds: 140));
      final unchanged = tester
          .widgetList<FadingReaderImage>(find.byType(FadingReaderImage))
          .map((i) => i.image)
          .whereType<PageImageProvider>()
          .firstWhere((p) => p.imageName == '0');
      expect(unchanged.targetWidth, provider.targetWidth);
      // Exercise the actual gesture, not only the callback API.
      await tester.tap(find.byType(PhotoViewGallery));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(PhotoViewGallery));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      final current = tester
          .widgetList<FadingReaderImage>(find.byType(FadingReaderImage))
          .map((i) => i.image)
          .whereType<PageImageProvider>()
          .firstWhere((p) => p.imageName == '0');
      expect(current.targetWidth!, greaterThan(provider.targetWidth!));
      await tester.pumpWidget(const SizedBox());
      for (final pending in imageRequests) {
        pending.complete(reply('/nonexistent-gallery'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
