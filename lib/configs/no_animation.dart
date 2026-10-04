import 'package:jasmine/basic/ui_action.dart';
import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

const _propertyName = "noAnimation";
bool _noAnimation = false;

Future<void> initNoAnimation() async {
  _noAnimation = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentNoAnimation() {
  return _noAnimation;
}

Future<void> _chooseNoAnimation(BuildContext context) async {
  String? result = await chooseListDialog<String>(context,
      title: "取消键盘或音量翻页动画", values: ["是", "否"]);
  if (result != null) {
    var target = result == "是";
    await methods.saveProperty(_propertyName, "$target");
    _noAnimation = target;
  }
}

Widget noAnimationSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: const Text("取消键盘或音量翻页动画"),
        subtitle: Text(_noAnimation ? "是" : "否"),
        onTap: () => runUiAction(context, () async {
          await _chooseNoAnimation(context);
          setState(() {});
        }),
      );
    },
  );
}
