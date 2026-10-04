import 'package:flutter/widgets.dart';

import '../../basic/reader_image_dimensions.dart';

/// Size the reserved page and decoded page from the same cross-axis extent.
/// Unknown comic pages use a portrait 3:4 estimate until metadata is available.
Size readerPageRenderSize({
  required BoxConstraints constraints,
  required Axis scrollDirection,
  Size? imageSize,
  double appBarHeight = 0,
  double bottomBarHeight = 0,
  double safeAreaBottom = 0,
}) {
  double positive(double value) => value.isFinite && value > 0 ? value : 1;
  double inset(double value) => value.isFinite && value > 0 ? value : 0;
  final measuredRatio = isValidReaderImageSize(imageSize)
      ? imageSize!.width / imageSize.height
      : 0.75;
  final ratio =
      measuredRatio.isFinite && measuredRatio > 0 ? measuredRatio : 0.75;
  if (scrollDirection == Axis.vertical) {
    final width = positive(constraints.maxWidth);
    return Size(width, positive(width / ratio));
  }
  final height = positive(constraints.maxHeight -
      inset(appBarHeight) -
      inset(bottomBarHeight) -
      inset(safeAreaBottom));
  return Size(positive(height * ratio), height);
}
