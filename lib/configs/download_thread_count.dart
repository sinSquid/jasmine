import 'package:jasmine/basic/ui_action.dart';

/// 多线程下载并发数

import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';

import '../basic/commons.dart';

int _downloadThreadCount = 1;
int get downloadThreadCount => _downloadThreadCount;
const _values = [1, 2, 3, 4, 5];

Future initDownloadThreadCount() async {
  _downloadThreadCount = (await methods.load_download_thread()).clamp(1, 5);
}

Widget downloadThreadCountSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: const Text("下载线程数"),
        subtitle: Text("$_downloadThreadCount"),
        onTap: () => runUiAction(context, () async {
          await chooseDownloadThread(context);
          if (context.mounted) setState(() {});
        }),
      );
    },
  );
}

Future chooseDownloadThread(BuildContext context) async {
  int? value = await chooseListDialog(
    context,
    title: "选择下载线程数",
    values: _values,
  );
  if (value != null) {
    await methods.set_download_thread(value);
    _downloadThreadCount = value;
  }
}
