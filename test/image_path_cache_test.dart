import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/image_path_cache.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/basic/native_call_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completed hits validate asynchronously and skip repeated native work',
      () async {
    final check = Completer<bool>();
    var loads = 0;
    var checks = 0;
    final cache = ImagePathCache<String>(fileExists: (_) {
      checks++;
      return check.future;
    });
    Future<String> load() async => '/image-${++loads}';
    expect(await cache.getOrLoad('page', load), '/image-1');
    var completed = false;
    final second = cache.getOrLoad('page', load).then((value) {
      completed = true;
      return value;
    });
    await pumpEventQueue();
    expect(completed, isFalse);
    expect(checks, 1);
    check.complete(true);
    expect(await second, '/image-1');
    expect(loads, 1);
  });

  test('fixed TTL expires even when a hot entry is repeatedly used', () async {
    var elapsed = Duration.zero;
    var loads = 0;
    final cache = ImagePathCache<String>(
        ttl: const Duration(seconds: 10),
        elapsed: () => elapsed,
        fileExists: (_) async => true);
    Future<String> load() async => '/image-${++loads}';
    expect(await cache.getOrLoad('page', load), '/image-1');
    elapsed = const Duration(seconds: 9);
    expect(await cache.getOrLoad('page', load), '/image-1');
    elapsed = const Duration(seconds: 10);
    expect(await cache.getOrLoad('page', load), '/image-2');
  });

  test('capacity evicts the least recently used completed path', () async {
    var loads = 0;
    final cache =
        ImagePathCache<String>(capacity: 2, fileExists: (_) async => true);
    Future<String> load() async => '/image-${++loads}';
    expect(await cache.getOrLoad('a', load), '/image-1');
    expect(await cache.getOrLoad('b', load), '/image-2');
    expect(await cache.getOrLoad('a', load), '/image-1');
    expect(await cache.getOrLoad('c', load), '/image-3');
    expect(await cache.getOrLoad('a', load), '/image-1');
    expect(await cache.getOrLoad('b', load), '/image-4');
  });

  test('a vanished file is fetched again using real asynchronous disk checks',
      () async {
    final directory = await Directory.systemTemp.createTemp('jasmine-path-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/page');
    var loads = 0;
    Future<String> load() async {
      loads++;
      await file.writeAsString('image');
      return file.path;
    }

    final cache = ImagePathCache<String>();
    await cache.getOrLoad('page', load);
    await cache.getOrLoad('page', load);
    expect(loads, 1);
    await file.delete();
    expect(await cache.getOrLoad('page', load), file.path);
    expect(loads, 2);
  });

  test('failed and empty native results are not cached', () async {
    final cache = ImagePathCache<String>(fileExists: (_) async => true);
    await expectLater(
        cache.getOrLoad('page', () async => throw StateError('x')),
        throwsStateError);
    expect(await cache.getOrLoad('page', () async => ''), '');
    expect(
        await cache.getOrLoad('page', () async => '/recovered'), '/recovered');
  });

  test('existence check failure falls back to native resolution', () async {
    final cache = ImagePathCache<String>(
        fileExists: (_) async => throw const FileSystemException('gone'));
    await cache.getOrLoad('page', () async => '/old');
    expect(await cache.getOrLoad('page', () async => '/new'), '/new');
  });

  for (final all in [false, true]) {
    test(
        '${all ? "clear" : "delete"} rejects late reads from an old generation',
        () async {
      final cache = ImagePathCache<String>(fileExists: (_) async => true);
      final response = Completer<String>();
      final old = cache.getOrLoad('page', () => response.future);
      all ? cache.clear() : cache.invalidate('page');
      await cache.getOrLoad('page', () async => '/new');
      response.complete('/old');
      expect(await old, '/old');
      expect(
          await cache.getOrLoad('page', () => throw StateError('cache miss')),
          '/new');
    });
  }

  test('invalidation during disk verification cannot return its stale hit',
      () async {
    final check = Completer<bool>();
    final cache = ImagePathCache<String>(fileExists: (_) => check.future);
    await cache.getOrLoad('page', () async => '/old');
    final pending = cache.getOrLoad('page', () async => '/new');
    cache.invalidate('page');
    check.complete(true);
    expect(await pending, '/new');
  });

  test('reads during failed storage mutation are not retained', () async {
    final cache = ImagePathCache<String>(fileExists: (_) async => true);
    final mutation = Completer<void>();
    final operation = cache.invalidateDuring(() => mutation.future);
    final failed = expectLater(operation, throwsStateError);
    final late = Completer<String>();
    final read = cache.getOrLoad('late', () => late.future);
    await cache.getOrLoad('page', () async => '/during');
    expect(await cache.getOrLoad('page', () async => '/during-2'), '/during-2');
    mutation.completeError(StateError('mutation failed'));
    await failed;
    late.complete('/old');
    await read;
    expect(await cache.getOrLoad('page', () async => '/after'), '/after');
    expect(await cache.getOrLoad('late', () async => '/fresh'), '/fresh');
  });

  test('a key invalidation preserves unrelated completed entries', () async {
    final cache = ImagePathCache<String>(fileExists: (_) async => true);
    await cache.getOrLoad('a', () async => '/a');
    await cache.getOrLoad('b', () async => '/b');
    cache.invalidate('a');
    expect(
        await cache.getOrLoad('b', () => throw StateError('cache miss')), '/b');
  });

  test('cache misses retain scheduler merging and foreground promotion',
      () async {
    final cache = ImagePathCache<String>(fileExists: (_) async => true);
    final scheduler = NativeCallScheduler(maxActive: 2, maxBackground: 1);
    final blocker = Completer<String>();
    final active = NativeCallScheduler.speculative(
        () => scheduler.run(() => blocker.future),
        isCancelled: () => false);
    var obsolete = false;
    var calls = 0;
    final response = Completer<String>();
    Future<String> load() => scheduler.run(() {
          calls++;
          return response.future;
        }, sharedKey: 'page');
    final background = NativeCallScheduler.speculative(
        () => cache.getOrLoad('page', load),
        isCancelled: () => obsolete);
    expect(calls, 0);
    obsolete = true;
    final visible = cache.getOrLoad('page', load);
    expect(calls, 1);
    response.complete('/image');
    expect(await visible, '/image');
    expect(await background, '/image');
    blocker.complete('done');
    await active;
  });

  group('Methods cache integration', () {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String reply(String value) =>
        jsonEncode({'error_message': '', 'response_data': value});
    late Directory directory;
    late File file;
    late List<String> calls;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('jasmine-method-path-');
      file = await File('${directory.path}/page').writeAsString('image');
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final method = jsonDecode(call.arguments as String)['method'] as String;
        calls.add(method);
        return reply(method == 'jm_page_image' ? file.path : '');
      });
      await methods.init();
      calls.clear();
    });
    tearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });

    test('completed path reuse and explicit retry work with native deletion',
        () async {
      await methods.jmPageImage(700, 'page');
      expect(await methods.jmPageImage(700, 'page'), file.path);
      expect(calls, ['jm_page_image']);
      await methods.deleteJmPageImageCache(700, 'page');
      await methods.jmPageImage(700, 'page');
      expect(calls,
          ['jm_page_image', 'delete_jm_page_image_cache', 'jm_page_image']);
    });

    for (final operation in <String, Future<dynamic> Function()>{
      'clean_all_cache': () => methods.cleanAllCache(),
      'init_dart': () => methods.init(),
      'init_dart2': () => methods.init2(),
      'set_download_and_export_to': () =>
          methods.setDownloadAndExportTo('/test-directory'),
    }.entries) {
      test('${operation.key} invalidates completed paths', () async {
        await methods.jmPageImage(700, 'page');
        await operation.value();
        await methods.jmPageImage(700, 'page');
        expect(calls, ['jm_page_image', operation.key, 'jm_page_image']);
      });
    }

    test('global clear detaches old in-flight native reads from new requests',
        () async {
      final oldResponse = Completer<String>();
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final method = jsonDecode(call.arguments as String)['method'] as String;
        calls.add(method);
        if (method == 'jm_page_image') {
          if (++reads == 1) return oldResponse.future;
          return reply(file.path);
        }
        return reply('');
      });
      final old = methods.jmPageImage(701, 'page');
      await pumpEventQueue();
      await methods.cleanAllCache();
      final fresh = methods.jmPageImage(701, 'page');
      oldResponse.complete(reply('/stale'));
      expect(await old, '/stale');
      expect(await fresh, file.path);
      expect(await methods.jmPageImage(701, 'page'), file.path);
      expect(reads, 2);
    });
  });
}
