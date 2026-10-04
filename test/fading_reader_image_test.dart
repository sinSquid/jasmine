import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/fading_reader_image.dart';

class _ControlledCompleter extends ImageStreamCompleter {
  final listeners = <ImageStreamListener>[];

  @override
  void addListener(ImageStreamListener listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }

  void emit(ui.Image image) => setImage(ImageInfo(image: image.clone()));

  void fail() => reportError(
      exception: StateError('controlled image failure'),
      context: ErrorDescription('loading a test image'));
}

class _ControlledProvider extends ImageProvider<_ControlledProvider> {
  _ControlledProvider(this.completer);
  _ControlledCompleter completer;
  int loads = 0;

  @override
  Future<_ControlledProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _ControlledProvider key, ImageDecoderCallback decode) {
    loads++;
    return completer;
  }
}

class _DelayedKeyProvider extends _ControlledProvider {
  _DelayedKeyProvider(super.completer);
  final key = Completer<_ControlledProvider>();

  @override
  Future<_ControlledProvider> obtainKey(ImageConfiguration configuration) =>
      key.future;
}

void main() {
  final ownedImages = <ui.Image>[];
  ui.Image createImage(Color color, {int width = 8, int height = 12}) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = color);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    ownedImages.add(image);
    return image;
  }

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    for (final image in ownedImages) {
      image.dispose();
    }
    ownedImages.clear();
  });

  Widget screen(ImageProvider? provider,
          {Object identity = 'page',
          bool reduceMotion = false,
          ImageProvider? initial,
          VoidCallback? onReload,
          ValueChanged<Size>? onImageSize,
          double width = 200,
          double height = 300,
          double statusScale = 1,
          double canvasScale = 1,
          Alignment alignment = Alignment.center}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Center(
            child: Transform.scale(
              scale: canvasScale,
              child: FadingReaderImage(
                image: provider,
                identity: identity,
                initialImageProvider: initial,
                width: width,
                height: height,
                onReload: onReload,
                onImageSize: onImageSize,
                statusScale: statusScale,
                alignment: alignment,
              ),
            ),
          ),
        ),
      );

  RawImage raw(WidgetTester tester) => tester.widget<RawImage>(find.descendant(
      of: find.byType(FadingReaderImage), matching: find.byType(RawImage)));

  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find
          .descendant(
              of: find.byType(FadingReaderImage),
              matching: find.byType(FadeTransition))
          .first)
      .opacity
      .value;

  testWidgets('static loading placeholder fades out only after the first frame',
      (tester) async {
    final completer = _ControlledCompleter();
    final provider = _ControlledProvider(completer);
    final image = createImage(Colors.red);
    await tester.pumpWidget(screen(provider));
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    expect(raw(tester).image, isNull);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);

    completer.emit(image);
    await tester.pump();
    expect(raw(tester).image!.isCloneOf(image), isTrue);
    expect(opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 140));
    expect(opacity(tester), closeTo(Curves.easeOutCubic.transform(0.5), 0.02));
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a failed upgrade keeps the old frame and retries only its key',
      (tester) async {
    final lowStream = _ControlledCompleter();
    final highStream = _ControlledCompleter();
    final low = _ControlledProvider(lowStream);
    final high = _ControlledProvider(highStream);
    final lowImage = createImage(Colors.red);
    final highImage = createImage(Colors.blue);
    var fullReloads = 0;
    await tester.pumpWidget(screen(low));
    lowStream.emit(lowImage);
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen(high, onReload: () => fullReloads++));
    expect(raw(tester).image!.isCloneOf(lowImage), isTrue);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    highStream.fail();
    await tester.pump();
    expect(raw(tester).image!.isCloneOf(lowImage), isTrue);
    expect(find.byTooltip('高清加载失败，重试'), findsOneWidget);
    expect(find.text('图片加载失败'), findsNothing);

    final retryStream = _ControlledCompleter();
    high.completer = retryStream;
    await tester.tap(find.byTooltip('高清加载失败，重试'));
    await tester.pump();
    expect(fullReloads, 0);
    expect(high.loads, 2);
    expect(raw(tester).image!.isCloneOf(lowImage), isTrue);
    expect(PaintingBinding.instance.imageCache.containsKey(low), isTrue);
    retryStream.emit(highImage);
    await tester.pump();
    expect(raw(tester).image!.isCloneOf(highImage), isTrue);
    expect(opacity(tester), 1);
    expect(find.byTooltip('高清加载失败，重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing identity clears the frame and ignores old callbacks',
      (tester) async {
    final firstStream = _ControlledCompleter();
    final nextStream = _ControlledCompleter();
    final first = _ControlledProvider(firstStream);
    final next = _ControlledProvider(nextStream);
    final image = createImage(Colors.red);
    await tester.pumpWidget(screen(first));
    final oldListener = firstStream.listeners.last;
    firstStream.emit(image);
    await tester.pumpAndSettle();
    final oldDisplayedHandle = raw(tester).image!;

    await tester.pumpWidget(screen(next, identity: 'next-page'));
    expect(raw(tester).image, isNull);
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    expect(firstStream.listeners, isNot(contains(oldListener)));
    expect(oldDisplayedHandle.debugDisposed, isTrue);
    final obsolete = ImageInfo(image: image.clone());
    oldListener.onImage(obsolete, false);
    oldListener.onError!(StateError('late error'), StackTrace.current);
    await tester.pump();
    expect(obsolete.image.debugDisposed, isTrue);
    expect(raw(tester).image, isNull);
    expect(find.text('图片加载失败'), findsNothing);
  });

  testWidgets('leaving during fade releases its listener, frame and ticker',
      (tester) async {
    final completer = _ControlledCompleter();
    final image = createImage(Colors.red);
    await tester.pumpWidget(screen(_ControlledProvider(completer)));
    final listener = completer.listeners.last;
    completer.emit(image);
    await tester.pump();
    final displayed = raw(tester).image!;
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(completer.listeners, isNot(contains(listener)));
    expect(displayed.debugDisposed, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    final obsolete = ImageInfo(image: image.clone());
    listener.onImage(obsolete, false);
    listener.onError!(StateError('after dispose'), StackTrace.current);
    expect(obsolete.image.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion displays the first image immediately',
      (tester) async {
    final completer = _ControlledCompleter();
    final image = createImage(Colors.red);
    await tester
        .pumpWidget(screen(_ControlledProvider(completer), reduceMotion: true));
    completer.emit(image);
    await tester.pump();
    expect(raw(tester).image!.isCloneOf(image), isTrue);
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a synchronous cache hit skips the fade and additional loading',
      (tester) async {
    final completer = _ControlledCompleter();
    final provider = _ControlledProvider(completer);
    final image = createImage(Colors.red);
    await tester.pumpWidget(screen(provider));
    completer.emit(image);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen(provider));
    expect(provider.loads, 1);
    expect(raw(tester).image!.isCloneOf(image), isTrue);
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a painted placeholder fades into a later synchronous cache hit',
      (tester) async {
    final completer = _ControlledCompleter();
    final provider = _ControlledProvider(completer);
    final image = createImage(Colors.red);
    completer.emit(image);
    PaintingBinding.instance.imageCache.putIfAbsent(provider, () => completer);

    await tester.pumpWidget(screen(null));
    final placeholderElement = tester.element(find.byType(FadingReaderImage));
    expect(raw(tester).image, isNull);
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(screen(provider));
    expect(tester.element(find.byType(FadingReaderImage)), placeholderElement);
    expect(raw(tester).image!.isCloneOf(image), isTrue);
    expect(opacity(tester), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final imageOpacity = opacity(tester);
    expect(imageOpacity, greaterThan(0));
    expect(imageOpacity, lessThan(1));
    final placeholderOpacity = tester
        .widget<FadeTransition>(find
            .descendant(
                of: find.byType(FadingReaderImage),
                matching: find.byType(FadeTransition))
            .last)
        .opacity
        .value;
    expect(placeholderOpacity, closeTo(1 - imageOpacity, 0.001));
    expect(provider.loads, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion skips the nullable placeholder transition',
      (tester) async {
    final completer = _ControlledCompleter();
    final provider = _ControlledProvider(completer);
    final image = createImage(Colors.red);
    completer.emit(image);
    PaintingBinding.instance.imageCache.putIfAbsent(provider, () => completer);
    await tester.pumpWidget(screen(null, reduceMotion: true));
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    await tester.pumpWidget(screen(provider, reduceMotion: true));
    expect(raw(tester).image!.isCloneOf(image), isTrue);
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('switching identity cancels an old fade and resets painted state',
      (tester) async {
    final firstStream = _ControlledCompleter();
    final nextStream = _ControlledCompleter();
    final first = _ControlledProvider(firstStream);
    final next = _ControlledProvider(nextStream);
    final firstImage = createImage(Colors.red);
    final nextImage = createImage(Colors.blue);
    firstStream.emit(firstImage);
    nextStream.emit(nextImage);
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(first, () => firstStream);
    cache.putIfAbsent(next, () => nextStream);
    await tester.pumpWidget(screen(null));
    await tester.pumpWidget(screen(first));
    final oldListener = firstStream.listeners.last;
    final oldFrame = raw(tester).image!;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(opacity(tester), inExclusiveRange(0, 1));

    await tester.pumpWidget(screen(next, identity: 'another-page'));
    expect(oldFrame.debugDisposed, isTrue);
    expect(raw(tester).image!.isCloneOf(nextImage), isTrue);
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    final lateFrame = ImageInfo(image: firstImage.clone());
    oldListener.onImage(lateFrame, false);
    expect(lateFrame.image.debugDisposed, isTrue);
    expect(raw(tester).image!.isCloneOf(nextImage), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'returning to a pending file stops its fade and detaches the frame',
      (tester) async {
    final completer = _ControlledCompleter();
    final provider = _ControlledProvider(completer);
    final image = createImage(Colors.red);
    await tester.pumpWidget(screen(provider));
    final listener = completer.listeners.last;
    completer.emit(image);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final oldFrame = raw(tester).image!;
    expect(opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpWidget(screen(null));
    expect(completer.listeners, isNot(contains(listener)));
    expect(oldFrame.debugDisposed, isTrue);
    expect(raw(tester).image, isNull);
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    final lateFrame = ImageInfo(image: image.clone());
    listener.onImage(lateFrame, false);
    expect(lateFrame.image.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the optional initial provider only uses an existing cached frame',
      (tester) async {
    final cachedStream = _ControlledCompleter();
    final cached = _ControlledProvider(cachedStream);
    final image = createImage(Colors.red);
    await tester.pumpWidget(screen(cached));
    cachedStream.emit(image);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    final primary = _ControlledProvider(_ControlledCompleter());
    await tester.pumpWidget(screen(primary, initial: cached));
    await tester.pumpAndSettle();
    expect(cached.loads, 1);
    expect(raw(tester).image!.isCloneOf(image), isTrue);
    expect(opacity(tester), 1);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);

    final missing = _ControlledProvider(_ControlledCompleter());
    await tester.pumpWidget(screen(_ControlledProvider(_ControlledCompleter()),
        identity: 'other', initial: missing));
    await tester.pump();
    expect(missing.loads, 0);
    expect(raw(tester).image, isNull);
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
  });

  testWidgets('a late initial cache lookup never replaces the primary frame',
      (tester) async {
    final initialStream = _ControlledCompleter();
    final initial = _DelayedKeyProvider(initialStream);
    final initialImage = createImage(Colors.red);
    initialStream.emit(initialImage);
    PaintingBinding.instance.imageCache
        .putIfAbsent(initial, () => initialStream);
    final primaryStream = _ControlledCompleter();
    final primaryImage = createImage(Colors.blue);
    await tester.pumpWidget(
        screen(_ControlledProvider(primaryStream), initial: initial));
    primaryStream.emit(primaryImage);
    await tester.pumpAndSettle();
    initial.key.complete(initial);
    await tester.pump();
    expect(raw(tester).image!.isCloneOf(primaryImage), isTrue);
    expect(initial.loads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-frame failure exposes external and internal retries',
      (tester) async {
    final externalStream = _ControlledCompleter();
    var reloads = 0;
    await tester.pumpWidget(
        screen(_ControlledProvider(externalStream), onReload: () => reloads++));
    externalStream.fail();
    await tester.pump();
    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    await tester.tap(find.text('重试'));
    expect(reloads, 1);

    final failed = _ControlledCompleter();
    final provider = _ControlledProvider(failed);
    await tester.pumpWidget(screen(provider, identity: 'internal'));
    failed.fail();
    await tester.pump();
    provider.completer = _ControlledCompleter();
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(provider.loads, 2);
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);
    provider.completer.emit(createImage(Colors.red));
    await tester.pumpAndSettle();
    expect(find.text('图片加载失败'), findsNothing);
    expect(raw(tester).image, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'small failed thumbnails retain a tappable retry without overflow',
      (tester) async {
    var retries = 0;
    for (final size in [const Size(75, 100), const Size(20, 20)]) {
      for (final scale in [1.0, 2.0]) {
        final completer = _ControlledCompleter();
        final provider = _ControlledProvider(completer);
        await tester.pumpWidget(screen(provider,
            identity: provider,
            width: size.width,
            height: size.height,
            statusScale: scale,
            onReload: () => retries++));
        completer.fail();
        await tester.pump();
        expect(find.text('图片加载失败'), findsNothing);
        expect(find.byTooltip('图片加载失败，重试'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('图片加载失败，重试'));
      }
    }
    expect(retries, 4);
  });

  testWidgets('scaled reader canvases keep loading and retry at readable sizes',
      (tester) async {
    final lowStream = _ControlledCompleter();
    final highStream = _ControlledCompleter();
    final low = _ControlledProvider(lowStream);
    final high = _ControlledProvider(highStream);
    Widget scaled(ImageProvider provider) => screen(provider,
        width: 400,
        height: 600,
        statusScale: 2,
        canvasScale: 0.5,
        alignment: Alignment.centerRight);
    await tester.pumpWidget(scaled(low));
    final loadingIcon = find.byIcon(Icons.image_outlined);
    final loadingSize =
        tester.getBottomRight(loadingIcon) - tester.getTopLeft(loadingIcon);
    expect(loadingSize.dx, 24);
    expect(loadingSize.dy, 24);
    lowStream.emit(createImage(Colors.red));
    await tester.pumpAndSettle();
    expect(raw(tester).alignment, Alignment.centerRight);
    await tester.pumpWidget(scaled(high));
    highStream.fail();
    await tester.pump();
    final retry = find.byType(IconButton);
    final retrySize = tester.getBottomRight(retry) - tester.getTopLeft(retry);
    expect(retrySize.dx, greaterThanOrEqualTo(40));
    expect(retrySize.dy, greaterThanOrEqualTo(40));
    high.completer = _ControlledCompleter();
    await tester.tap(find.byTooltip('高清加载失败，重试'));
    await tester.pump();
    expect(high.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary dimensions report after layout to the current callback',
      (tester) async {
    final firstCallbackSizes = <Size>[];
    final currentCallbackSizes = <Size>[];
    final lowStream = _ControlledCompleter();
    final highStream = _ControlledCompleter();
    final low = _ControlledProvider(lowStream);
    final high = _ControlledProvider(highStream);
    final lowImage = createImage(Colors.red);
    final highImage = createImage(Colors.blue, width: 16, height: 24);
    await tester.pumpWidget(screen(low, onImageSize: firstCallbackSizes.add));
    lowStream.emit(lowImage);
    expect(firstCallbackSizes, isEmpty);
    await tester.pumpWidget(screen(low, onImageSize: currentCallbackSizes.add));
    expect(firstCallbackSizes, isEmpty);
    expect(currentCallbackSizes, [const Size(8, 12)]);
    lowStream.emit(lowImage);
    await tester.pump();
    await tester
        .pumpWidget(screen(high, onImageSize: currentCallbackSizes.add));
    highStream.emit(highImage);
    await tester.pump();
    expect(raw(tester).image!.isCloneOf(highImage), isTrue);
    expect(currentCallbackSizes, [const Size(8, 12)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached fallback dimensions are not reported as primary metadata',
      (tester) async {
    final fallbackStream = _ControlledCompleter();
    final fallback = _ControlledProvider(fallbackStream);
    final fallbackImage = createImage(Colors.red, width: 2, height: 3);
    fallbackStream.emit(fallbackImage);
    PaintingBinding.instance.imageCache
        .putIfAbsent(fallback, () => fallbackStream);
    final primaryStream = _ControlledCompleter();
    final primary = _ControlledProvider(primaryStream);
    final primaryImage = createImage(Colors.blue, width: 8, height: 80);
    final sizes = <Size>[];
    await tester
        .pumpWidget(screen(primary, initial: fallback, onImageSize: sizes.add));
    await tester.pumpAndSettle();
    expect(raw(tester).image!.isCloneOf(fallbackImage), isTrue);
    expect(sizes, isEmpty);
    primaryStream.emit(primaryImage);
    expect(sizes, isEmpty);
    await tester.pump();
    expect(sizes, [const Size(8, 80)]);
  });

  testWidgets('switching images discards a pending dimension notification',
      (tester) async {
    final oldStream = _ControlledCompleter();
    final nextStream = _ControlledCompleter();
    final sizes = <Size>[];
    await tester.pumpWidget(screen(_ControlledProvider(oldStream),
        identity: 'old', onImageSize: sizes.add));
    oldStream.emit(createImage(Colors.red));
    expect(sizes, isEmpty);
    await tester.pumpWidget(screen(_ControlledProvider(nextStream),
        identity: 'next', onImageSize: sizes.add));
    expect(sizes, isEmpty);
    nextStream.emit(createImage(Colors.blue, width: 16, height: 40));
    await tester.pump();
    expect(sizes, [const Size(16, 40)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the reader cancels its deferred size notification',
      (tester) async {
    final stream = _ControlledCompleter();
    final sizes = <Size>[];
    await tester.pumpWidget(
        screen(_ControlledProvider(stream), onImageSize: sizes.add));
    stream.emit(createImage(Colors.red));
    expect(sizes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sizes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new provider generation invalidates a queued size callback',
      (tester) async {
    final oldStream = _ControlledCompleter();
    final nextStream = _ControlledCompleter();
    final sizes = <Size>[];
    await tester.pumpWidget(
        screen(_ControlledProvider(oldStream), onImageSize: sizes.add));
    oldStream.emit(createImage(Colors.red));
    await tester.pumpWidget(
        screen(_ControlledProvider(nextStream), onImageSize: sizes.add));
    expect(sizes, isEmpty);
    nextStream.emit(createImage(Colors.blue, width: 16, height: 24));
    await tester.pump();
    expect(sizes, [const Size(16, 24)]);
  });
}
