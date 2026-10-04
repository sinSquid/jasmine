import 'package:flutter/material.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/comic_info_screen.dart';
import 'package:jasmine/screens/components/types.dart';

import '../../basic/commons.dart';
import 'comic_info_card.dart';
import 'images.dart';
import 'fading_reader_image.dart';
import 'dart:math' as math;

class ComicList extends StatefulWidget {
  final bool inScroll;
  final List<ComicBasic> data;
  final int placeholderCount;
  final List<Widget>? appendList;
  final ScrollController? controller;
  final Function? onScroll;
  final List<ComicLongPressMenuItem>? longPressMenuItems;

  const ComicList({
    Key? key,
    required this.data,
    this.placeholderCount = 0,
    this.appendList,
    this.controller,
    this.inScroll = false,
    this.onScroll,
    this.longPressMenuItems,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicListState();
}

class _ComicListState extends State<ComicList> {
  int get _placeholderCount => widget.placeholderCount.clamp(0, 40);
  int get _itemCount =>
      widget.data.length + _placeholderCount + (widget.appendList?.length ?? 0);
  int get _columns => pagerColumnNumber.clamp(1, 10);

  Widget _afterData(int index, Widget Function() placeholder) {
    final offset = index - widget.data.length;
    if (offset < _placeholderCount) {
      return IgnorePointer(child: ExcludeSemantics(child: placeholder()));
    }
    return widget.appendList![offset - _placeholderCount];
  }

  Widget _placeholderCover({bool title = false}) => Card(
        shape: coverShape,
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const ReaderImagePlaceholder(),
              if (title)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: math.min(40, constraints.maxHeight),
                    color: Colors.black.withAlpha(180),
                    padding: const EdgeInsets.all(3),
                    child: const _ComicPlaceholderText(light: true),
                  ),
                ),
            ],
          );
        }),
      );

  Widget _placeholderInfo() => Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            SizedBox(width: 83, height: 108, child: _placeholderCover()),
            const SizedBox(width: 10),
            const Expanded(
              child:
                  SizedBox(height: 64, child: _ComicPlaceholderText(lines: 3)),
            ),
          ],
        ),
      );

  Widget _placeholderTitleAndCover(double width, double height) => Column(
        children: [
          SizedBox(width: width, height: height, child: _placeholderCover()),
          SizedBox(
            width: width,
            height: 50,
            child: const Padding(
              padding: EdgeInsets.only(left: 5, right: 5, bottom: 10),
              child: _ComicPlaceholderText(),
            ),
          ),
        ],
      );

  bool _isSealed(ComicBasic comic) {
    return comic is ComicSimple && comic.sealed;
  }

  Widget _buildSealedCoverPlaceholder({required BoxConstraints constraints}) {
    return Container(
      color: Colors.black12,
      child: Center(
        child: Icon(
          Icons.visibility_off_outlined,
          color: Colors.grey.shade600,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildCoverByRate({
    required ComicBasic comic,
    required BoxConstraints constraints,
    required int index,
  }) {
    if (_isSealed(comic)) {
      return _buildSealedCoverPlaceholder(constraints: constraints);
    }
    switch (currentPagerCoverRate) {
      case PagerCoverRate.rate3x4:
        return JM3x4Cover(
          comicId: comic.id,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          longPressMenuItems: _longPressImageCallback(index),
        );
      case PagerCoverRate.rateSquare:
        return JMSquareCover(
          comicId: comic.id,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          longPressMenuItems: _longPressImageCallback(index),
        );
    }
  }

  Widget _buildInfoCard(ComicBasic comic) {
    if (_isSealed(comic)) {
      return Container(
        padding: const EdgeInsets.only(top: 5, bottom: 5, left: 10, right: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 100 * 3 / 4,
              height: 100,
              child: Card(
                shape: coverShape,
                clipBehavior: Clip.antiAlias,
                child: _buildSealedCoverPlaceholder(
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
            Container(width: 10),
            Expanded(
              child: Text(
                comic.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    return ComicInfoCard(comic);
  }

  @override
  void initState() {
    currentPagerViewModeEvent.subscribe(_setState);
    pageColumnEvent.subscribe(_setState);
    pagerCoverRateEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    currentPagerViewModeEvent.unsubscribe(_setState);
    pageColumnEvent.unsubscribe(_setState);
    pagerCoverRateEvent.unsubscribe(_setState);
    super.dispose();
  }

  _setState(_) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (currentPagerViewMode) {
      case PagerViewMode.cover:
        return _buildCoverMode();
      case PagerViewMode.info:
        return _buildInfoMode();
      case PagerViewMode.titleInCover:
        return _buildTitleInCoverMode();
      case PagerViewMode.titleAndCover:
        return _buildTitleAndCoverMode();
    }
  }

  Widget _buildCoverMode() {
    Widget itemAt(int i) {
      if (i >= widget.data.length) {
        return _afterData(i, _placeholderCover);
      }
      final sealed = _isSealed(widget.data[i]);
      return GestureDetector(
        onTap: sealed
            ? null
            : () {
                _pushToComicInfo(widget.data[i]);
              },
        onLongPress: sealed ? null : _longPressCallback(i),
        child: Card(
          shape: coverShape,
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return _buildCoverByRate(
                comic: widget.data[i],
                constraints: constraints,
                index: i,
              );
            },
          ),
        ),
      );
    }

    final itemCount = _itemCount;
    late final double childAspectRatio;
    switch (currentPagerCoverRate) {
      case PagerCoverRate.rate3x4:
        childAspectRatio = 3 / 4;
        break;
      case PagerCoverRate.rateSquare:
        childAspectRatio = 1;
        break;
    }
    if (widget.inScroll) {
      return LayoutBuilder(builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final columnWidth = availableWidth / _columns;
        return Wrap(
          alignment: WrapAlignment.spaceAround,
          crossAxisAlignment: WrapCrossAlignment.center,
          runAlignment: WrapAlignment.spaceBetween,
          children: List.generate(itemCount, itemAt)
              .map((e) => SizedBox(
                    width: columnWidth,
                    height: columnWidth / childAspectRatio,
                    child: e,
                  ))
              .toList(),
        );
      });
    }
    final view = GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: childAspectRatio,
      ),
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) => itemAt(index),
    );
    return NotificationListener<ScrollNotification>(
      child: view,
      onNotification: (scrollNotification) {
        if (scrollNotification.depth == 0) widget.onScroll?.call();
        return false;
      },
    );
  }

  Widget _buildInfoMode() {
    Widget itemAt(int i) {
      if (i >= widget.data.length) {
        return _afterData(i, _placeholderInfo);
      }
      final sealed = _isSealed(widget.data[i]);
      return GestureDetector(
        onTap: sealed
            ? null
            : () {
                _pushToComicInfo(widget.data[i]);
              },
        onLongPress: sealed ? null : _longPressCallback(i),
        child: _buildInfoCard(widget.data[i]),
      );
    }

    final itemCount = _itemCount;
    if (widget.inScroll) {
      return Column(children: List.generate(itemCount, itemAt));
    }
    final view = ListView.builder(
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      itemCount: itemCount,
      itemBuilder: (context, index) => itemAt(index),
    );
    return NotificationListener<ScrollNotification>(
      child: view,
      onNotification: (scrollNotification) {
        if (scrollNotification.depth == 0) widget.onScroll?.call();
        return false;
      },
    );
  }

  Widget _buildTitleInCoverMode() {
    Widget itemAt(int i) {
      if (i >= widget.data.length) {
        return _afterData(i, () => _placeholderCover(title: true));
      }
      final sealed = _isSealed(widget.data[i]);
      return GestureDetector(
        onTap: sealed
            ? null
            : () {
                _pushToComicInfo(widget.data[i]);
              },
        child: Card(
          shape: coverShape,
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final image = _buildCoverByRate(
                comic: widget.data[i],
                constraints: constraints,
                index: i,
              );
              return Stack(
                children: [
                  image,
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      color: Colors.black.withAlpha(180),
                      width: constraints.maxWidth,
                      child: Text(
                        "${widget.data[i].name}\n",
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.3,
                        ),
                        strutStyle: const StrutStyle(
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    final itemCount = _itemCount;
    late final double childAspectRatio;
    switch (currentPagerCoverRate) {
      case PagerCoverRate.rate3x4:
        childAspectRatio = 3 / 4;
        break;
      case PagerCoverRate.rateSquare:
        childAspectRatio = 1;
        break;
    }
    if (widget.inScroll) {
      return LayoutBuilder(builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final columnWidth = availableWidth / _columns;
        return Wrap(
          alignment: WrapAlignment.spaceAround,
          crossAxisAlignment: WrapCrossAlignment.center,
          runAlignment: WrapAlignment.spaceBetween,
          children: List.generate(itemCount, itemAt)
              .map((e) => SizedBox(
                    width: columnWidth,
                    height: columnWidth / childAspectRatio,
                    child: e,
                  ))
              .toList(),
        );
      });
    }
    final view = GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: childAspectRatio,
      ),
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) => itemAt(index),
    );
    return NotificationListener<ScrollNotification>(
      child: view,
      onNotification: (scrollNotification) {
        if (scrollNotification.depth == 0) widget.onScroll?.call();
        return false;
      },
    );
  }

  Widget _buildTitleAndCoverMode() {
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final width = math.max(
          1.0, (availableWidth - (widget.inScroll ? 0 : 20)) / _columns);
      late final double height;
      switch (currentPagerCoverRate) {
        case PagerCoverRate.rate3x4:
          height = width * 4 / 3;
          break;
        case PagerCoverRate.rateSquare:
          height = width;
          break;
      }
      Widget itemAt(int i) {
        if (i >= widget.data.length) {
          return _afterData(i, () => _placeholderTitleAndCover(width, height));
        }
        final sealed = _isSealed(widget.data[i]);
        return GestureDetector(
          onTap: sealed
              ? null
              : () {
                  _pushToComicInfo(widget.data[i]);
                },
          onLongPress: sealed ? null : _longPressCallback(i),
          child: Column(
            children: [
              SizedBox(
                width: width,
                height: height,
                child: Card(
                  shape: coverShape,
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      return _buildCoverByRate(
                        comic: widget.data[i],
                        constraints: constraints,
                        index: i,
                      );
                    },
                  ),
                ),
              ),
              Container(
                width: width,
                height: 50,
                padding: const EdgeInsets.only(left: 5, right: 5, bottom: 10),
                child: Text(
                  "${widget.data[i].name}\n",
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    height: 1.3,
                  ),
                  strutStyle: const StrutStyle(
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      final itemCount = _itemCount;
      if (widget.inScroll) {
        return Wrap(
          alignment: WrapAlignment.spaceAround,
          crossAxisAlignment: WrapCrossAlignment.center,
          runAlignment: WrapAlignment.spaceBetween,
          children: List.generate(itemCount, itemAt),
        );
      }
      final view = GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          childAspectRatio: width / (height + 50),
        ),
        controller: widget.controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10.0),
        itemCount: itemCount,
        itemBuilder: (context, index) => itemAt(index),
      );
      return NotificationListener<ScrollNotification>(
        child: view,
        onNotification: (scrollNotification) {
          if (scrollNotification.depth == 0) widget.onScroll?.call();
          return false;
        },
      );
    });
  }

  void _pushToComicInfo(ComicBasic data) {
    Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) {
      return ComicInfoScreen(data.id, data);
    }));
  }

  GestureLongPressCallback? _longPressCallback(int index) {
    if (widget.longPressMenuItems != null &&
        widget.longPressMenuItems!.isNotEmpty) {
      final comic = widget.data[index];
      return () {
        showMenu(
          context: context,
          position: const RelativeRect.fromLTRB(0, 0, 0, 0),
          items: widget.longPressMenuItems!
              .map((e) => PopupMenuItem(
                    child: Text(e.title),
                    value: e,
                  ))
              .toList(),
        ).then((value) {
          if (mounted && value != null) {
            value.onChoose.call(comic);
          }
        });
      };
    }
    return null;
  }

  List<LongPressMenuItem>? _longPressImageCallback(int index) {
    if (widget.longPressMenuItems != null &&
        widget.longPressMenuItems!.isNotEmpty) {
      final comic = widget.data[index];
      return widget.longPressMenuItems!
          .map((e) => LongPressMenuItem(e.title, () {
                if (mounted) e.onChoose(comic);
              }))
          .toList();
    }
    return null;
  }
}

/// Paints bounded gray lines without text layout or a repeating animation.
class _ComicPlaceholderText extends StatelessWidget {
  const _ComicPlaceholderText({this.lines = 2, this.light = false});
  final int lines;
  final bool light;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ComicPlaceholderTextPainter(
          light
              ? Colors.white.withValues(alpha: 0.32)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          lines,
        ),
        child: const SizedBox.expand(),
      );
}

class _ComicPlaceholderTextPainter extends CustomPainter {
  const _ComicPlaceholderTextPainter(this.color, this.lines);
  final Color color;
  final int lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final spacing = size.height / (lines + 1);
    final height = math.min(8.0, spacing * 0.5);
    for (var i = 0; i < lines; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, spacing * (i + 1) - height / 2,
              size.width * (i == 0 ? 0.86 : 0.62), height),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ComicPlaceholderTextPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.lines != lines;
}
