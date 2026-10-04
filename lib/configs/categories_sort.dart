import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/screens/components/content_error.dart';

import '../basic/methods.dart';
import '../basic/commons.dart';

List<int> _categoriesSort = [];

void sortCategories(List<Categories> categories) {
  final ranks = {
    for (var i = 0; i < _categoriesSort.length; i++) _categoriesSort[i]: i
  };
  final original = {
    for (var i = 0; i < categories.length; i++) categories[i]: i
  };
  categories.sort((a, b) {
    final compared = (ranks[a.id] ?? _categoriesSort.length)
        .compareTo(ranks[b.id] ?? _categoriesSort.length);
    return compared == 0 ? original[a]!.compareTo(original[b]!) : compared;
  });
}

List<int> getCategoriesSort() => List.unmodifiable(_categoriesSort);

const _propertyName = "categoriesSort";

Future initCategoriesSort() async {
  final stored = await methods.loadProperty(_propertyName);
  try {
    final decoded = jsonDecode(stored.isEmpty ? '[]' : stored);
    _categoriesSort =
        decoded is List ? decoded.whereType<int>().toSet().toList() : [];
  } on FormatException {
    _categoriesSort = [];
  }
}

List<int> get categoriesSort => getCategoriesSort();
var categoriesSortEvent = Event();

Future<dynamic> saveCategoriesSort(List<int> categories) async {
  final next = categories.toSet().toList();
  await methods.saveProperty(_propertyName, jsonEncode(next));
  _categoriesSort = next;
  categoriesSortEvent.broadcast();
}

Widget categoriesSortSetting(BuildContext context) {
  return ListTile(
    onTap: () {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (BuildContext context) {
          return const CategoriesSortScreen();
        },
      ));
    },
    title: const Text(
      "首页分类排序",
    ),
  );
}

class CategoriesSortScreen extends StatefulWidget {
  const CategoriesSortScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CategoriesSortScreenState();
}

class _CategoriesSortScreenState extends State<CategoriesSortScreen> {
  Future<CategoriesResponse> _categoriesFuture = methods.categories();
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        key: _key,
        future: _categoriesFuture,
        builder:
            (BuildContext context, AsyncSnapshot<CategoriesResponse> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                title: const Text("分类排序"),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: const Text("分类排序"),
              ),
              body: ContentError(
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
                onRefresh: () async {
                  setState(() {
                    _categoriesFuture = methods.categories();
                    _key = UniqueKey();
                  });
                },
              ),
            );
          }
          var categories = snapshot.requireData.categories;
          return CategoriesSortPanel(categories);
        });
  }
}

class CategoriesSortPanel extends StatefulWidget {
  final List<Categories> categories;

  const CategoriesSortPanel(this.categories, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CategoriesSortPanelState();
}

class _CategoriesSortPanelState extends State<CategoriesSortPanel> {
  late final List<int> _categoriesSort;
  late final List<Categories> _categories;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ids = widget.categories.map((e) => e.id).toSet();
    _categoriesSort = getCategoriesSort().where(ids.contains).toList();
    _categories = [...widget.categories];
    sortCategories(_categories);
  }

  _switch(int value) {
    setState(() {
      if (_categoriesSort.contains(value)) {
        _categoriesSort.remove(value);
      } else {
        _categoriesSort.add(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    //
    late double blockSize;
    late double imageSize;
    late double imageRs;
    var size = MediaQuery.of(context).size;
    var min = size.width < size.height ? size.width : size.height;
    blockSize = (min ~/ 3).floorToDouble();
    imageSize = blockSize - 15;
    imageRs = imageSize / 10;
    List<Widget> wrapItems = _wrapItems(blockSize, imageRs, imageSize);
    //
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类排序'),
        actions: [
          _saveIcon(),
        ],
      ),
      body: ListView(
        children: [
          Container(height: 20),
          Wrap(
            runSpacing: 20,
            alignment: WrapAlignment.spaceAround,
            children: wrapItems,
          ),
          Container(height: 20),
        ],
      ),
    );
  }

  List<Widget> _wrapItems(
    double blockSize,
    double imageRs,
    double imageSize,
  ) {
    List<Widget> list = [];

    append(Widget widget, int id, String title, Function() onTap) {
      list.add(
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: blockSize,
            child: Column(
              children: [
                Stack(
                  children: [
                    Card(
                      elevation: .5,
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.all(Radius.circular(imageRs)),
                        child: Container(
                          color: Colors.black,
                          child: widget,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(imageRs)),
                      ),
                    ),
                    if (!_categoriesSort.contains(id))
                      Container(
                        width: imageSize,
                        height: imageSize,
                        color: Colors.black.withOpacity(.6),
                        margin: const EdgeInsets.all(4.0),
                      ),
                    if (_categoriesSort.contains(id))
                      Container(
                        width: imageSize,
                        height: imageSize,
                        color: Colors.black.withOpacity(.2),
                        margin: const EdgeInsets.all(4.0),
                      ),
                    if (_categoriesSort.contains(id))
                      Container(
                        color: Colors.black.withOpacity(.2),
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          "${_categoriesSort.indexOf(id) + 1}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                Container(height: 5),
                Center(
                  child: Text(title),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (var value in _categories) {
      var id = value.id;
      append(
        SizedBox(
          width: imageSize,
          height: imageSize,
          child: Center(
            child: Text(
              value.name.isEmpty ? '?' : value.name.characters.first,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
        ),
        value.id,
        value.name,
        () {
          setState(() {
            _switch(id);
          });
        },
      );
    }

    return list;
  }

  Widget _saveIcon() {
    return IconButton(
      onPressed: _saving
          ? null
          : () async {
              if (_saving) return;
              setState(() => _saving = true);
              try {
                await saveCategoriesSort(_categoriesSort);
                if (mounted) Navigator.of(context).pop();
              } catch (_) {
                if (mounted) defaultToast(context, '保存排序失败，请重试');
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
      icon: const Icon(Icons.save),
    );
  }
}
