import 'package:jasmine/basic/ui_action.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';

import '../basic/commons.dart';
import '../configs/export_path.dart';
import '../configs/export_rename.dart';
import 'components/content_loading.dart';
import 'components/right_click_pop.dart';

class ExportAb {
  final int id;
  final String name;

  ExportAb(this.id, this.name);
}

class DownloadsExportingScreen extends StatefulWidget {
  final List<int> idList;

  const DownloadsExportingScreen({Key? key, required this.idList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportingScreenState();
}

class _DownloadsExportingScreenState extends State<DownloadsExportingScreen> {
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
  var deleteExport = false;

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
          title: const Text("导出后删除下载的漫画"),
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
        _buildButtonInner(
          _exportJmis,
          "分别导出JMI",
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportZips,
          "分别导出JM.ZIP",
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportJpegZips,
          "分别导出JPEGS.ZIP",
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportCbzsZips,
          "分别导出CBZ",
        ),
        Container(height: 20),
        if (true) ...[
          _buildButtonInner(
            _exportPdf,
            "分别导Pdf",
          ),
          Container(height: 20),
        ],
        Container(height: 20),
        _buildButtonInner(
          _exportEpubs,
          "分别导出EPUB",
        ),
        Container(height: 20),
      ],
    );
  }

  Widget _buildButtonInner(Future<dynamic> Function()? onPressed, String text) {
    return MaterialButton(
      onPressed: _preparing || exporting || onPressed == null
          ? null
          : () => _runExport(onPressed),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Container(
            width: constraints.maxWidth,
            padding: const EdgeInsets.all(15),
            color:
                (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black)
                    .withOpacity(.05),
            child: Text(
              text,
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportJmis() async {
    if (Platform.isMacOS) {
      if (!await chooseEx(context)) return;
    }
    if (!mounted) return;
    if (!await confirmDialog(
        context, "导出确认", "将您所选的漫画分别导出JMI${showExportPath()}")) {
      return;
    }
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          exporting = true;
        });
      }
      final path = await attachExportPath();
      for (var value in widget.idList) {
        if (!mounted) return;
        var ab = await methods.downloadById(value);
        if (mounted) {
          setState(() {
            exportMessage = "正在导出 : " + (ab?.album?.name ?? "");
          });
        }
        String? rename;
        if (!mounted) return;
        if (currentExportRename()) {
          rename = await displayTextInputDialog(context,
              title: "导出重命名", src: ab?.album?.name ?? "");
          if (rename == null || !mounted) return;
        }
        await methods.export_jm_jmi_single(
          value,
          path,
          rename,
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

  Future<void> _exportPdf() async {
    if (Platform.isMacOS) {
      if (!await chooseEx(context)) return;
    }
    if (!mounted) return;
    if (!await confirmDialog(
        context, "导出确认", "将您所选的漫画分别导出PDF${showExportPath()}")) {
      return;
    }
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          exporting = true;
        });
      }
      final path = await attachExportPath();
      for (var value in widget.idList) {
        if (!mounted) return;
        var ab = await methods.downloadById(value);
        if (mounted) {
          setState(() {
            exportMessage = "正在导出 : " + (ab?.album?.name ?? "");
          });
        }
        await methods.export_jm_pdf(
          value,
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

  Future<void> _exportCbzsZips() async {
    if (Platform.isMacOS) {
      if (!await chooseEx(context)) return;
    }
    if (!mounted) return;
    if (!await confirmDialog(
        context, "导出确认", "将您所选的漫画分别导出cbzs.zip${showExportPath()}")) {
      return;
    }
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          exporting = true;
        });
      }
      final path = await attachExportPath();
      for (var value in widget.idList) {
        if (!mounted) return;
        var ab = await methods.downloadById(value);
        if (mounted) {
          setState(() {
            exportMessage = "正在导出 : " + (ab?.album?.name ?? "");
          });
        }
        String? rename;
        if (!mounted) return;
        if (currentExportRename()) {
          rename = await displayTextInputDialog(context,
              title: "导出重命名", src: ab?.album?.name ?? "");
          if (rename == null || !mounted) return;
        }
        await methods.export_cbzs_zip_single(
          value,
          path,
          rename,
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

  Future<void> _exportZips() async {
    if (Platform.isMacOS) {
      if (!await chooseEx(context)) return;
    }
    if (!mounted) return;
    if (!await confirmDialog(
        context, "导出确认", "将您所选的漫画分别导出ZIP${showExportPath()}")) {
      return;
    }
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          exporting = true;
        });
      }
      final path = await attachExportPath();
      for (var value in widget.idList) {
        if (!mounted) return;
        var ab = await methods.downloadById(value);
        if (mounted) {
          setState(() {
            exportMessage = "正在导出 : " + (ab?.album?.name ?? "");
          });
        }
        String? rename;
        if (!mounted) return;
        if (currentExportRename()) {
          rename = await displayTextInputDialog(context,
              title: "导出重命名", src: ab?.album?.name ?? "");
          if (rename == null || !mounted) return;
        }
        await methods.export_jm_zip_single(
          value,
          path,
          rename,
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

  Future<void> _exportJpegZips() async {
    if (Platform.isMacOS) {
      if (!await chooseEx(context)) return;
    }
    if (!mounted) return;
    if (!await confirmDialog(
        context, "导出确认", "将您所选的漫画分别导出JPEGS.ZIP${showExportPath()}")) {
      return;
    }
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          exporting = true;
        });
      }
      final path = await attachExportPath();
      for (var value in widget.idList) {
        if (!mounted) return;
        var ab = await methods.downloadById(value);
        if (mounted) {
          setState(() {
            exportMessage = "正在导出 : " + (ab?.album?.name ?? "");
          });
        }
        String? rename;
        if (!mounted) return;
        if (currentExportRename()) {
          rename = await displayTextInputDialog(context,
              title: "导出重命名", src: ab?.album?.name ?? "");
          if (rename == null || !mounted) return;
        }
        await methods.export_jm_jpegs_zip_single(
          value,
          path,
          rename,
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

  Future<void> _exportEpubs() async {
    if (Platform.isMacOS) {
      if (!await chooseEx(context)) return;
    }
    if (!mounted) return;
    if (!await confirmDialog(
        context, "导出确认", "将您所选的漫画分别导出EPUB${showExportPath()}")) {
      return;
    }
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          exporting = true;
        });
      }
      final path = await attachExportPath();
      for (var value in widget.idList) {
        if (!mounted) return;
        var ab = await methods.downloadById(value);
        if (mounted) {
          setState(() {
            exportMessage = "正在导出 : " + (ab?.album?.name ?? "");
          });
        }
        String? rename;
        if (!mounted) return;
        if (currentExportRename()) {
          rename = await displayTextInputDialog(context,
              title: "导出重命名", src: ab?.album?.name ?? "");
          if (rename == null || !mounted) return;
        }
        await methods.export_jm_epub_single(
          value,
          path,
          rename,
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
          title: const Text("批量导出"),
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
