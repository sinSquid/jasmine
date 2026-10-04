import 'package:jasmine/basic/ui_action.dart';
import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

const _propertyName = "webDavSyncSwitch";
late bool _webDavSyncSwitch;

Future<void> initWebDavSyncSwitch() async {
  _webDavSyncSwitch = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentWebDavSyncSwitch() {
  return _webDavSyncSwitch;
}

Future<void> _chooseWebDavSyncSwitch(BuildContext context) async {
  String? result = await chooseListDialog<String>(context,
      title: "开开启时自动同步历史记录到WebDAV", values: ["是", "否"]);
  if (result != null) {
    var target = result == "是";
    await methods.saveProperty(_propertyName, "$target");
    _webDavSyncSwitch = target;
  }
}

Widget webDavSyncSwitchSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: const Text("开启时自动同步历史记录到WebDAV"),
        subtitle: Text(_webDavSyncSwitch ? "是" : "否"),
        onTap: () => runUiAction(context, () async {
          await _chooseWebDavSyncSwitch(context);
          setState(() {});
        }),
      );
    },
  );
}
