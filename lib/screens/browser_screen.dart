import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/components/comic_loading.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';

import '../configs/categories_sort.dart';
import '../configs/login.dart';
import '../configs/pager_controller_mode.dart';
import 'components/browser_bottom_sheet.dart';
import 'components/actions.dart';
import 'components/comic_floating_search_bar.dart';
import 'components/content_error.dart';
import 'components/content_loading.dart';
import 'week_screen.dart';

class BrowserScreenWrapper extends StatefulWidget {
  final FloatingSearchBarController searchBarController;

  const BrowserScreenWrapper({Key? key, required this.searchBarController})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _BrowserScreenWrapperState();
}

class _BrowserScreenWrapperState extends State<BrowserScreenWrapper> {
  @override
  void initState() {
    loginEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (loginStatus) {
      case LoginStatus.loginSuccess:
        return BrowserScreen(searchBarController: widget.searchBarController);
      case LoginStatus.loginField:
        return ContentError(
          error: "请先登录",
          stackTrace: StackTrace.current,
          onRefresh: () async {},
        );
      case LoginStatus.logging:
        return const ContentLoading(
          label: "登录中",
        );
      case LoginStatus.notSet:
        return ContentError(
          error: "请先登录",
          stackTrace: StackTrace.current,
          onRefresh: () async {},
        );
    }
  }
}

class BrowserScreen extends StatefulWidget {
  final FloatingSearchBarController searchBarController;

  const BrowserScreen({Key? key, required this.searchBarController})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<CategoriesResponse> _future;
  late Key _key;
  String _slug = "";
  SortBy _sortBy = sortByDefault;
  int _categoryRequest = 0;

  Future<CategoriesResponse> _loadCategories() {
    final future = _categories();
    // A reload may fail before FutureBuilder attaches on the next frame.
    future.ignore();
    return future;
  }

  Future<CategoriesResponse> _categories() async {
    final request = ++_categoryRequest;
    final rsp = await methods.categories();
    if (mounted && request == _categoryRequest) {
      blockStore = rsp.blocks;
      sortCategories(rsp.categories);
    }
    return rsp;
  }

  @override
  void initState() {
    _future = _loadCategories();
    _key = UniqueKey();
    super.initState();
    categoriesSortEvent.subscribe(_resort);
  }

  @override
  void dispose() {
    categoriesSortEvent.unsubscribe(_resort);
    super.dispose();
  }

  _resort(_) {
    setState(() {
      _future = _loadCategories();
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("浏览"),
        actions: [
          IconButton(
            onPressed: () async {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const WeekScreen()));
            },
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(
            onPressed: () async {
              await showComicSearch(context, widget.searchBarController,
                  keywords: "");
            },
            icon: const Icon(Icons.search),
          ),
          const BrowserBottomSheetAction(),
        ],
      ),
      body: FutureBuilder<CategoriesResponse>(
        key: _key,
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<CategoriesResponse> snapshot,
        ) {
          final loading = snapshot.connectionState != ConnectionState.done;
          Widget content;
          if (loading) {
            content = const SizedBox.expand();
          } else if (snapshot.hasError) {
            content = ContentError(
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
              onRefresh: () async {
                setState(() {
                  _future = _loadCategories();
                  _key = UniqueKey();
                });
              },
            );
          } else {
            content = _buildCategories(snapshot.requireData.categories);
          }
          return ComicLoadingTransition(
            loading: loading,
            placeholder: const _BrowserPlaceholder(),
            child: content,
          );
        },
      ),
    );
  }

  Widget _buildCategories(List<Categories> categories) {
    if (categories.isEmpty) return const Center(child: Text('暂无分类'));
    if (!categories.any((category) => category.slug == _slug)) {
      _slug = categories[0].slug;
    }
    // Bind the request to this category, even if a response is delayed
    // while the user switches category or sort order.
    final slug = _slug;
    final sortBy = _sortBy;
    return Column(children: [
      SizedBox(
        height: 56,
        child: Container(
          padding: const EdgeInsets.only(top: 8),
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: Row(
            children: [
              Expanded(
                child: _MTabBar(
                  categories,
                  categories.indexWhere((category) => category.slug == _slug),
                  (index) {
                    setState(() {
                      _slug = categories[index].slug;
                    });
                  },
                ),
              ),
              buildOrderSwitch(context, _sortBy, (value) {
                setState(() {
                  _sortBy = value;
                });
              }),
            ],
          ),
        ),
      ),
      Expanded(
        child: ComicPager(
          key: Key("$_slug:$_sortBy"),
          smoothLoading: true,
          onPage: (int page) async {
            final response = await methods.comics(slug, sortBy, page);
            return InnerComicPage(
              total: response.total,
              list: response.content,
            );
          },
        ),
      ),
    ]);
  }
}

class _BrowserPlaceholder extends StatefulWidget {
  const _BrowserPlaceholder();

  @override
  State<_BrowserPlaceholder> createState() => _BrowserPlaceholderState();
}

class _BrowserPlaceholderState extends State<_BrowserPlaceholder> {
  @override
  void initState() {
    super.initState();
    currentPagerControllerModeEvent.subscribe(_refresh);
  }

  void _refresh(_) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    currentPagerControllerModeEvent.unsubscribe(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: .08);
    Widget bar() => Container(
        height: 24,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(5)));
    return Semantics(
      label: '正在加载分类',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: Column(children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(child: bar()),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(width: 36, child: bar()),
                ]),
              ),
            ),
            SizedBox(
              height: currentPagerControllerMode == PagerControllerMode.stream
                  ? 30
                  : 50,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  Expanded(child: bar()),
                  const Spacer(),
                  Expanded(child: bar()),
                ]),
              ),
            ),
            const Expanded(child: ComicListPlaceholder()),
          ]),
        ),
      ),
    );
  }
}

class _MTabBar extends StatefulWidget {
  final List<Categories> categories;
  final void Function(int index) onTab;

  final int selectedIndex;
  const _MTabBar(this.categories, this.selectedIndex, this.onTab);

  @override
  State<StatefulWidget> createState() => _MTabBarState();
}

class _MTabBarState extends State<_MTabBar> with TickerProviderStateMixin {
  late TabController _tabController = TabController(
      length: widget.categories.length,
      initialIndex: widget.selectedIndex,
      vsync: this);
  @override
  void didUpdateWidget(covariant _MTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.length != widget.categories.length) {
      _tabController.dispose();
      _tabController = TabController(
          length: widget.categories.length,
          initialIndex: widget.selectedIndex,
          vsync: this);
    } else if (_tabController.index != widget.selectedIndex) {
      _tabController.index = widget.selectedIndex;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: TabBar(
          onTap: widget.onTab,
          controller: _tabController,
          isScrollable: true,
          indicatorSize: TabBarIndicatorSize.tab,
          padding: const EdgeInsets.only(left: 10, right: 10),
          indicator: BoxDecoration(
            color: Colors.grey.shade500.withOpacity(.3),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(5),
            ),
          ),
          tabs: widget.categories
              .map((e) => Tab(
                    text: e.name,
                  ))
              .toList()),
    );
  }
}
