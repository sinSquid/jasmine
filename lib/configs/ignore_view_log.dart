import 'package:jasmine/basic/ui_action.dart';
import 'package:flutter/material.dart';

import '../basic/methods.dart';

const _propertyName = "ignoreVewLog";
bool _ignoreVewLog = false;

Future<void> initIgnoreVewLog() async {
  _ignoreVewLog = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentIgnoreVewLog() {
  return _ignoreVewLog;
}

Widget ignoreVewLogSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        value: _ignoreVewLog,
        onChanged: (value) => runUiAction(context, () async {
          await methods.saveProperty(_propertyName, "$value");
          _ignoreVewLog = value;
          setState(() {});
        }),
        title: const Text("详情页不记录浏览记录"),
      );
    },
  );
}
