import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/screens/components/content_builder.dart';
import '../basic/commons.dart';
import 'components/comic_download_card.dart';
import 'components/right_click_pop.dart';
import 'downloads_exporting_screen.dart';

class DownloadsExportScreen extends StatefulWidget {
  const DownloadsExportScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportScreenState();
}

class _DownloadsExportScreenState extends State<DownloadsExportScreen> {
  late Future<List<DownloadAlbum>> _downloadsFuture;

  bool _loading = true;
  bool _openingExport = false;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _reload(rebuild: false);
  }

  void _reload({bool rebuild = true}) {
    final revision = ++_loadRevision;
    _loading = true;
    _downloadsFuture = methods.allDownloads().then((albums) {
      final available = albums.where((album) => album.dlStatus == 1).toList();
      if (mounted && revision == _loadRevision) {
        final ids = available.map((album) => album.id).toSet();
        setState(() {
          selected.retainWhere(ids.contains);
          _loading = false;
        });
      }
      return available;
    }, onError: (Object error, StackTrace stack) {
      if (mounted && revision == _loadRevision) {
        setState(() {
          selected.clear();
          _loading = false;
        });
      }
      Error.throwWithStackTrace(error, stack);
    });
    // Own errors even if the route is removed before FutureBuilder subscribes.
    _downloadsFuture.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _openExport() async {
    if (_openingExport || _loading) return;
    if (selected.isEmpty) {
      defaultToast(context, '请选择导出的内容');
      return;
    }
    setState(() {
      _openingExport = true;
    });
    final ids = selected.toList();
    try {
      if (!await androidMangeStorageRequest()) {
        if (mounted) defaultToast(context, '申请权限被拒绝');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DownloadsExportingScreen(idList: ids)));
      if (mounted) _reload();
    } catch (_) {
      if (mounted) defaultToast(context, '无法打开导出，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _openingExport = false;
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
        title: const Text("批量导出"),
        actions: [
          FutureBuilder(
            future: _downloadsFuture,
            builder: (BuildContext context,
                AsyncSnapshot<List<DownloadAlbum>> snapshot) {
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData) {
                return Container();
              }
              List<int> exportableIds = [];
              for (var value in snapshot.requireData) {
                exportableIds.add(value.id);
              }
              return _selectAllButton(exportableIds);
            },
          ),
          _goToExport(),
        ],
      ),
      body: ContentBuilder(
        key: null,
        future: _downloadsFuture,
        onRefresh: () async {
          _reload();
        },
        successBuilder: (
          BuildContext context,
          AsyncSnapshot<List<DownloadAlbum>> snapshot,
        ) {
          final downloads = snapshot.requireData;
          return ListView.builder(
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final e = downloads[index];
              return GestureDetector(
                onTap: () {
                  if (selected.contains(e.id)) {
                    selected.remove(e.id);
                  } else {
                    selected.add(e.id);
                  }
                  if (mounted) setState(() {});
                },
                child: Stack(children: [
                  ComicDownloadCard(e),
                  Row(children: [
                    Expanded(child: Container()),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        selected.contains(e.id)
                            ? Icons.check_circle_sharp
                            : Icons.circle_outlined,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  final Set<int> selected = {};

  Widget _selectAllButton(List<int> exportableIds) {
    return IconButton(
      onPressed: () async {
        if (mounted) {
          setState(() {
            if (selected.length >= exportableIds.length) {
              selected.clear();
            } else {
              selected.clear();
              selected.addAll(exportableIds);
            }
          });
        }
      },
      icon: const Icon(
        Icons.select_all,
      ),
    );
  }

  Widget _goToExport() {
    return IconButton(
      onPressed: _loading || _openingExport ? null : _openExport,
      icon: const Icon(Icons.check),
      tooltip: '确认导出',
    );
  }
}
