import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';

import '../../basic/commons.dart';
import 'floating_search_bar.dart';

final _event = Event();
final List<Block> _blockStore = [];
final List<SearchHistory> _histories = [];
int _historyRevision = 0;
bool _deletingHistory = false;
Future<List<SearchHistory>>? _historyRequest;

Future<void> showComicSearch(
    BuildContext context, FloatingSearchBarController controller,
    {required String keywords}) async {
  // History is optional: opening search must not wait for a native request.
  controller.display(modifyInput: keywords);
  final revision = _historyRevision;
  final request = _historyRequest ??= methods.lastSearchHistories(20);
  try {
    final values = await request;
    if (context.mounted && revision == _historyRevision) {
      searchHistories = values;
    }
  } catch (_) {
    if (context.mounted) defaultToast(context, '搜索历史加载失败，仍可搜索');
  } finally {
    if (identical(_historyRequest, request)) _historyRequest = null;
  }
}

set blockStore(List<Block> values) {
  _blockStore.clear();
  _blockStore.addAll(values);
  _event.broadcast();
}

set searchHistories(List<SearchHistory> values) {
  _historyRevision++;
  _histories.clear();
  _histories.addAll(values);
  _event.broadcast();
}

class ComicFloatingSearchBarScreen extends StatefulWidget {
  final FloatingSearchBarController controller;
  final Widget child;
  final ValueChanged<String>? onQuery;

  const ComicFloatingSearchBarScreen({
    Key? key,
    required this.controller,
    required this.child,
    this.onQuery,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicFloatingSearchBarScreenState();
}

class _ComicFloatingSearchBarScreenState
    extends State<ComicFloatingSearchBarScreen> {
  final _panelController = ScrollController();

  @override
  void initState() {
    _event.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    _event.unsubscribe(_setState);
    _panelController.dispose();
    super.dispose();
  }

  void _setState(_) {
    if (mounted) setState(() {});
  }

  Future<void> _deleteHistory([SearchHistory? entry]) async {
    if (_deletingHistory) return;
    _deletingHistory = true;
    _event.broadcast();
    try {
      final choice = await chooseListDialog(context,
          values: ['是', '否'],
          title: entry == null ? '清除所有历史记录?' : '清除历史记录"${entry.searchQuery}"?');
      if (!mounted || choice != '是') return;
      if (entry == null) {
        await methods.clearAllSearchLog();
        searchHistories = [];
      } else {
        await methods.clearASearchLog(entry.searchQuery);
        searchHistories = _histories
            .where((value) => value.searchQuery != entry.searchQuery)
            .toList();
      }
    } catch (_) {
      if (mounted) defaultToast(context, '删除搜索历史失败，请重试');
    } finally {
      _deletingHistory = false;
      _event.broadcast();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingSearchBarScreen(
      controller: widget.controller,
      child: widget.child,
      onSubmitted: _onSubmitted,
      panel: _buildPanel(),
    );
  }

  void _onSubmitted(String value) {
    widget.controller.hide();
    if (value.isNotEmpty && widget.onQuery != null) {
      widget.onQuery!(value);
    }
  }

  Widget _buildPanel() {
    return ListView(
      controller: _panelController,
      padding: const EdgeInsets.all(10),
      children: [
        ..._buildHistory(),
        ..._buildTags(),
      ],
    );
  }

  List<Widget> _buildHistory() {
    if (_histories.isEmpty) {
      return [];
    }
    final List<Widget> widgets = [];
    widgets.add(_buildTitle("历史记录", clear: () => _deleteHistory()));
    widgets.add(Wrap(
      children: _histories.map((e) {
        return InkWell(
          onTap: () {
            _onSubmitted(e.searchQuery);
          },
          onLongPress: () => _deleteHistory(e),
          child: Container(
            padding: const EdgeInsets.only(
              left: 10,
              right: 10,
              top: 3,
              bottom: 3,
            ),
            margin: const EdgeInsets.only(
              left: 5,
              right: 5,
              top: 3,
              bottom: 3,
            ),
            decoration: BoxDecoration(
              color: Colors.pink.shade100,
              border: Border.all(
                style: BorderStyle.solid,
                color: Colors.pink.shade400,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(30)),
            ),
            child: Text(
              e.searchQuery,
              style: TextStyle(
                color: Colors.pink.shade500,
                height: 1.4,
              ),
              strutStyle: const StrutStyle(
                height: 1.4,
              ),
            ),
          ),
        );
      }).toList(),
    ));
    return widgets;
  }

  List<Widget> _buildTags() {
    final List<Widget> widgets = [];
    widgets.add(_buildTitle("板块"));
    for (final block in _blockStore) {
      widgets.add(_buildSubTitle(block.title));
      widgets.add(Wrap(
        children: block.content.map((e) {
          return InkWell(
            onTap: () {
              _onSubmitted(e);
            },
            child: Container(
              padding: const EdgeInsets.only(
                left: 10,
                right: 10,
                top: 3,
                bottom: 3,
              ),
              margin: const EdgeInsets.only(
                left: 5,
                right: 5,
                top: 3,
                bottom: 3,
              ),
              decoration: BoxDecoration(
                color: Colors.pink.shade100,
                border: Border.all(
                  style: BorderStyle.solid,
                  color: Colors.pink.shade400,
                ),
                borderRadius: const BorderRadius.all(Radius.circular(30)),
              ),
              child: Text(
                e,
                style: TextStyle(
                  color: Colors.pink.shade500,
                  height: 1.4,
                ),
                strutStyle: const StrutStyle(
                  height: 1.4,
                ),
              ),
            ),
          );
        }).toList(),
      ));
    }
    return widgets;
  }

  Widget _buildTitle(String title, {void Function()? clear}) {
    if (clear != null) {
      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 5),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(child: Container()),
            IconButton(
              onPressed: _deletingHistory ? null : clear,
              icon: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubTitle(String title) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        title,
      ),
    );
  }
}
