import 'package:jasmine/basic/ui_action.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart';

import '../basic/methods.dart';

const _propertyName = "disableRecommendContent";
late bool _disableRecommendContent;
final disableRecommendContentEvent = Event();

Future<void> initDisableRecommendContent() async {
  _disableRecommendContent =
      (await methods.loadProperty(_propertyName)) == "true";
}

bool currentDisableRecommendContent() {
  return _disableRecommendContent;
}

Widget disableRecommendContentSetting() {
  return SettingsBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        title: const Text("关闭推荐内容"),
        subtitle: Text(_disableRecommendContent ? "已关闭" : "已开启"),
        value: _disableRecommendContent,
        onChanged: (value) => runUiAction(context, () async {
          await methods.saveProperty(_propertyName, "$value");
          _disableRecommendContent = value;
          disableRecommendContentEvent.broadcast();
          setState(() {});
        }),
      );
    },
  );
}
