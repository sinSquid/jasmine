import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_svg/svg.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'dart:io';
import 'dart:ui' as ui show Codec, ImmutableBuffer, TargetImageSize;
import 'dart:math' as math;

import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/screens/components/types.dart';

import '../file_photo_view_screen.dart';

//JM3x4Cover
class JM3x4ImageProvider extends ImageProvider<JM3x4ImageProvider> {
  final int comicId;
  final double scale;

  JM3x4ImageProvider(this.comicId, {this.scale = 1.0});

  @override
  ImageStreamCompleter loadImage(
      JM3x4ImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
    );
  }

  @override
  Future<JM3x4ImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<JM3x4ImageProvider>(this);
  }

  Future<ui.Codec> _loadAsync(
      JM3x4ImageProvider key, ImageDecoderCallback decode) async {
    assert(key == this);
    final path = await methods.jm3x4Cover(comicId);
    return decode(await ui.ImmutableBuffer.fromFilePath(path));
  }

  @override
  bool operator ==(Object other) {
    if (other is! JM3x4ImageProvider) return false;
    return comicId == other.comicId && scale == other.scale;
  }

  @override
  int get hashCode => Object.hash(comicId, scale);

  @override
  String toString() => '$runtimeType('
      ' comicId: ${describeIdentity(comicId)},'
      ' scale: $scale'
      ')';
}

//JM3x4Cover
class PageImageProvider extends ImageProvider<PageImageProvider> {
  final int id;
  final String imageName;
  final double scale;

  PageImageProvider(this.id, this.imageName, {this.scale = 1.0});

  @override
  ImageStreamCompleter loadImage(
      PageImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
    );
  }

  @override
  Future<PageImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<PageImageProvider>(this);
  }

  Future<ui.Codec> _loadAsync(
      PageImageProvider key, ImageDecoderCallback decode) async {
    assert(key == this);
    final path = await methods.jmPageImage(id, imageName);
    return decode(await ui.ImmutableBuffer.fromFilePath(path),
        getTargetSize: boundedPageImageSize);
  }

  @override
  bool operator ==(Object other) {
    if (other is! PageImageProvider) return false;
    return id == other.id &&
        imageName == other.imageName &&
        scale == other.scale;
  }

  @override
  int get hashCode => Object.hash(id, imageName, scale);

  @override
  String toString() => '$runtimeType('
      ' id: ${describeIdentity(id)},'
      ' imageName: ${describeIdentity(imageName)},'
      ' scale: $scale'
      ')';
}

// 远端图片
class JM3x4Cover extends StatefulWidget {
  final int comicId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;

  const JM3x4Cover({
    Key? key,
    required this.comicId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.longPressMenuItems,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JM3x4CoverState();
}

class _JM3x4CoverState extends State<JM3x4Cover> {
  late Future<String> _future;

  @override
  void initState() {
    _future = methods.jm3x4Cover(widget.comicId);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant JM3x4Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId) {
      _future = methods.jm3x4Cover(widget.comicId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      fit: widget.fit,
      longPressMenuItems: widget.longPressMenuItems,
      maxCacheWidth: 2048,
    );
  }
}

// 远端图片
class JMSquareCover extends StatefulWidget {
  final int comicId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;

  const JMSquareCover({
    Key? key,
    required this.comicId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.longPressMenuItems,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMSquareCoverState();
}

class _JMSquareCoverState extends State<JMSquareCover> {
  late Future<String> _future;

  @override
  void initState() {
    _future = methods.jmSquareCover(widget.comicId);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant JMSquareCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId) {
      _future = methods.jmSquareCover(widget.comicId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      fit: widget.fit,
      longPressMenuItems: widget.longPressMenuItems,
      maxCacheWidth: 2048,
    );
  }
}

class JMPhotoImage extends StatefulWidget {
  final String photoName;

  final double? width;
  final double? height;
  final BoxFit fit;

  const JMPhotoImage({
    Key? key,
    required this.photoName,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMPhotoImageState();
}

class _JMPhotoImageState extends State<JMPhotoImage> {
  late Future<String> _future;

  @override
  void initState() {
    _future = methods.jmPhotoImage(widget.photoName);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant JMPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoName != widget.photoName) {
      _future = methods.jmPhotoImage(widget.photoName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      fit: widget.fit,
      maxCacheWidth: 2048,
    );
  }
}

//
class JMPageImage extends StatefulWidget {
  final int id;
  final String imageName;
  final double? width;
  final double? height;
  final Function(Size size)? onTrueSize;
  final bool decodeToDisplayWidth;

  const JMPageImage(this.id, this.imageName,
      {Key? key,
      this.width,
      this.height,
      this.onTrueSize,
      this.decodeToDisplayWidth = false})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMPageImageState();
}

class _JMPageImageState extends State<JMPageImage> {
  Future<String>? _future;
  Key _futureKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _future = _init();
  }

  @override
  void didUpdateWidget(covariant JMPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.imageName != widget.imageName) {
      _futureKey = UniqueKey();
      _future = _init();
    }
  }

  Future<String> _init() async {
    final id = widget.id;
    final imageName = widget.imageName;
    final path = await methods.jmPageImage(id, imageName);
    if (mounted &&
        widget.id == id &&
        widget.imageName == imageName &&
        widget.onTrueSize != null) {
      final size = await methods.imageSize(path);
      if (mounted &&
          widget.id == id &&
          widget.imageName == imageName &&
          widget.onTrueSize != null) {
        widget.onTrueSize!(Size(size.w.toDouble(), size.h.toDouble()));
      }
    }
    return path;
  }

  void _reload() {
    if (mounted) {
      // 先清除旧的 Future，然后创建新的
      setState(() {
        _future = null;
        _futureKey = UniqueKey();
      });
      // 在下一帧创建新的 Future，确保 FutureBuilder 完全重建
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _future = _init();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果 future 为 null，显示加载状态
    if (_future == null) {
      return buildLoading(
        context,
        widget.width,
        widget.height,
      );
    }
    return pathFutureImage(
      context,
      _future!,
      widget.width,
      widget.height,
      key: _futureKey,
      onReload: _reload,
      maxCacheWidth: widget.decodeToDisplayWidth ? 4096 : null,
    );
  }
}

Widget pathFutureImage(
    BuildContext context, Future<String> future, double? width, double? height,
    {BoxFit fit = BoxFit.cover,
    List<LongPressMenuItem>? longPressMenuItems,
    Key? key,
    VoidCallback? onReload,
    int? maxCacheWidth}) {
  // 使用 key 来确保 FutureBuilder 完全重建
  return FutureBuilder<String>(
      key: key,
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        // 检查是否有错误
        if (snapshot.hasError) {
          debugPrient("${snapshot.error}");
          debugPrient("${snapshot.stackTrace}");
          return buildError(
            context,
            width,
            height,
            longPressMenuItems: longPressMenuItems,
            onReload: onReload,
          );
        }
        // 检查是否完成
        if (snapshot.connectionState == ConnectionState.done) {
          return buildFile(
            context,
            snapshot.data!,
            width,
            height,
            fit: fit,
            longPressMenuItems: longPressMenuItems,
            maxCacheWidth: maxCacheWidth,
          );
        }
        // 其他状态（waiting, active, none）都显示加载状态
        return buildLoading(
          context,
          width,
          height,
          longPressMenuItems: longPressMenuItems,
        );
      });
}

// 通用方法

Widget buildSvg(String source, double? width, double? height,
    {Color? color, double? margin}) {
  var widget = Container(
    width: width,
    height: height,
    padding: margin != null ? const EdgeInsets.all(10) : null,
    child: Center(
      child: SvgPicture.asset(
        source,
        width: width,
        height: height,
        color: color,
      ),
    ),
  );
  return GestureDetector(onLongPress: () {}, child: widget);
}

Widget buildMock(double? width, double? height) {
  var widget = Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(10),
    child: Center(
      child: SvgPicture.asset(
        'lib/assets/unknown.svg',
        width: width,
        height: height,
        color: Colors.grey.shade600,
      ),
    ),
  );
  return GestureDetector(onLongPress: () {}, child: widget);
}

Widget buildError(BuildContext context, double? width, double? height,
    {List<LongPressMenuItem>? longPressMenuItems, VoidCallback? onReload}) {
  double? size;
  if (width != null && height != null) {
    size = width < height ? width : height;
  }
  var error = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(
        Icons.error_outline,
        size: size,
        color: Colors.grey,
      ),
    ),
  );
  if (onReload != null ||
      (longPressMenuItems != null && longPressMenuItems.isNotEmpty)) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        List<String> menuItems = [];
        if (onReload != null) {
          menuItems.add('重新加载');
        }
        if (longPressMenuItems != null && longPressMenuItems.isNotEmpty) {
          menuItems.addAll(longPressMenuItems.map((e) => e.title));
        }
        if (menuItems.isEmpty) return;

        String? choose = await chooseListDialog(
          context,
          title: '请选择',
          values: menuItems,
        );
        if (choose == '重新加载' && onReload != null) {
          onReload();
        } else {
          for (var item in longPressMenuItems ?? []) {
            if (item.title == choose) {
              item.onChoose();
              break;
            }
          }
        }
      },
      child: error,
    );
  }
  return error;
}

Widget buildLoading(BuildContext context, double? width, double? height,
    {List<LongPressMenuItem>? longPressMenuItems}) {
  double? size;
  if (width != null && height != null) {
    size = width < height ? width : height;
  }
  var loading = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(
        Icons.downloading,
        size: size,
        color: Colors.grey.withAlpha(150),
      ),
    ),
  );
  if (longPressMenuItems != null && longPressMenuItems.isNotEmpty) {
    return GestureDetector(
      onLongPress: () async {
        String? choose = await chooseListDialog(
          context,
          title: '请选择',
          values: longPressMenuItems.map((e) => e.title).toList(),
        );
        for (var item in longPressMenuItems) {
          if (item.title == choose) {
            item.onChoose();
            break;
          }
        }
      },
      child: loading,
    );
  }
  return loading;
}

Widget buildFile(
    BuildContext context, String file, double? width, double? height,
    {BoxFit fit = BoxFit.cover,
    List<LongPressMenuItem>? longPressMenuItems,
    int? maxCacheWidth}) {
  final pixelWidth =
      maxCacheWidth != null && width != null && width.isFinite && width > 0
          ? (width * MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(1, maxCacheWidth)
          : null;
  var image = Image.file(
    File(file),
    cacheWidth: pixelWidth,
    width: width,
    height: height,
    errorBuilder: (a, b, c) {
      debugPrient("$b");
      debugPrient("$c");
      return buildError(context, width, height);
    },
    fit: fit,
  );
  return GestureDetector(
    onLongPress: () async {
      String? choose = await chooseListDialog(
        context,
        title: '请选择',
        values: [
          '预览图片',
          ...Platform.isAndroid || Platform.isIOS
              ? [
                  '保存图片到相册',
                ]
              : [],
          ...!Platform.isIOS
              ? [
                  '保存图片到文件',
                ]
              : [],
          ...longPressMenuItems?.map((e) => e.title) ?? [],
        ],
      );
      switch (choose) {
        case '预览图片':
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => FilePhotoViewScreen(file),
          ));
          break;
        case '保存图片到相册':
          saveImageFileToGallery(context, file);
          break;
        case '保存图片到文件':
          saveImageFileToFile(context, file);
          break;
        default:
          for (var item in longPressMenuItems ?? []) {
            if (item.title == choose) {
              item.onChoose();
              break;
            }
          }
          break;
      }
    },
    child: image,
  );
}

/// Bound a decoded page to 16 megapixels / 4096 pixels wide. Tall strips keep
/// their aspect ratio; small images are never upscaled.
ui.TargetImageSize boundedPageImageSize(int width, int height) {
  final ratio = math.min(1.0,
      math.min(4096 / width, math.sqrt(16 * 1024 * 1024 / (width * height))));
  return ui.TargetImageSize(
      width: math.max(1, (width * ratio).floor()),
      height: math.max(1, (height * ratio).floor()));
}
