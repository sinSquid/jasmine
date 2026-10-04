import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:photo_view/photo_view.dart';

import 'components/right_click_pop.dart';
import 'components/images.dart';
import 'components/image_decode_scale.dart';
import 'components/fading_reader_image.dart';

// 预览图片
class FilePhotoViewScreen extends StatefulWidget {
  final String filePath;

  final ImageProvider? initialImageProvider;
  const FilePhotoViewScreen(this.filePath,
      {Key? key, this.initialImageProvider})
      : super(key: key);

  @override
  State<FilePhotoViewScreen> createState() => _FilePhotoViewScreenState();
}

class _FilePhotoViewScreenState extends State<FilePhotoViewScreen> {
  double _decodeScale = 1;
  int _revision = 0;
  Timer? _qualityTimer;
  String get filePath => widget.filePath;

  void _upgrade(double zoom) {
    final tier = imageDecodeScale(zoom);
    if (tier <= _decodeScale) {
      _qualityTimer?.cancel();
      return;
    }
    _qualityTimer?.cancel();
    final path = filePath;
    _qualityTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted && filePath == path) setState(() => _decodeScale = tier);
    });
  }

  @override
  void didUpdateWidget(covariant FilePhotoViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != filePath) {
      _qualityTimer?.cancel();
      _decodeScale = 1;
      _revision = 0;
    }
  }

  @override
  void dispose() {
    _qualityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            GestureDetector(
              onLongPress: () async {
                String? choose = await chooseListDialog(
                  context,
                  title: '请选择',
                  values: [
                    ...Platform.isAndroid || Platform.isIOS
                        ? [
                            '保存图片到相册',
                          ]
                        : [],
                    '保存图片到文件',
                  ],
                );
                switch (choose) {
                  case '保存图片到相册':
                    saveImageFileToGallery(context, filePath);
                    break;
                  case '保存图片到文件':
                    saveImageFileToFile(context, filePath);
                    break;
                }
              },
              child: LayoutBuilder(builder: (context, constraints) {
                final ratio =
                    MediaQuery.devicePixelRatioOf(context) * _decodeScale;
                return PhotoView.customChild(
                  key: ValueKey(filePath),
                  // Stable geometry across decode changes; originalSize gives
                  // double-tap a real 2x zoom even though this is a custom child.
                  childSize:
                      Size(constraints.maxWidth * 2, constraints.maxHeight * 2),
                  minScale: 0.5,
                  initialScale: 0.5,
                  maxScale: 2.5,
                  scaleStateChangedCallback: (state) {
                    if (state == PhotoViewScaleState.covering ||
                        state == PhotoViewScaleState.originalSize) {
                      _upgrade(2);
                    } else if (state == PhotoViewScaleState.initial ||
                        state == PhotoViewScaleState.zoomedOut) {
                      _qualityTimer?.cancel();
                    }
                  },
                  onScaleEnd: (context, details, value) {
                    _upgrade((value.scale ?? 0.5) / 0.5);
                  },
                  child: SizedBox.expand(
                      child: FadingReaderImage(
                    identity: (filePath, _revision),
                    statusScale: 2,
                    initialImageProvider:
                        _revision == 0 ? widget.initialImageProvider : null,
                    image: BoundedFileImage(filePath,
                        targetWidth:
                            viewportImagePixels(constraints.maxWidth, ratio),
                        targetHeight: viewportImagePixels(
                            constraints.maxHeight, ratio,
                            maxDimension: 16384)),
                    onReload: () async {
                      final path = filePath;
                      await BoundedFileImage(path,
                              targetWidth: viewportImagePixels(
                                  constraints.maxWidth, ratio),
                              targetHeight: viewportImagePixels(
                                  constraints.maxHeight, ratio,
                                  maxDimension: 16384))
                          .evict();
                      if (mounted && path == filePath) {
                        setState(() => _revision++);
                      }
                    },
                  )),
                );
              }),
            ),
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.only(top: 80),
                padding: const EdgeInsets.only(left: 4, right: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.75),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Icon(Icons.keyboard_backspace, color: Colors.white),
              ),
            ),
          ],
        ),
      );
}
