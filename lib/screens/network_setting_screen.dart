import 'dart:io';
import '../basic/ui_action.dart';
import '../configs/Authentication.dart';
import '../configs/android_version.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/configs/network_api_host.dart';
import 'package:jasmine/configs/network_cdn_host.dart';
import 'package:jasmine/configs/proxy.dart';
import 'package:jasmine/screens/init_screen.dart';

import 'components/right_click_pop.dart';
import 'downloads_screen.dart';

class NetworkSettingScreen extends StatelessWidget {
  const NetworkSettingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("网络设置"),
        actions: [
          IconButton(
            onPressed: () => runUiAction(context, () async {
              if (Platform.isAndroid) await initAndroidVersion();
              await initAuthentication();
              if (!context.mounted) return;
              if (currentAuthentication() &&
                  !await verifyAuthentication(context)) return;
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return const DownloadsScreen();
                }),
              );
            }, failureMessage: '无法验证身份，请重试'),
            icon: const Icon(Icons.download),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return const InitScreen();
                }),
              );
            },
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: ListView(
        children: [
          apiHostSetting(),
          cdnHostSetting(),
          proxySetting(),
        ],
      ),
    );
  }
}
