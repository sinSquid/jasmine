import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/methods.dart';

import 'components/browser_bottom_sheet.dart';
import 'components/comic_pager.dart';
import 'components/right_click_pop.dart';
import 'components/types.dart';

class ViewLogScreen extends StatefulWidget {
  const ViewLogScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ViewLogScreenState();
}

class _ViewLogScreenState extends State<ViewLogScreen> {
  int _revision = 0;
  bool _mutating = false;

  Future<void> _mutate(Future<dynamic> Function() action,
      {bool confirm = false}) async {
    if (!mounted || _mutating) return;
    setState(() => _mutating = true);
    try {
      if (confirm) {
        final choice = await chooseListDialog(context,
            values: ['是', '否'], title: '清除所有历史记录?');
        if (!mounted || choice != '是') return;
      }
      await action();
      if (mounted) setState(() => _revision++);
    } catch (_) {
      if (mounted) defaultToast(context, '删除浏览记录失败，请重试');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("浏览记录"),
        actions: [
          IconButton(
            onPressed: _mutating
                ? null
                : () => _mutate(methods.clearViewLog, confirm: true),
            icon: const Icon(Icons.auto_delete),
          ),
          const BrowserBottomSheetAction(),
        ],
      ),
      body: ComicPager(
        key: ValueKey(_revision),
        onPage: (int page) async {
          final response = await methods.pageViewLog(page);
          return InnerComicPage(
            total: response.total,
            list: response.content,
          );
        },
        longPressMenuItems: [
          ComicLongPressMenuItem(
            "删除浏览记录",
            (ComicBasic comic) =>
                _mutate(() => methods.deleteViewLogByComicId(comic.id)),
          ),
        ],
      ),
    );
  }
}
