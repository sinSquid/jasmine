import 'dart:async';
import 'package:flutter/foundation.dart';
import 'debounced_writer.dart';
import 'dart:io';

import 'package:jasmine/basic/methods.dart';
import 'package:window_manager/window_manager.dart';

onDesktopStart() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    windowManager.ensureInitialized();
    windowManager.addListener(winListener);
  }
}

onDesktopStop() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    windowManager.removeListener(winListener);
    unawaited(winListener.flush());
  }
}

final winListener = WinListener();

class WinListener with WindowListener {
  final _writer = DebouncedWriter<bool>((_) async {
    final size = await windowManager.getSize();
    await methods.saveProperty('window_width', '${size.width.toInt()}');
    await methods.saveProperty('window_height', '${size.height.toInt()}');
  }, onError: (_, __) => debugPrint('窗口尺寸保存失败'));

  @override
  void onWindowResize() => _writer.add(true);
  Future<void> flush() => _writer.flush();
}
