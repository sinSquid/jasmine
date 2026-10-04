import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/reader_image_dimensions.dart';
import 'package:jasmine/screens/components/fading_reader_image.dart';
import 'package:jasmine/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void cacheFrame(String path) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 20, 40), Paint()..color = Colors.blue);
    final picture = recorder.endRecording();
    final frame = picture.toImageSync(20, 40);
    picture.dispose();
    PaintingBinding.instance.imageCache.putIfAbsent(
        BoundedFileImage(path),
        () => OneFrameImageStreamCompleter(
            SynchronousFuture(ImageInfo(image: frame))));
  }

  Widget screen(Future<String> path) => MaterialApp(
        home: Center(
          child: Builder(
            builder: (context) => pathFutureImage(context, path, 100, 200),
          ),
        ),
      );

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    readerImageDimensions.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('path lookup and cached frame share one reserved fading cell',
      (tester) async {
    const path = '/cached-transition.png';
    cacheFrame(path);
    final response = Completer<String>();
    await tester.pumpWidget(screen(response.future));
    final finder = find.byType(FadingReaderImage);
    final before = tester.state(finder);
    expect(tester.getSize(finder), const Size(100, 200));
    expect(tester.widget<FadingReaderImage>(finder).image, isNull);
    expect(find.byType(ReaderImagePlaceholder), findsOneWidget);

    response.complete(path);
    await tester.pump();
    expect(identical(tester.state(finder), before), isTrue);
    final transitions = tester
        .widgetList<FadeTransition>(
            find.descendant(of: finder, matching: find.byType(FadeTransition)))
        .toList();
    expect(transitions.first.opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 70));
    expect(transitions.first.opacity.value, inExclusiveRange(0, 1));
    expect(transitions.last.opacity.value, inExclusiveRange(0, 1));
    expect(transitions.first.opacity.value + transitions.last.opacity.value,
        closeTo(1, 0.0001));
    expect(tester.getSize(finder), const Size(100, 200));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replaced path lookup cannot remove the new placeholder',
      (tester) async {
    final oldPath = Completer<String>();
    final newPath = Completer<String>();
    await tester.pumpWidget(screen(oldPath.future));
    await tester.pumpWidget(screen(newPath.future));
    oldPath.complete('/stale-path.png');
    await tester.pump();
    final cell =
        tester.widget<FadingReaderImage>(find.byType(FadingReaderImage));
    expect(cell.image, isNull);
    expect(cell.identity, newPath.future);
    expect(
        tester.getSize(find.byType(FadingReaderImage)), const Size(100, 200));
    cacheFrame('/fresh-path.png');
    newPath.complete('/fresh-path.png');
    await tester.pumpAndSettle();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed optional size metadata still displays the whole image',
      (tester) async {
    const path = '/cached-metadata-fallback.png';
    cacheFrame(path);
    final requests = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final method = jsonDecode(call.arguments as String)['method'] as String;
      requests.add(method);
      return jsonEncode({
        'error_message': method == 'image_size' ? 'metadata unavailable' : '',
        'response_data': path,
      });
    });
    final dimensions = ValueNotifier<Size?>(null);
    addTearDown(dimensions.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: ValueListenableBuilder<Size?>(
      valueListenable: dimensions,
      builder: (context, size, _) => JMPageImage(9801, 'metadata-fallback',
          width: 100,
          height: size == null ? 150 : 100 * size.height / size.width,
          knownSize: size,
          onTrueSize: (size) => dimensions.value = size),
    ))));
    await tester.pumpAndSettle();
    expect(requests, ['jm_page_image', 'image_size']);
    expect(dimensions.value, const Size(20, 40));
    expect(readerImageDimensions.get(9801, 'metadata-fallback'),
        const Size(20, 40));
    expect(
        tester.getSize(find.byType(FadingReaderImage)), const Size(100, 200));
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, isNotNull);
    expect(raw.fit, BoxFit.contain);
    expect(find.byType(ReaderImagePlaceholder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalidated metadata cannot overwrite the displayed frame ratio',
      (tester) async {
    const path = '/cached-stale-metadata.png';
    cacheFrame(path);
    final header = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final method = jsonDecode(call.arguments as String)['method'] as String;
      if (method == 'image_size') return header.future;
      return jsonEncode({'error_message': '', 'response_data': path});
    });
    final received = <Size>[];
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: JMPageImage(9802, 'stale-metadata',
                width: 100, height: 150, onTrueSize: received.add))));
    await tester.pump();
    readerImageDimensions.invalidate(9802, 'stale-metadata');
    header.complete(jsonEncode({
      'error_message': '',
      'response_data': jsonEncode({'w': 40, 'h': 20}),
    }));
    await tester.pumpAndSettle();
    expect(received, [const Size(20, 40)]);
    expect(readerImageDimensions.get(9802, 'stale-metadata'), isNull);
    expect(tester.takeException(), isNull);
  });
}
