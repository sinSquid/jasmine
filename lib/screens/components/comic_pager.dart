import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/screens/comic_info_screen.dart';
import 'package:jasmine/screens/components/content_builder.dart';
import 'package:jasmine/screens/components/types.dart';

import 'comic_list.dart';
import 'comic_loading.dart';
import 'content_error.dart';

class ComicPager extends StatefulWidget {
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;
  final bool smoothLoading;

  const ComicPager(
      {required this.onPage,
      this.longPressMenuItems,
      this.appendList,
      this.smoothLoading = false,
      Key? key})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicPagerState();
}

class _ComicPagerState extends State<ComicPager> {
  @override
  void initState() {
    currentPagerControllerModeEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    currentPagerControllerModeEvent.unsubscribe(_setState);
    super.dispose();
  }

  _setState(_) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (currentPagerControllerMode) {
      case PagerControllerMode.stream:
        return _StreamPager(
            onPage: widget.onPage,
            smoothLoading: widget.smoothLoading,
            longPressMenuItems: widget.longPressMenuItems,
            appendList: widget.appendList);
      case PagerControllerMode.pager:
        return _PagerPager(
            onPage: widget.onPage,
            smoothLoading: widget.smoothLoading,
            longPressMenuItems: widget.longPressMenuItems,
            appendList: widget.appendList);
    }
  }
}

class _StreamPager extends StatefulWidget {
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;
  final bool smoothLoading;

  const _StreamPager(
      {Key? key,
      required this.onPage,
      required this.smoothLoading,
      this.longPressMenuItems,
      this.appendList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _StreamPagerState();
}

class _StreamPagerState extends State<_StreamPager> {
  static const _windowItems = 1000;
  int _windowStart = 1;
  final List<int> _previousWindows = [];
  bool get _windowFull => _data.length >= _windowItems;

  void _changeWindow(int page, {bool previous = false}) {
    if (previous) {
      _previousWindows.removeLast();
    } else {
      _previousWindows.add(_windowStart);
    }
    _windowStart = page;
    _nextPage = page;
    _data.clear();
    if (_controller.hasClients) _controller.jumpTo(0);
    _join(replace: true);
  }

  int _maxPage = 1;
  int _nextPage = 1;
  int _total = 0;

  var _joining = false;
  var _joinSuccess = true;
  int _requestId = 0;

  Future _join({bool replace = false}) async {
    if (!mounted || (_joining && !replace)) return;
    final requestId = ++_requestId;
    final page = _nextPage;
    try {
      setState(() {
        _joining = true;
      });
      var response = await widget.onPage(page);
      if (!mounted || requestId != _requestId) return;
      if (page == 1) {
        if (_redirectAid(response.redirectAid, context)) {
          return;
        }
        if (response.total <= 0 || response.list.isEmpty) {
          _maxPage = 1;
        } else {
          _maxPage = (response.total / response.list.length).ceil();
        }
        _total = response.total;
      }
      if (response.list.isEmpty) _maxPage = page;
      _nextPage = page + 1;
      _data.addAll(response.list);
      setState(() {
        _joinSuccess = true;
        _joining = false;
      });
    } catch (e, st) {
      if (!mounted || requestId != _requestId) return;
      debugPrient("$e\n$st");
      setState(() {
        _joinSuccess = false;
        _joining = false;
      });
    }
  }

  final List<ComicSimple> _data = [];
  late ScrollController _controller;
  final TextEditingController _textEditController = TextEditingController();

  _jumpPage() {
    if (_total == 0) {
      return;
    }
    _textEditController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Card(
            child: TextField(
              controller: _textEditController,
              decoration: const InputDecoration(
                labelText: "请输入页数：",
              ),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'\d+')),
              ],
            ),
          ),
          actions: <Widget>[
            MaterialButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            MaterialButton(
              onPressed: () {
                Navigator.pop(context);
                var text = _textEditController.text;
                if (text.isEmpty || text.length > 7) {
                  return;
                }
                var num = int.parse(text);
                if (num == 0 || num > _maxPage) {
                  return;
                }
                _previousWindows.clear();
                _windowStart = num;
                _data.clear();
                if (_controller.hasClients) _controller.jumpTo(0);
                _nextPage = num;
                _join(replace: true);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    _controller = ScrollController();
    _join();
    super.initState();
  }

  @override
  void dispose() {
    _textEditController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_joining || _windowFull || _nextPage > _maxPage) {
      return;
    }
    if (_controller.position.pixels + 100 >
        _controller.position.maxScrollExtent) {
      _join();
    }
  }

  Widget? _buildLoadingCard() {
    if (!_joining && _windowFull && _nextPage <= _maxPage) {
      return TextButton(
          onPressed: () => _changeWindow(_nextPage),
          child: const Text('继续浏览下一段'));
    }
    if (_joining) {
      if (widget.smoothLoading) {
        return _smoothStatusCard(Icons.more_horiz, '加载中');
      }
      return Card(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: const CupertinoActivityIndicator(
                radius: 14,
              ),
            ),
            const Text('加载中'),
          ],
        ),
      );
    }
    if (!_joinSuccess) {
      if (widget.smoothLoading) {
        return _smoothStatusCard(Icons.sync_problem_rounded, '重试',
            onTap: () => _join());
      }
      return Card(
        child: InkWell(
          onTap: () {
            _join();
          },
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: const Icon(Icons.sync_problem_rounded),
              ),
              const Text('出错, 点击重试'),
            ],
          ),
        ),
      );
    }
    return null;
  }

  Widget _smoothStatusCard(IconData icon, String label, {VoidCallback? onTap}) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loadingCard = _buildLoadingCard();
    final list = ComicList(
      controller: _controller,
      onScroll: _onScroll,
      data: _data,
      appendList: loadingCard != null
          ? [loadingCard, ...(widget.appendList ?? [])]
          : widget.appendList,
      longPressMenuItems: widget.longPressMenuItems,
    );
    Widget content = list;
    if (widget.smoothLoading) {
      if (_data.isEmpty && !_joining) {
        content = _joinSuccess
            ? const Center(child: Text('暂无漫画'))
            : Center(
                child: TextButton.icon(
                  onPressed: () => _join(),
                  icon: const Icon(Icons.sync_problem_rounded),
                  label: const Text('出错, 点击重试'),
                ),
              );
      }
      content = ComicLoadingTransition(
        loading: _data.isEmpty && _joining,
        placeholder: const ComicListPlaceholder(),
        child: content,
      );
    }
    return Column(
      children: [
        _buildPagerBar(),
        if (_previousWindows.isNotEmpty)
          TextButton(
              onPressed: () =>
                  _changeWindow(_previousWindows.last, previous: true),
              child: const Text('返回上一段')),
        Expanded(
          child: content,
        ),
      ],
    );
  }

  PreferredSize _buildPagerBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(30),
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: .5,
              style: BorderStyle.solid,
              color: Colors.grey[200]!,
            ),
          ),
        ),
        child: GestureDetector(
          onTap: _jumpPage,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.smoothLoading) ...[
                  Flexible(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text("已加载 ${_nextPage - 1} / $_maxPage 页")),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text("已加载 ${_data.length} / $_total 项")),
                  ),
                ] else ...[
                  Text("已加载 ${_nextPage - 1} / $_maxPage 页"),
                  Text("已加载 ${_data.length} / $_total 项"),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PagerPager extends StatefulWidget {
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;
  final bool smoothLoading;

  const _PagerPager(
      {Key? key,
      required this.onPage,
      required this.smoothLoading,
      this.longPressMenuItems,
      this.appendList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _PagerPagerState();
}

class _PagerPagerState extends State<_PagerPager> {
  final TextEditingController _textEditController =
      TextEditingController(text: '');
  late int _currentPage = 1;
  late int _maxPage = 1;
  late final List<ComicSimple> _data = [];
  late Future _pageFuture = _load();
  late Key _pageKey = UniqueKey();
  int _requestId = 0;
  bool _loading = false;

  Future<dynamic> _load() async {
    final requestId = ++_requestId;
    final page = _currentPage;
    _loading = true;
    try {
      var response = await widget.onPage(page);
      if (!mounted || requestId != _requestId) return;
      if (page == 1 && _redirectAid(response.redirectAid, context)) return;
      setState(() {
        if (page == 1) {
          if (response.total <= 0 || response.list.isEmpty) {
            _maxPage = 1;
          } else {
            _maxPage = (response.total / response.list.length).ceil();
          }
        }
        _data.clear();
        _data.addAll(response.list);
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _replacePage(int page) {
    if (widget.smoothLoading && _loading) return;
    setState(() {
      _currentPage = page;
      _pageFuture = _load();
      // Own an early failure until FutureBuilder attaches on the next frame.
      _pageFuture.ignore();
      _pageKey = UniqueKey();
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.smoothLoading) {
      // Start the lazy initial request before building the controls so their
      // disabled state already matches the body on the first frame.
      final future = _pageFuture;
      return Scaffold(
        appBar: _buildPagerBar(),
        body: FutureBuilder(
          future: future,
          builder: (context, snapshot) {
            final waiting = snapshot.connectionState != ConnectionState.done;
            return ComicLoadingTransition(
              loading: waiting,
              placeholder: const ComicListPlaceholder(),
              child: waiting
                  ? const SizedBox.expand()
                  : snapshot.hasError
                      ? ContentError(
                          error: snapshot.error,
                          stackTrace: snapshot.stackTrace,
                          onRefresh: () async => _replacePage(_currentPage),
                        )
                      : _data.isEmpty
                          ? const Center(child: Text('暂无漫画'))
                          : ComicList(
                              key: _pageKey,
                              appendList: widget.appendList,
                              data: _data,
                              longPressMenuItems: widget.longPressMenuItems,
                            ),
            );
          },
        ),
      );
    }
    return ContentBuilder(
      key: _pageKey,
      future: _pageFuture,
      onRefresh: () async => _replacePage(_currentPage),
      successBuilder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        return Scaffold(
          appBar: _buildPagerBar(),
          body: ComicList(
            appendList: widget.appendList,
            data: _data,
            longPressMenuItems: widget.longPressMenuItems,
          ),
        );
      },
    );
  }

  PreferredSize _buildPagerBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: .5,
              style: BorderStyle.solid,
              color: Colors.grey[200]!,
            ),
          ),
        ),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: widget.smoothLoading && _loading
                    ? null
                    : () {
                        _textEditController.clear();
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              content: Card(
                                child: TextField(
                                  controller: _textEditController,
                                  decoration: const InputDecoration(
                                    labelText: "请输入页数：",
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'\d+')),
                                  ],
                                ),
                              ),
                              actions: <Widget>[
                                MaterialButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: const Text('取消'),
                                ),
                                MaterialButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    var text = _textEditController.text;
                                    if (text.isEmpty || text.length > 5) {
                                      return;
                                    }
                                    var num = int.parse(text);
                                    if (num == 0 || num > _maxPage) {
                                      return;
                                    }
                                    _replacePage(num);
                                  },
                                  child: const Text('确定'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                child: Row(
                  children: [
                    Text("第 $_currentPage / $_maxPage 页"),
                  ],
                ),
              ),
              Row(
                children: [
                  MaterialButton(
                    minWidth: 0,
                    onPressed: widget.smoothLoading && _loading
                        ? null
                        : () {
                            if (_currentPage > 1) {
                              _replacePage(_currentPage - 1);
                            }
                          },
                    child: const Text('上一页'),
                  ),
                  MaterialButton(
                    minWidth: 0,
                    onPressed: widget.smoothLoading && _loading
                        ? null
                        : () {
                            if (_currentPage < _maxPage) {
                              _replacePage(_currentPage + 1);
                            }
                          },
                    child: const Text('下一页'),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _redirectAid(int? redirectAid, BuildContext context) {
  if (redirectAid != null) {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (BuildContext context) {
      return ComicInfoScreen(redirectAid, null);
    }));
    return true;
  }
  return false;
}
