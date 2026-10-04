import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';

import 'comic_list.dart';

/// Uses the real comic list geometry without constructing comics or providers.
class ComicListPlaceholder extends StatefulWidget {
  const ComicListPlaceholder({Key? key, this.inScroll = false})
      : super(key: key);
  final bool inScroll;

  @override
  State<ComicListPlaceholder> createState() => _ComicListPlaceholderState();
}

class _ComicListPlaceholderState extends State<ComicListPlaceholder> {
  @override
  void initState() {
    super.initState();
    pageColumnEvent.subscribe(_settingsChanged);
    currentPagerViewModeEvent.subscribe(_settingsChanged);
    pagerCoverRateEvent.subscribe(_settingsChanged);
  }

  void _settingsChanged(_) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    pageColumnEvent.unsubscribe(_settingsChanged);
    currentPagerViewModeEvent.unsubscribe(_settingsChanged);
    pagerCoverRateEvent.unsubscribe(_settingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = MediaQuery.of(context).size;
          final width = math.max(
              1.0,
              constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : viewport.width);
          final height = math.max(
              1.0,
              constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : viewport.height);
          final mode = currentPagerViewMode;
          final columns =
              mode == PagerViewMode.info ? 1 : pagerColumnNumber.clamp(1, 10);
          final ratio =
              currentPagerCoverRate == PagerCoverRate.rate3x4 ? 3 / 4 : 1.0;
          final coverWidth = math.max(
              1.0,
              (width -
                      (mode == PagerViewMode.titleAndCover && !widget.inScroll
                          ? 20
                          : 0)) /
                  columns);
          final rowHeight = mode == PagerViewMode.info
              ? 118.0
              : coverWidth / ratio +
                  (mode == PagerViewMode.titleAndCover ? 50.0 : 0.0);
          final count =
              (((height / rowHeight).ceil() + 1) * columns).clamp(1, 40);
          return IgnorePointer(
            child: ExcludeSemantics(
              child: ComicList(
                data: const [],
                placeholderCount: count,
                inScroll: widget.inScroll,
              ),
            ),
          );
        },
      );
}

/// Keeps the content in one tree position while a static skeleton fades away.
class ComicLoadingTransition extends StatefulWidget {
  const ComicLoadingTransition({
    Key? key,
    required this.loading,
    required this.child,
    required this.placeholder,
  }) : super(key: key);

  final bool loading;
  final Widget child;
  final Widget placeholder;

  @override
  State<ComicLoadingTransition> createState() => _ComicLoadingTransitionState();
}

class _ComicLoadingTransitionState extends State<ComicLoadingTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.loading ? 0 : 1,
  )..addStatusListener(_statusChanged);
  late final CurvedAnimation _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  bool _reduceMotion = false;

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) _controller.value = widget.loading ? 0 : 1;
  }

  @override
  void didUpdateWidget(covariant ComicLoadingTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading != oldWidget.loading) {
      if (widget.loading) {
        _controller.value = 0;
      } else if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.loading ? '正在加载' : null,
        liveRegion: widget.loading,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            IgnorePointer(
              ignoring: widget.loading,
              child: ExcludeSemantics(
                excluding: widget.loading,
                child: FadeTransition(opacity: _opacity, child: widget.child),
              ),
            ),
            Positioned.fill(
              child: Visibility(
                visible: widget.loading || !_controller.isCompleted,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: FadeTransition(
                      opacity: ReverseAnimation(_opacity),
                      child: widget.placeholder,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
