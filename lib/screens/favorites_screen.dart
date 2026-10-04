import 'package:jasmine/basic/ui_action.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/screens/components/comic_pager.dart';

import 'components/right_click_pop.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _folderId = 0;
  bool _isLoading = true;

  final Map<int, String> _folderMap = {
    0: "全部",
  };

  _chooseFolder() async {
    int? f = await chooseMapDialog(
      context,
      values: _folderMap.map(
          (key, value) => MapEntry(key == 0 ? value : '$value (#$key)', key)),
      title: "选择文件夹",
    );
    if (f != null) {
      if (mounted) {
        setState(() {
          _folderId = f;
        });
      }
    }
  }

  final _sortNameMap = {
    "mr": "收藏时间",
    "mp": "更新时间",
  };
  String _sort = "mr";

  Future<void> _chooseSort() => runUiAction(context, () async {
        if (_isLoading) return;
        final value = await chooseMapDialog(context,
            values: _sortNameMap.map((key, value) => MapEntry(value, key)),
            title: '选择排序');
        if (value == null || !mounted) return;
        await methods.saveProperty('favorites_sort', value);
        if (mounted) setState(() => _sort = value);
      });

  @override
  void initState() {
    for (var value in favData) {
      try {
        _folderMap[value.fid] = value.name;
      } catch (e) {
        debugPrient(e);
        defaultToast(context, "$e");
      }
    }
    _loadSort();
    super.initState();
  }

  Future<void> _loadSort() async {
    try {
      final sort = await methods.loadProperty("favorites_sort");
      if (sort.isNotEmpty && _sortNameMap.containsKey(sort)) {
        if (mounted) {
          setState(() {
            _sort = sort;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // 使用默认值
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("收藏夹"),
        actions: [
          MaterialButton(
            onPressed: _isLoading ? null : _chooseSort,
            child: Row(
              children: [
                const Icon(Icons.sort, size: 15),
                Container(width: 8),
                Text(_sortNameMap[_sort] ?? ""),
              ],
            ),
          ),
          MaterialButton(
            onPressed: _chooseFolder,
            child: Row(
              children: [
                const Icon(Icons.folder_copy_outlined, size: 15),
                Container(width: 8),
                Text(_folderMap[_folderId] ?? ""),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ComicPager(
              key: Key("FAVOUR:$_folderId:$_sort"),
              onPage: (int page) async {
                final revision = sessionRevision;
                final folderId = _folderId;
                final sort = _sort;
                final response = await methods.favorites(folderId, page, sort);
                if (mounted &&
                    revision == sessionRevision &&
                    _folderId == folderId &&
                    _sort == sort) {
                  setState(() {
                    favData = response.folderList;
                    _folderMap
                      ..clear()
                      ..[0] = "全部"
                      ..addEntries(response.folderList
                          .map((f) => MapEntry(f.fid, f.name)));
                  });
                }
                if (revision != sessionRevision)
                  throw StateError('登录状态已变化，请刷新');
                return InnerComicPage(
                    total: response.total, list: response.list);
              },
            ),
    );
  }
}
