import 'package:jasmine/basic/ui_action.dart';
import 'package:flutter/material.dart';

import '../basic/methods.dart';

const _propertyName = "ignoreUpgradePop";
late bool _ignoreUpgradePop;

Future<void> initIgnoreUpgradePop() async {
  _ignoreUpgradePop = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentIgnoreUpgradePop() {
  return _ignoreUpgradePop;
}

Widget ignoreUpgradePopSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        title: const Text("是否忽略升级弹窗"),
        subtitle: Text(_ignoreUpgradePop ? "是" : "否"),
        value: _ignoreUpgradePop,
        onChanged: (value) => runUiAction(context, () async {
          await methods.saveProperty(_propertyName, "$value");
          _ignoreUpgradePop = value;
          setState(() {});
        }),
      );
    },
  );
}
