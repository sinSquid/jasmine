import 'package:jasmine/basic/ui_action.dart';
import 'dart:async';
import '../basic/debounced_writer.dart';
import '../basic/reader_system_ui.dart';
import '../basic/reader_image_dimensions.dart';
import 'dart:io';
import 'dart:math';

import 'package:another_xlider/another_xlider.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/reader_controller_type.dart';
import 'package:jasmine/configs/drag_region_lock.dart';
import 'package:jasmine/configs/gesture_speed.dart';
import 'package:jasmine/configs/reader_direction.dart';
import 'package:jasmine/configs/reader_slider_position.dart';
import 'package:jasmine/configs/reader_type.dart';
import 'package:jasmine/configs/reader_zoom_scale.dart';
import 'package:jasmine/configs/two_page_direction.dart';
import 'package:jasmine/screens/components/content_error.dart';
import 'package:jasmine/screens/components/content_loading.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:photo_view/photo_view.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:zoomable_positioned_list/zoomable_positioned_list.dart'
    as zoomable;

import '../configs/ignore_view_log.dart';
import '../configs/no_animation.dart';
import '../configs/volume_key_control.dart';
import 'components/images.dart';
import 'components/image_preloader.dart';
import 'components/image_decode_scale.dart';
import 'components/reader_page_layout.dart';
import 'components/right_click_pop.dart';

final _readerSystemUi = ReaderSystemUi((fullscreen) {
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.manual : SystemUiMode.edgeToEdge,
      overlays: fullscreen ? [] : SystemUiOverlay.values,
    );
  }
});

class ComicReaderScreen extends StatefulWidget {
  final ComicBasic comic;
  final List<Series> series;
  final int chapterId;
  final int initRank;
  final Future<ChapterResponse> Function(int seriesId) loadChapter;
  final bool fullScreenOnInit;

  const ComicReaderScreen({
    Key? key,
    required this.comic,
    required this.series,
    required this.chapterId,
    required this.initRank,
    required this.loadChapter,
    this.fullScreenOnInit = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late ReaderType _readerType;
  late ReaderDirection _readerDirection;
  late Future<ChapterResponse> _chapterFuture;
  Future<void> _progressReady = Future.value();

  void _load() {
    setState(() {
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _chapterFuture = widget.loadChapter(widget.chapterId);
    });
  }

  @override
  void initState() {
    if (currentIgnoreVewLog()) {
      _progressReady = methods.album(widget.comic.id).then<void>((_) {},
          onError: (Object _, StackTrace __) {
        debugPrient('阅读详情加载失败');
      });
    }
    _load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return FutureBuilder(
      future: _chapterFuture,
      builder: (BuildContext context, AsyncSnapshot<ChapterResponse> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: ContentError(
              onRefresh: () async {
                setState(() {
                  _chapterFuture = widget.loadChapter(widget.chapterId);
                });
              },
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: const ContentLoading(),
          );
        }
        final chapter = snapshot.requireData;
        if (chapter.images.isEmpty) {
          return Scaffold(
              appBar: AppBar(),
              body: ContentError(
                error: StateError('章节暂无图片'),
                stackTrace: null,
                onRefresh: () async {
                  _load();
                },
              ));
        }
        final screen = Scaffold(
          backgroundColor: Colors.black,
          body: _ComicReader(
            progressReady: _progressReady,
            comicId: widget.comic.id,
            chapter: chapter,
            startIndex: widget.initRank.clamp(0, chapter.images.length - 1),
            reload: (int index, bool fullScreen) async {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return ComicReaderScreen(
                    comic: widget.comic,
                    series: widget.series,
                    chapterId: widget.chapterId,
                    initRank: index,
                    loadChapter: widget.loadChapter,
                    fullScreenOnInit: fullScreen,
                  );
                }),
              );
            },
            onChangeEp: (int id, bool fullScreen) async {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return ComicReaderScreen(
                    comic: widget.comic,
                    series: widget.series,
                    chapterId: id,
                    initRank: 0,
                    loadChapter: widget.loadChapter,
                    fullScreenOnInit: fullScreen,
                  );
                }),
              );
            },
            readerType: _readerType,
            readerDirection: _readerDirection,
            fullScreenOnInit: widget.fullScreenOnInit,
          ),
        );
        return _readerKeyboardHolder(screen);
      },
    );
  }

  Widget _readerKeyboardHolder(Widget widget) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      widget = Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _readerControllerEvent
                  .broadcast(_ReaderControllerEventArgs("UP"));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _readerControllerEvent
                  .broadcast(_ReaderControllerEventArgs("DOWN"));
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: widget,
      );
    }
    return widget;
  }
}

////////////////////////////////

// 仅支持安卓
// 监听后会拦截安卓手机音量键
// 仅最后一次监听生效
// event可能为DOWN/UP

var _volumeListenCount = 0;

void _onVolumeEvent(dynamic args) {
  _readerControllerEvent.broadcast(_ReaderControllerEventArgs("$args"));
}

EventChannel volumeButtonChannel = const EventChannel("volume_button");
StreamSubscription? volumeS;

void addVolumeListen() {
  if (!Platform.isAndroid) return;
  _volumeListenCount++;
  if (_volumeListenCount == 1) {
    volumeS = volumeButtonChannel
        .receiveBroadcastStream()
        .listen(_onVolumeEvent, onError: (Object error) {
      debugPrient('Volume event stream failed');
    });
  }
}

void delVolumeListen() {
  if (_volumeListenCount == 0) return;
  _volumeListenCount--;
  if (_volumeListenCount == 0) {
    volumeS?.cancel();
    volumeS = null;
  }
}

////////////////////////////////

Event<_ReaderControllerEventArgs> _readerControllerEvent =
    Event<_ReaderControllerEventArgs>();

class _ReaderControllerEventArgs extends EventArgs {
  final String key;

  _ReaderControllerEventArgs(this.key);
}

class _ComicReader extends StatefulWidget {
  final Future<void> progressReady;
  final int comicId;
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) reload;
  final FutureOr Function(int, bool) onChangeEp;
  final int startIndex;
  final ReaderType readerType;
  final ReaderDirection readerDirection;
  final bool fullScreenOnInit;

  const _ComicReader({
    required this.progressReady,
    required this.comicId,
    required this.chapter,
    required this.reload,
    required this.onChangeEp,
    required this.startIndex,
    required this.readerType,
    required this.readerDirection,
    required this.fullScreenOnInit,
    Key? key,
  }) : super(key: key);

  @override
  // ignore: no_logic_in_create_state
  State<StatefulWidget> createState() {
    switch (readerType) {
      case ReaderType.webtoon:
        return _ComicReaderWebToonState();
      case ReaderType.gallery:
        return _ComicReaderGalleryState();
      case ReaderType.webToonFreeZoom:
        return _ListViewReaderState();
      case ReaderType.twoPageGallery:
        return _TwoPageGalleryReaderState();
    }
  }
}

abstract class _ComicReaderState extends State<_ComicReader> {
  late final DebouncedWriter<int> _progress = DebouncedWriter<int>(
    (page) async {
      await widget.progressReady;
      await methods.updateViewLog(widget.comicId, widget.chapter.id, page);
    },
    delay: const Duration(milliseconds: 500),
    onError: (_, __) => debugPrient('阅读进度保存失败'),
  );
  final _systemUiOwner = Object();
  bool _sliderDragging = false;
  Widget _buildViewer();

  _needJumpTo(int pageIndex, bool animation);

  late bool _fullScreen;
  late int _current;
  late int _slider;
  List<int> _sortedSeriesIds = const <int>[];
  int? _nextEpId;

  void _rebuildSeriesCache() {
    if (widget.chapter.series.isEmpty) {
      _sortedSeriesIds = const <int>[];
      _nextEpId = null;
      return;
    }
    final entries = [...widget.chapter.series];
    entries.sort(
      (a, b) =>
          (int.tryParse(a.sort) ?? 0).compareTo(int.tryParse(b.sort) ?? 0),
    );
    _sortedSeriesIds = entries.map((e) => e.id).toList(growable: false);
    final index = _sortedSeriesIds.indexOf(widget.chapter.id);
    if (index >= 0 && index < _sortedSeriesIds.length - 1) {
      _nextEpId = _sortedSeriesIds[index + 1];
    } else {
      _nextEpId = null;
    }
  }

  Future _onFullScreenChange(bool fullScreen) async {
    setState(() {
      _readerSystemUi.update(_systemUiOwner, fullScreen);
      _fullScreen = fullScreen;
    });
  }

  bool _ownsVolumeListen = false;

  void _syncVolumeListening() {
    final enabled = Platform.isAndroid && currentVolumeKeyControl();
    if (enabled == _ownsVolumeListen) return;
    _ownsVolumeListen = enabled;
    if (enabled) {
      addVolumeListen();
    } else {
      delVolumeListen();
    }
  }

  void _onCurrentChange(int index) {
    if (index != _current) {
      setState(() {
        _current = index;
        _slider = index;
        _progress.add(index);
      });
    }
  }

  @override
  void initState() {
    _fullScreen = widget.fullScreenOnInit;
    _readerSystemUi.attach(_systemUiOwner, _fullScreen);
    _current = widget.readerType == ReaderType.twoPageGallery
        ? widget.startIndex ~/ 2 * 2
        : widget.startIndex;
    _slider = _current;
    _progress.add(_current);
    _readerControllerEvent.subscribe(_onPageControl);
    _syncVolumeListening();
    _rebuildSeriesCache();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ComicReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chapter, widget.chapter)) {
      _rebuildSeriesCache();
    }
  }

  @override
  void dispose() {
    unawaited(_progress.close());
    _readerControllerEvent.unsubscribe(_onPageControl);
    if (_ownsVolumeListen) delVolumeListen();
    _readerSystemUi.detach(_systemUiOwner);
    super.dispose();
  }

  void _onPageControl(_ReaderControllerEventArgs? args) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final step = widget.readerType == ReaderType.twoPageGallery ? 2 : 1;
    if (args != null) {
      var event = args.key;
      switch (event) {
        case "UP":
          if (_current > 0) {
            _needJumpTo(
                (_current - step).clamp(0, widget.chapter.images.length - 1),
                !currentNoAnimation());
          }
          break;
        case "DOWN":
          if (_current + step < widget.chapter.images.length) {
            _needJumpTo(_current + step, !currentNoAnimation());
          }
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (currentReaderControllerType) {
      // 按钮
      case ReaderControllerType.controller:
        return Stack(
          children: [
            _buildViewer(),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(_buildFullScreenControllerStackItem()),
          ],
        );
      case ReaderControllerType.touchOnce:
        return Stack(
          children: [
            _buildTouchOnceControllerAction(_buildViewer()),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(null),
          ],
        );
      case ReaderControllerType.touchDouble:
        return Stack(
          children: [
            _buildTouchDoubleControllerAction(_buildViewer()),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(null),
          ],
        );
      case ReaderControllerType.touchDoubleOnceNext:
        return Stack(
          children: [
            _buildTouchDoubleOnceNextControllerAction(_buildViewer()),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(null),
          ],
        );
      case ReaderControllerType.threeArea:
        return Stack(
          children: [
            _buildViewer(),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(_buildThreeAreaControllerAction()),
          ],
        );
    }
  }

  Widget _sliderDraggingText() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x88000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${_slider + 1} / ${widget.chapter.images.length}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenControllerStackItem() {
    if (currentReaderSliderPosition == ReaderSliderPosition.bottom &&
        !_fullScreen) {
      return Container();
    }
    if (ReaderSliderPosition.right == currentReaderSliderPosition) {
      return SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding:
                  const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
                color: Color(0x88000000),
              ),
              child: GestureDetector(
                onTap: () {
                  _onFullScreenChange(!_fullScreen);
                },
                child: Icon(
                  _fullScreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen_outlined,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SafeArea(
        child: Align(
      alignment: Alignment.bottomLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              _onFullScreenChange(!_fullScreen);
            },
            child: Icon(
              _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen_outlined,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildTouchOnceControllerAction(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _onFullScreenChange(!_fullScreen);
      },
      child: child,
    );
  }

  Widget _buildTouchDoubleControllerAction(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        _onFullScreenChange(!_fullScreen);
      },
      child: child,
    );
  }

  Widget _buildTouchDoubleOnceNextControllerAction(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _readerControllerEvent.broadcast(_ReaderControllerEventArgs("DOWN"));
      },
      onDoubleTap: () {
        _onFullScreenChange(!_fullScreen);
      },
      child: child,
    );
  }

  Widget _buildThreeAreaControllerAction() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        var up = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _readerControllerEvent
                  .broadcast(_ReaderControllerEventArgs("UP"));
            },
            child: Container(),
          ),
        );
        var down = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _readerControllerEvent
                  .broadcast(_ReaderControllerEventArgs("DOWN"));
            },
            child: Container(),
          ),
        );
        var fullScreen = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _onFullScreenChange(!_fullScreen),
            child: Container(),
          ),
        );
        late Widget child;
        switch (currentReaderDirection) {
          case ReaderDirection.topToBottom:
            child = Column(children: [
              up,
              fullScreen,
              down,
            ]);
            break;
          case ReaderDirection.leftToRight:
            child = Row(children: [
              up,
              fullScreen,
              down,
            ]);
            break;
          case ReaderDirection.rightToLeft:
            child = Row(children: [
              down,
              fullScreen,
              up,
            ]);
            break;
        }
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: child,
        );
      },
    );
  }

  Widget _buildBar(Widget? child) {
    switch (currentReaderSliderPosition) {
      case ReaderSliderPosition.bottom:
        return Column(
          children: [
            _buildAppBar(),
            Expanded(child: child ?? Container()),
            _fullScreen
                ? Container()
                : Container(
                    height: 45,
                    color: const Color(0x88000000),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(width: 15),
                        IconButton(
                          icon: const Icon(Icons.fullscreen),
                          color: Colors.white,
                          onPressed: () {
                            _onFullScreenChange(!_fullScreen);
                          },
                        ),
                        Container(width: 10),
                        Expanded(
                          child: _buildSliderBottom(),
                        ),
                        Container(width: 10),
                        IconButton(
                          icon: const Icon(Icons.skip_next_outlined),
                          color: Colors.white,
                          onPressed: _onNextAction,
                        ),
                        Container(width: 15),
                      ],
                    ),
                  ),
            _fullScreen
                ? Container()
                : Container(
                    color: const Color(0x88000000),
                    child: SafeArea(
                      top: false,
                      child: Container(),
                    ),
                  ),
          ],
        );
      case ReaderSliderPosition.right:
        return Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  ...child == null ? [] : [child],
                  _buildSliderRight(),
                ],
              ),
            ),
          ],
        );
      case ReaderSliderPosition.left:
        return Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  ...child == null ? [] : [child],
                  _buildSliderLeft(),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _buildAppBar() => _fullScreen
      ? Container()
      : AppBar(
          title: Text(widget.chapter.name),
          actions: [
            IconButton(
              onPressed: _onChooseEp,
              icon: const Icon(Icons.menu_open),
            ),
            IconButton(
              onPressed: _onMoreSetting,
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        );

  Widget _buildSliderBottom() {
    return Column(
      children: [
        Expanded(child: Container()),
        SizedBox(
          height: 25,
          child: _buildSliderWidget(Axis.horizontal),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget _buildSliderLeft() => _fullScreen
      ? Container()
      : Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 35,
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0x66000000),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.only(top: 10, bottom: 10, left: 6, right: 5),
              child: Center(
                child: _buildSliderWidget(Axis.vertical),
              ),
            ),
          ),
        );

  Widget _buildSliderRight() => _fullScreen
      ? Container()
      : Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 35,
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0x66000000),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.only(top: 10, bottom: 10, left: 5, right: 6),
              child: Center(
                child: _buildSliderWidget(Axis.vertical),
              ),
            ),
          ),
        );

  Widget _buildSliderWidget(Axis axis) {
    return FlutterSlider(
      disabled: widget.chapter.images.length <= 1,
      axis: axis,
      values: [_slider.toDouble()],
      min: 0,
      max: max(1, widget.chapter.images.length - 1).toDouble(),
      onDragging: (handlerIndex, lowerValue, upperValue) {
        setState(() {
          _slider =
              (lowerValue.toInt().clamp(0, widget.chapter.images.length - 1));
        });
      },
      onDragCompleted: (handlerIndex, lowerValue, upperValue) {
        setState(() {
          _sliderDragging = false;
        });
        _slider =
            (lowerValue.toInt().clamp(0, widget.chapter.images.length - 1));
        if (_slider != _current) {
          _needJumpTo(_slider, false);
        }
      },
      onDragStarted: (handlerIndex, lowerValue, upperValue) {
        setState(() {
          _sliderDragging = true;
        });
      },
      trackBar: FlutterSliderTrackBar(
        inactiveTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.shade300,
        ),
        activeTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      step: const FlutterSliderStep(
        step: 1,
        isPercentRange: false,
      ),
      tooltip: FlutterSliderTooltip(disabled: true),
    );
  }

  Future _onChooseEp() async {
    showMaterialModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xAA000000),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * (.45),
          child: _EpChooser(widget.chapter, widget.onChangeEp),
        );
      },
    );
  }

  //
  _onMoreSetting() async {
    await showMaterialModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xAA000000),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height / 2,
          child: _SettingPanel(),
        );
      },
    );
    if (!mounted) return;
    _syncVolumeListening();
    if (widget.readerDirection != currentReaderDirection ||
        widget.readerType != currentReaderType) {
      widget.reload(_current, _fullScreen);
    } else {
      setState(() {});
    }
  }

  //
  double _appBarHeight() {
    return Scaffold.of(context).appBarMaxHeight ?? 0;
  }

  double _bottomBarHeight() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      if (widget.readerType == ReaderType.webtoon ||
          widget.readerType == ReaderType.webToonFreeZoom) {
        if (widget.readerDirection == ReaderDirection.leftToRight ||
            widget.readerDirection == ReaderDirection.rightToLeft) {
          return 0;
        }
      }
    }
    return 45;
  }

  bool _fullscreenController() {
    switch (currentReaderControllerType) {
      case ReaderControllerType.touchOnce:
        return false;
      case ReaderControllerType.controller:
        return false;
      case ReaderControllerType.touchDouble:
        return false;
      case ReaderControllerType.touchDoubleOnceNext:
        return false;
      case ReaderControllerType.threeArea:
        return true;
    }
  }

  bool _hasNextEp() {
    return _nextEpId != null;
  }

  void _onNextAction() {
    final nextId = _nextEpId;
    if (nextId == null) {
      defaultToast(context, "已经到头了");
      return;
    }
    widget.onChangeEp(nextId, _fullScreen);
  }
}

class _EpChooser extends StatefulWidget {
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) onChangeEp;

  const _EpChooser(this.chapter, this.onChangeEp);

  @override
  State<StatefulWidget> createState() => _EpChooserState();
}

class _EpChooserState extends State<_EpChooser> {
  @override
  Widget build(BuildContext context) {
    if (widget.chapter.series.isEmpty) {
      return const Center(
        child: Text("无章节可选择", style: TextStyle(color: Colors.white)),
      );
    }

    var entries = [...widget.chapter.series];
    entries.sort(
      (a, b) =>
          (int.tryParse(a.sort) ?? 0).compareTo(int.tryParse(b.sort) ?? 0),
    );
    var widgets = [
      Container(height: 20),
      ...entries.map((e) {
        return Container(
          margin: const EdgeInsets.only(left: 15, right: 15, top: 5, bottom: 5),
          decoration: BoxDecoration(
            color:
                widget.chapter.id == e.id ? Colors.grey.withAlpha(100) : null,
            border: Border.all(
              color: const Color(0xff484c60),
              style: BorderStyle.solid,
              width: .5,
            ),
          ),
          child: MaterialButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onChangeEp(e.id, false);
            },
            textColor: Colors.white,
            child: Text(e.sort + (e.name == "" ? "" : (" - ${e.name}"))),
          ),
        );
      })
    ];
    final index = entries.map((e) => e.id).toList().indexOf(widget.chapter.id);
    return ScrollablePositionedList.builder(
      initialScrollIndex: index < 2 ? 0 : index - 2,
      itemCount: widgets.length,
      itemBuilder: (BuildContext context, int index) => widgets[index],
    );
  }
}

class _SettingPanel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<_SettingPanel> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            _bottomIcon(
              icon: Icons.crop_sharp,
              title: readerDirectionName(currentReaderDirection, context),
              onPressed: () => runUiAction(context, () async {
                await chooseReaderDirection(context);
                if (mounted) setState(() {});
              }),
            ),
            _bottomIcon(
              icon: Icons.view_day_outlined,
              title: readerTypeName(currentReaderType, context),
              onPressed: () => runUiAction(context, () async {
                await chooseReaderType(context);
                if (mounted) setState(() {});
              }),
            ),
            _bottomIcon(
              icon: Icons.control_camera_outlined,
              title: currentReaderControllerTypeName(),
              onPressed: () => runUiAction(context, () async {
                await chooseReaderControllerType(context);
                if (mounted) setState(() {});
              }),
            ),
            _bottomIcon(
              icon: Icons.straighten_sharp,
              title: currentReaderSliderPositionName,
              onPressed: () => runUiAction(context, () async {
                await chooseReaderSliderPosition(context);
                if (mounted) setState(() {});
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bottomIcon({
    required IconData icon,
    required String title,
    required void Function() onPressed,
  }) {
    return Expanded(
      child: Center(
        child: Column(
          children: [
            IconButton(
              iconSize: 55,
              icon: Column(
                children: [
                  Container(height: 3),
                  Icon(
                    icon,
                    size: 25,
                    color: Colors.white,
                  ),
                  Container(height: 3),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                  Container(height: 3),
                ],
              ),
              onPressed: onPressed,
            )
          ],
        ),
      ),
    );
  }
}

/// Warms only nearby files/headers; it does not retain decoded full-size images.
mixin _ScrollingPagePreload on _ComicReaderState {
  late final List<ValueNotifier<Size?>> _trueSizes = List.generate(
      widget.chapter.images.length,
      (index) => ValueNotifier<Size?>(readerImageDimensions.get(
          widget.chapter.id, widget.chapter.images[index])));
  late final ImagePreloader _scrollPreloader = ImagePreloader((index) async {
    final generation = readerImageDimensions.generation;
    final path = await methods.jmPageImage(
        widget.chapter.id, widget.chapter.images[index]);
    if (!mounted || _trueSizes[index].value != null) return;
    final size = await methods.imageSize(path);
    final dimensions = Size(size.w.toDouble(), size.h.toDouble());
    if (!mounted ||
        generation != readerImageDimensions.generation ||
        !isValidReaderImageSize(dimensions)) {
      return;
    }
    readerImageDimensions.put(
        widget.chapter.id, widget.chapter.images[index], dimensions,
        generation: generation);
    // The visible page may have populated this while the prefetch was running.
    _trueSizes[index].value ??= dimensions;
  }, maxPending: 7);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadNear(widget.startIndex);
    });
  }

  void _preloadNear(int first, {int? last, bool backwards = false}) {
    final end = last ?? first;
    _scrollPreloader.schedule([
      if (backwards) ...[
        for (var offset = 1; offset <= 6; offset++)
          if (first - offset >= 0) first - offset,
        if (end + 1 < widget.chapter.images.length) end + 1,
      ] else ...[
        for (var offset = 1; offset <= 6; offset++)
          if (end + offset < widget.chapter.images.length) end + offset,
        if (first > 0) first - 1,
      ],
    ]);
  }

  bool _scrollingBackwards = false;
  void _updateScrollPosition(Iterable<zoomable.ItemPosition> positions) {
    int? first, last;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0 ||
          position.itemLeadingEdge >= 1 ||
          position.index >= widget.chapter.images.length) continue;
      first = first == null ? position.index : min(first, position.index);
      last = last == null ? position.index : max(last, position.index);
    }
    if (first == null) return;
    if (first != _current) _scrollingBackwards = first < _current;
    _preloadNear(first, last: last, backwards: _scrollingBackwards);
    _onCurrentChange(first);
  }

  @override
  void dispose() {
    _scrollPreloader.dispose();
    for (final size in _trueSizes) {
      size.dispose();
    }
    super.dispose();
  }
}

class _ComicReaderWebToonState extends _ComicReaderState
    with _ScrollingPagePreload {
  var _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
  late final zoomable.ItemScrollController _itemScrollController;
  late final zoomable.ItemPositionsListener _itemPositionsListener;

  @override
  void initState() {
    _itemScrollController = zoomable.ItemScrollController();
    _itemPositionsListener = zoomable.ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onListCurrentChange);
    super.initState();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onListCurrentChange);
    super.dispose();
  }

  void _onListCurrentChange() =>
      _updateScrollPosition(_itemPositionsListener.itemPositions.value);

  @override
  void _needJumpTo(int index, bool animation) {
    if (animation) {
      if (DateTime.now().millisecondsSinceEpoch < _controllerTime) {
        return;
      }
      _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
      _itemScrollController.scrollTo(
        index: index, // 减1 当前position 再减少1 前一个
        duration: const Duration(milliseconds: 400),
      );
    } else {
      _itemScrollController.jumpTo(
        index: index,
      );
    }
  }

  @override
  Widget _buildViewer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: _buildList(),
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Widget buildPage(int index) => ValueListenableBuilder<Size?>(
            key: ValueKey(
                '${widget.chapter.id}:${widget.chapter.images[index]}:$index'),
            valueListenable: _trueSizes[index],
            builder: (context, trueSize, _) {
              final renderSize = readerPageRenderSize(
                constraints: constraints,
                scrollDirection:
                    widget.readerDirection == ReaderDirection.topToBottom
                        ? Axis.vertical
                        : Axis.horizontal,
                imageSize: trueSize,
                appBarHeight: super._appBarHeight(),
                bottomBarHeight: super._bottomBarHeight(),
                safeAreaBottom: MediaQuery.of(context).padding.bottom,
              );
              var currentIndex = index;
              onTrueSize(Size size) {
                if (!mounted ||
                    !size.width.isFinite ||
                    !size.height.isFinite ||
                    size.width <= 0 ||
                    size.height <= 0) return;
                // JMPageImage owns metadata caching and its generation guard.
                if (_trueSizes[currentIndex].value == size) return;
                _trueSizes[currentIndex].value = size;
              }

              return JMPageImage(
                widget.chapter.id,
                widget.chapter.images[index],
                width: renderSize.width,
                height: renderSize.height,
                onTrueSize: onTrueSize,
                knownSize: trueSize,
                decodeToDisplayWidth: true,
              );
            });

        return zoomable.ZoomablePositionedList.builder(
          enableZoom: false,
          initialScrollIndex: widget.startIndex,
          scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
              ? Axis.vertical
              : Axis.horizontal,
          reverse: widget.readerDirection == ReaderDirection.rightToLeft,
          padding: EdgeInsets.only(
            // 不管全屏与否, 滚动方向如何, 顶部永远保持间距
            top: super._appBarHeight(),
            bottom: widget.readerDirection == ReaderDirection.topToBottom
                ? 130 // 纵向滚动 底部永远都是130的空白
                : (super._bottomBarHeight() +
                    MediaQuery.of(context).padding.bottom)
            // 非全屏时, 顶部去掉顶部BAR的高度, 底部去掉底部BAR的高度, 形成看似填充的效果
            ,
          ),
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          itemCount: widget.chapter.images.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (widget.chapter.images.length == index) {
              return _buildNextEp();
            }
            return buildPage(index);
          },
        );
      },
    );
  }

  Widget _buildNextEp() {
    if (super._fullscreenController()) {
      return Container();
    }
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(20),
      child: MaterialButton(
        onPressed: () {
          if (super._hasNextEp()) {
            super._onNextAction();
          } else {
            Navigator.of(context).pop();
          }
        },
        textColor: Colors.white,
        child: Container(
          padding: const EdgeInsets.only(top: 40, bottom: 40),
          child: Text(super._hasNextEp() ? '下一章' : '结束阅读'),
        ),
      ),
    );
  }
}

// Upgrade only after the gesture settles, in bounded resolution tiers.
mixin _GalleryResolution on _ComicReaderState {
  final _qualityPage = ValueNotifier<(int, double)?>(null);
  Timer? _qualityTimer;
  void _requestQuality(int page, double zoom) {
    final tier = imageDecodeScale(zoom);
    if (tier <= 1 ||
        (_qualityPage.value?.$1 == page && _qualityPage.value!.$2 >= tier)) {
      _qualityTimer?.cancel();
      return;
    }
    _qualityTimer?.cancel();
    _qualityTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _current == page) _qualityPage.value = (page, tier);
    });
  }

  void _onScaleState(PhotoViewScaleState state) {
    if (state == PhotoViewScaleState.covering ||
        state == PhotoViewScaleState.originalSize) {
      _requestQuality(_current, 2);
    } else if (state == PhotoViewScaleState.initial ||
        state == PhotoViewScaleState.zoomedOut) {
      _qualityTimer?.cancel();
    }
  }

  void _resetQuality() {
    _qualityTimer?.cancel();
    _qualityPage.value = null;
  }

  @override
  void dispose() {
    _qualityTimer?.cancel();
    _qualityPage.dispose();
    super.dispose();
  }
}

class _ComicReaderGalleryState extends _ComicReaderState
    with _GalleryResolution {
  late PageController _pageController;
  late final ImagePreloader _imagePreloader;
  final Map<int, int> _reloadKeys = {}; // 跟踪每个页面的重新加载次数

  @override
  void initState() {
    _pageController = PageController(initialPage: widget.startIndex);
    super.initState();
    _imagePreloader = ImagePreloader(_precachePage);
    _preloadJump(widget.startIndex, init: true);
  }

  Future<void> _precachePage(int index) {
    if (!mounted) return Future.value();
    // Warm the file cache only. Do not pin full decoded pages or let a
    // speculative ImageCache entry delay a subsequent visible-page request.
    return methods
        .jmPageImage(widget.chapter.id, widget.chapter.images[index])
        .then<void>((_) {});
  }

  void _reloadImage(int index) => runUiAction(context, () async {
        if (mounted) {
          await PageImageProvider.evictPage(
              widget.chapter.id, widget.chapter.images[index]);
          await methods.deleteJmPageImageCache(
            widget.chapter.id,
            widget.chapter.images[index],
          );
          debugPrient("evict ${widget.chapter.images[index]}");
          if (!mounted) {
            return;
          }
          setState(() {
            _reloadKeys[index] = (_reloadKeys[index] ?? 0) + 1;
          });
        }
      });

  Widget _buildGallery() {
    return LayoutBuilder(builder: (context, viewport) {
      return PhotoViewGallery.builder(
        scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
            ? Axis.vertical
            : Axis.horizontal,
        reverse: widget.readerDirection == ReaderDirection.rightToLeft,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) => LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return buildLoading(
                context, constraints.maxWidth, constraints.maxHeight);
          },
        ),
        pageController: _pageController,
        onPageChanged: _onGalleryPageChange,
        scaleStateChangedCallback: _onScaleState,
        itemCount: widget.chapter.images.length,
        allowImplicitScrolling: true,
        builder: (BuildContext context, int index) {
          final reloadKey = _reloadKeys[index] ?? 0;

          return PhotoViewGalleryPageOptions.customChild(
            childSize: Size(viewport.maxWidth * 2, viewport.maxHeight * 2),
            initialScale: 0.5,
            minScale: 0.5,
            maxScale: 2.5,
            disableGestures: currentReaderControllerType ==
                    ReaderControllerType.touchDouble ||
                currentReaderControllerType ==
                    ReaderControllerType.touchDoubleOnceNext,
            onScaleEnd: (context, details, value) {
              _requestQuality(index, (value.scale ?? 0.5) / 0.5);
            },
            child: ValueListenableBuilder<(int, double)?>(
              valueListenable: _qualityPage,
              builder: (context, highPage, _) => ViewportPageImage(
                  key: ValueKey(
                      'page_${widget.chapter.id}_${widget.chapter.images[index]}_$reloadKey'),
                  id: widget.chapter.id,
                  imageName: widget.chapter.images[index],
                  revision: reloadKey,
                  canvasScale: 0.5,
                  decodeScale: highPage?.$1 == index ? highPage!.$2 : 1,
                  onReload: () => _reloadImage(index)),
            ),
          );
        },
      );
    });
  }

  @override
  void dispose() {
    _imagePreloader.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget _buildViewer() {
    return Column(
      children: [
        Container(height: _fullScreen ? 0 : super._appBarHeight()),
        Expanded(
          child: Stack(
            children: [
              _buildGallery(),
              _buildNextEpController(),
            ],
          ),
        ),
        Container(height: _fullScreen ? 0 : super._bottomBarHeight()),
      ],
    );
  }

  @override
  _needJumpTo(int pageIndex, bool animation) {
    if (animation) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
      );
    } else {
      _pageController.jumpToPage(pageIndex);
    }
    _preloadJump(pageIndex);
  }

  void _onGalleryPageChange(int to) {
    _resetQuality();
    _preloadJump(to);
    super._onCurrentChange(to);
  }

  void _preloadJump(int index, {bool init = false}) {
    void schedule() {
      if (!mounted) return;
      _imagePreloader.schedule([
        if (index + 1 < widget.chapter.images.length) index + 1,
        if (index + 2 < widget.chapter.images.length) index + 2,
        if (index > 0) index - 1,
      ]);
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => schedule());
    } else {
      schedule();
    }
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController()) {
      return Container();
    }
    if (_current < widget.chapter.images.length - 1) return Container();
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              if (super._hasNextEp()) {
                super._onNextAction();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Text(super._hasNextEp() ? '下一章' : '结束阅读',
                style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _ListViewReaderState extends _ComicReaderState
    with _ScrollingPagePreload {
  var _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
  late final zoomable.ItemScrollController _itemScrollController;
  late final zoomable.ItemPositionsListener _itemPositionsListener;

  @override
  void initState() {
    _itemScrollController = zoomable.ItemScrollController();
    _itemPositionsListener = zoomable.ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onListCurrentChange);
    super.initState();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onListCurrentChange);
    super.dispose();
  }

  @override
  void _needJumpTo(int index, bool animation) {
    if (!animation || currentNoAnimation()) {
      _itemScrollController.jumpTo(index: index);
      return;
    }
    if (DateTime.now().millisecondsSinceEpoch < _controllerTime) {
      return;
    }
    _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 400),
    );
  }

  void _onListCurrentChange() =>
      _updateScrollPosition(_itemPositionsListener.itemPositions.value);

  @override
  Widget _buildViewer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: _buildList(),
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Widget buildPage(int index) => ValueListenableBuilder<Size?>(
            key: ValueKey(
                '${widget.chapter.id}:${widget.chapter.images[index]}:$index'),
            valueListenable: _trueSizes[index],
            builder: (context, trueSize, _) {
              final renderSize = readerPageRenderSize(
                constraints: constraints,
                scrollDirection:
                    widget.readerDirection == ReaderDirection.topToBottom
                        ? Axis.vertical
                        : Axis.horizontal,
                imageSize: trueSize,
                appBarHeight: super._appBarHeight(),
                bottomBarHeight: super._bottomBarHeight(),
                safeAreaBottom: MediaQuery.of(context).padding.bottom,
              );
              var currentIndex = index;
              onTrueSize(Size size) {
                if (!mounted ||
                    !size.width.isFinite ||
                    !size.height.isFinite ||
                    size.width <= 0 ||
                    size.height <= 0) return;
                // JMPageImage owns metadata caching and its generation guard.
                if (_trueSizes[currentIndex].value == size) return;
                _trueSizes[currentIndex].value = size;
              }

              return JMPageImage(
                widget.chapter.id,
                widget.chapter.images[index],
                width: renderSize.width,
                height: renderSize.height,
                onTrueSize: onTrueSize,
                knownSize: trueSize,
              );
            });

        return zoomable.ZoomablePositionedList.builder(
          gestureSpeed: currentGestureSpeed(),
          dragRegionLock: currentDragRegionLock(),
          minScale: readerZoomMinScale,
          maxScale: readerZoomMaxScale,
          doubleTapScale: readerZoomDoubleTapScale,
          doubleTapAnimationDuration: currentNoAnimation()
              ? Duration.zero
              : const Duration(milliseconds: 200),
          enableDoubleTapZoom:
              currentReaderControllerType != ReaderControllerType.touchDouble &&
                  currentReaderControllerType !=
                      ReaderControllerType.touchDoubleOnceNext,
          initialScrollIndex: widget.startIndex,
          scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
              ? Axis.vertical
              : Axis.horizontal,
          reverse: widget.readerDirection == ReaderDirection.rightToLeft,
          padding: EdgeInsets.only(
            top: super._appBarHeight(),
            bottom: widget.readerDirection == ReaderDirection.topToBottom
                ? 130
                : (super._bottomBarHeight() +
                    MediaQuery.of(context).padding.bottom),
          ),
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          itemCount: widget.chapter.images.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (widget.chapter.images.length == index) {
              return _buildNextEp();
            }
            return buildPage(index);
          },
        );
      },
    );
  }

  Widget _buildNextEp() {
    if (super._fullscreenController()) {
      return Container();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      child: MaterialButton(
        onPressed: () {
          if (super._hasNextEp()) {
            super._onNextAction();
          } else {
            Navigator.of(context).pop();
          }
        },
        textColor: Colors.white,
        child: Container(
          padding: const EdgeInsets.only(top: 40, bottom: 40),
          child: Text(super._hasNextEp() ? '下一章' : '结束阅读'),
        ),
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////

class _TwoPageGalleryReaderState extends _ComicReaderState
    with _GalleryResolution {
  late PageController _pageController;
  late final ImagePreloader _imagePreloader;
  final Map<int, int> _imageProviderKeys = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.startIndex ~/ 2);
    _imagePreloader = ImagePreloader(_precachePage);
    _preloadJump(widget.startIndex, init: true);
  }

  Future<void> _precachePage(int index) {
    if (!mounted) return Future.value();
    // Warm the file cache only. Do not pin full decoded pages or let a
    // speculative ImageCache entry delay a subsequent visible-page request.
    return methods
        .jmPageImage(widget.chapter.id, widget.chapter.images[index])
        .then<void>((_) {});
  }

  Widget _buildView() {
    return LayoutBuilder(builder: (context, viewport) {
      return PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: (widget.chapter.images.length + 1) ~/ 2,
        builder: (context, pageIndex) =>
            _buildOptions(pageIndex, viewport.biggest),
        scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
            ? Axis.vertical
            : Axis.horizontal,
        reverse: widget.readerDirection == ReaderDirection.rightToLeft,
        onPageChanged: _onGalleryPageChange,
        scaleStateChangedCallback: _onScaleState,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      );
    });
  }

  PhotoViewGalleryPageOptions _buildOptions(int pageIndex, Size viewport) {
    final index = pageIndex * 2;
    var leftIndex = index;
    var rightIndex = index + 1 < widget.chapter.images.length ? index + 1 : -1;
    if (currentTwoPageDirection == TwoPageDirection.rightToLeft) {
      final temp = leftIndex;
      leftIndex = rightIndex;
      rightIndex = temp;
    }
    return PhotoViewGalleryPageOptions.customChild(
      childSize: viewport * 2,
      initialScale: 0.5,
      minScale: 0.5,
      maxScale: 2.5,
      disableGestures:
          currentReaderControllerType == ReaderControllerType.touchDouble ||
              currentReaderControllerType ==
                  ReaderControllerType.touchDoubleOnceNext,
      onScaleEnd: (context, details, value) {
        _requestQuality(index, (value.scale ?? 0.5) / 0.5);
      },
      child: ValueListenableBuilder<(int, double)?>(
        valueListenable: _qualityPage,
        builder: (context, highPage, _) {
          Widget page(int imageIndex, Alignment alignment) => Expanded(
              child: imageIndex < 0
                  ? const SizedBox.expand()
                  : Align(
                      alignment: alignment,
                      child: ViewportPageImage(
                          key: ValueKey(
                              'page_${widget.chapter.id}_${widget.chapter.images[imageIndex]}_${_imageProviderKeys[imageIndex] ?? 0}'),
                          id: widget.chapter.id,
                          imageName: widget.chapter.images[imageIndex],
                          revision: _imageProviderKeys[imageIndex] ?? 0,
                          canvasScale: 0.5,
                          alignment: alignment,
                          decodeScale: highPage?.$1 == index ? highPage!.$2 : 1,
                          onReload: () => _reloadImage(imageIndex)),
                    ));
          return Row(children: [
            page(leftIndex, Alignment.centerRight),
            page(rightIndex, Alignment.centerLeft),
          ]);
        },
      ),
    );
  }

  void _reloadImage(int index) => runUiAction(context, () async {
        if (mounted) {
          await PageImageProvider.evictPage(
              widget.chapter.id, widget.chapter.images[index]);
          await methods.deleteJmPageImageCache(
            widget.chapter.id,
            widget.chapter.images[index],
          );
          if (!mounted) {
            return;
          }
          setState(() {
            _imageProviderKeys[index] = (_imageProviderKeys[index] ?? 0) + 1;
          });
        }
      });

  @override
  void dispose() {
    _imagePreloader.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void _needJumpTo(int index, bool animation) {
    if (currentNoAnimation() || animation == false) {
      _pageController.jumpToPage(
        index ~/ 2,
      );
    } else {
      _pageController.animateToPage(
        index ~/ 2,
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
      );
    }
    _preloadJump(index);
  }

  void _preloadJump(int index, {bool init = false}) {
    void schedule() {
      if (!mounted) return;
      final next = (index ~/ 2 + 1) * 2;
      final previous = (index ~/ 2 - 1) * 2;
      _imagePreloader.schedule([
        if (next < widget.chapter.images.length) next,
        if (next + 1 < widget.chapter.images.length) next + 1,
        if (previous >= 0) previous,
        if (previous + 1 >= 0) previous + 1,
      ]);
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => schedule());
    } else {
      schedule();
    }
  }

  @override
  Widget _buildViewer() {
    return Stack(
      children: [
        GestureDetector(
          child: _buildView(),
        ),
        _buildNextEpController(),
      ],
    );
  }

  void _onGalleryPageChange(int to) {
    _resetQuality();
    final toIndex = to * 2;
    _preloadJump(toIndex);
    // 包含一个下一章, 假设5张图片 0,1,2,3,4 length=5, 下一章=5
    if (to >= 0 && to < widget.chapter.images.length) {
      super._onCurrentChange(toIndex);
    }
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController() ||
        _current < widget.chapter.images.length - 2) {
      return Container();
    }
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              if (_hasNextEp()) {
                _onNextAction();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Text(
              _hasNextEp() ? '下一章' : '结束阅读',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////
