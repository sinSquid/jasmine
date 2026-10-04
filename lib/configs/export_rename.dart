import 'package:jasmine/basic/ui_action.dart';
import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

const _propertyName = "exportRename";
bool _exportRename = false;

Future<void> initExportRename() async {
  _exportRename = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentExportRename() {
  return _exportRename;
}

Future<void> _chooseExportRename(BuildContext context) async {
  String? result = await chooseListDialog<String>(context,
      title: "导出的时候重新命名", values: ["是", "否"]);
  if (result != null) {
    var target = result == "是";
    await methods.saveProperty(_propertyName, "$target");
    _exportRename = target;
  }
}

Widget exportRenameSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: const Text("导出的时候重新命名"),
        subtitle: Text(_exportRename ? "是" : "否"),
        onTap: () => runUiAction(context, () async {
          await _chooseExportRename(context);
          setState(() {});
        }),
      );
    },
  );
}
