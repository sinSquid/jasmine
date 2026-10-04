import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/download_thread_count.dart';
import 'package:jasmine/screens/components/content_loading.dart';
import 'package:jasmine/screens/download_import_screen.dart';

import 'components/comic_download_card.dart';
import 'components/content_error.dart';
import 'components/right_click_pop.dart';
import 'download_album_screen.dart';
import 'downloads_exports_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _loading = true;
  List<DownloadAlbum> _downloads = [];

  Object? _error;
  StackTrace? _stackTrace;
  int _requestId = 0;

  Future<void> _load() async {
    if (!mounted) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final downloads = await methods.allDownloads();
      if (!mounted || requestId != _requestId) return;
      _downloads = downloads;
    } catch (e, st) {
      if (!mounted || requestId != _requestId) return;
      _error = e;
      _stackTrace = st;
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    _load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("下载"),
        actions: [
          threadCountButton(),
          exportButton(),
          importButton(),
          IconButton(
            onPressed:
                _mutating ? null : () => _mutate(methods.renewAllDownloads),
            icon: const Icon(Icons.autorenew),
          ),
        ],
      ),
      body: _body(),
    );
  }

  bool _mutating = false;

  Future<void> _mutate(Future<dynamic> Function() action) async {
    if (!mounted || _mutating) return;
    setState(() {
      _mutating = true;
    });
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) defaultToast(context, '下载操作失败，请重试');
    } finally {
      if (mounted)
        setState(() {
          _mutating = false;
        });
    }
  }

  Widget _body() {
    if (_loading && _downloads.isEmpty) {
      return const ContentLoading(label: "加载中");
    }
    // if (_loading) 可以加个浮层, 极为短暂, 性价比比较低
    if (_error != null) {
      return ContentError(
          error: _error, stackTrace: _stackTrace, onRefresh: _load);
    }
    return _listView();
  }

  Widget _listView() {
    return ListView.builder(
      itemCount: _downloads.length,
      itemBuilder: (context, index) {
        final e = _downloads[index];
        return GestureDetector(
          key: Key("DOWNLOAD:${e.id}"),
          onTap: () {
            if (e.dlStatus == 3) {
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(builder: (BuildContext context) {
                return DownloadAlbumScreen(e);
              }),
            );
          },
          onLongPress: () async {
            String? action =
                await chooseListDialog(context, values: ["删除"], title: "请选择");
            if (action != null && action == "删除") {
              await _mutate(() => methods.deleteDownload(e.id));
            }
          },
          child: ComicDownloadCard(e),
        );
      },
    );
  }

  Widget importButton() {
    return IconButton(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DownloadImportScreen(),
          ),
        );
        _load();
      },
      icon: const Icon(
        Icons.drive_folder_upload,
      ),
    );
  }

  Widget exportButton() {
    return IconButton(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DownloadsExportScreen(),
          ),
        );
        _load();
      },
      icon: const Icon(
        Icons.sim_card_download_outlined,
      ),
    );
  }

  Widget threadCountButton() {
    return MaterialButton(
      onPressed: () async {
        await chooseDownloadThread(context);
        if (mounted) setState(() {});
      },
      minWidth: 0,
      child: Text(
        "$downloadThreadCount线程",
      ),
    );
  }
}
