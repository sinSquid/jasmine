import 'package:jasmine/basic/ui_action.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';

import '../basic/commons.dart';
import '../configs/export_path.dart';
import 'components/content_loading.dart';
import 'components/right_click_pop.dart';

class ExportAb {
  final int id;
  final String name;

  ExportAb(this.id, this.name);
}

class DownloadsExportingScreen2 extends StatefulWidget {
  final List<int> idList;

  const DownloadsExportingScreen2({Key? key, required this.idList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportingScreen2State();
}

class _DownloadsExportingScreen2State extends State<DownloadsExportingScreen2> {
  bool exporting = false;
  bool _preparing = false;
  Future<void> _runExport(Future<dynamic> Function() action) =>
      runUiAction(context, () async {
        if (_preparing || exporting) return;
        setState(() => _preparing = true);
        try {
          await action();
        } finally {
          if (mounted) setState(() => _preparing = false);
        }
      });
  bool exported = false;
  bool exportFail = false;
  dynamic e;
  String exportMessage = "正在导出";
  bool deleteExport = false;

  @override
  void initState() {
    //registerEvent(_onMessageChange, "EXPORT");
    super.initState();
  }

  @override
  void dispose() {
    //unregisterEvent(_onMessageChange);
    super.dispose();
  }

  void _onMessageChange(event) {
    if (mounted) {
      setState(() {
        exportMessage = event;
      });
    }
  }

  Widget _body() {
    if (exporting) {
      return ContentLoading(label: exportMessage);
    }
    if (exportFail) {
      return Center(child: Text("导出失败\n$e\n($exportMessage)"));
    }
    if (exported) {
      return const Center(child: Text("导出成功"));
    }
    return ListView(
      children: [
        // Container(height: 20),
        // MaterialButton(
        //   onPressed: _preparing || exporting ? null : () => _runExport(_exportPkz),
        //   child: const Text("导出PKZ"),
        // ),
        Container(height: 20),
        displayExportPathInfo(),
        Container(height: 20),
        SwitchListTile(
          title: const Text("导出后删除原文件"),
          value: deleteExport,
          onChanged: (value) {
            if (mounted) {
              setState(() {
                deleteExport = value;
              });
            }
          },
        ),
        Container(height: 20),
        MaterialButton(
          onPressed:
              _preparing || exporting ? null : () => _runExport(_exportJpegs),
          child: const Text(
            "导出成文件夹",
            textAlign: TextAlign.center,
          ),
        ),
        Container(height: 20),
        MaterialButton(
          onPressed:
              _preparing || exporting ? null : () => _runExport(_exportPdf2),
          child: const Text(
            "导出成PDF",
            textAlign: TextAlign.center,
          ),
        ),
        Container(height: 20),
        MaterialButton(
          onPressed:
              _preparing || exporting ? null : () => _runExport(_exportEpub),
          child: const Text(
            "导出成EPUB",
            textAlign: TextAlign.center,
          ),
        ),
        Container(height: 20),
      ],
    );
  }

  Future<void> _exportJpegs() async {
    late String? path;
    try {
      path = Platform.isIOS
          ? await methods.iosGetDocumentDir()
          : await chooseFolder(context);
    } catch (e) {
      if (mounted) defaultToast(context, "$e");
      return;
    }
    debugPrient("path $path");
    if (!mounted) return;
    if (path != null) {
      try {
        if (mounted) {
          setState(() {
            exporting = true;
          });
        }
        await methods.export_jm_jpegs(
          widget.idList,
          path,
          deleteExport,
        );
        exported = true;
      } catch (err) {
        e = err;
        exportFail = true;
      } finally {
        if (mounted) {
          setState(() {
            exporting = false;
          });
        }
      }
    }
  }

  Future<void> _exportPdf2() async {
    late String? path;
    try {
      path = Platform.isIOS
          ? await methods.iosGetDocumentDir()
          : await chooseFolder(context);
    } catch (e) {
      if (mounted) defaultToast(context, "$e");
      return;
    }
    debugPrient("path $path");
    if (!mounted) return;
    if (path != null) {
      try {
        if (mounted) {
          setState(() {
            exporting = true;
          });
        }
        for (var id in widget.idList) {
          if (!mounted) return;
          await methods.export_jm_pdf2(
            id,
            path,
            deleteExport,
          );
        }
        exported = true;
      } catch (err) {
        e = err;
        exportFail = true;
      } finally {
        if (mounted) {
          setState(() {
            exporting = false;
          });
        }
      }
    }
  }

  Future<void> _exportEpub() async {
    late String? path;
    try {
      path = Platform.isIOS
          ? await methods.iosGetDocumentDir()
          : await chooseFolder(context);
    } catch (e) {
      if (mounted) defaultToast(context, "$e");
      return;
    }
    debugPrient("path $path");
    if (!mounted) return;
    if (path != null) {
      try {
        if (mounted) {
          setState(() {
            exporting = true;
          });
        }
        await methods.export_jm_epub(
          widget.idList,
          path,
          deleteExport,
        );
        exported = true;
      } catch (err) {
        e = err;
        exportFail = true;
      } finally {
        if (mounted) {
          setState(() {
            exporting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(
      child: buildScreen(context),
      context: context,
      canPop: !exporting && !_preparing,
    );
  }

  Widget buildScreen(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("批量导出(即使没有下载完)"),
        ),
        body: _body(),
      ),
      onWillPop: () async {
        if (exporting) {
          defaultToast(context, "导出中, 请稍后");
          return false;
        }
        return true;
      },
    );
  }
}
