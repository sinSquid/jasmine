import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/Authentication.dart';
import 'package:jasmine/configs/configs.dart';
import 'package:jasmine/configs/login.dart';

import '../basic/web_dav_sync.dart';
import 'app_screen.dart';
import 'first_login_screen.dart';
import 'network_setting_screen.dart';

/// Continue to the app while preserving the configured authentication gate.
Future<void> activateApp(BuildContext context) async {
  if (!context.mounted) return;
  if (currentAuthentication()) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    return;
  }
  if (loginStatus == LoginStatus.notSet) {
    await webDavSyncAuto(context);
    if (!context.mounted) return;
  }
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
        builder: (_) => loginStatus == LoginStatus.notSet
            ? firstLoginScreen
            : const AppScreen()),
  );
}

class InitScreen extends StatefulWidget {
  const InitScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  String? _startupImagePath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _startupImagePath != null && _startupImagePath!.isNotEmpty
          ? Center(
              child: Image.file(
                File(_startupImagePath!),
                fit: BoxFit.contain,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            )
          : const Center(
              child: Text("initializing..."),
            ),
    );
  }

  Future _init() async {
    try {
      await methods.init();
      if (!mounted) return;
      final startupImagePath = await methods.getStartupImagePath();
      if (!mounted) return;
      setState(() {
        _startupImagePath = startupImagePath;
      });
      await methods.init2();
      if (!mounted) return;
      await initConfigs(context);
      if (!mounted) return;
      debugPrient("STATE : ${loginStatus}");
      await webDavSyncAuto(context);
      if (!mounted) return;

      final Widget nextScreen;
      if (currentAuthentication()) {
        nextScreen = const AuthScreen();
      } else if (loginStatus == LoginStatus.notSet) {
        nextScreen = firstLoginScreen;
      } else {
        nextScreen = const AppScreen();
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => nextScreen),
      );
    } catch (e, st) {
      debugPrient("$e\n$st");
      if (!mounted) return;
      defaultToast(context, "初始化失败, 请设置网络");
      Future.delayed(Duration.zero, () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (BuildContext context) {
            return const NetworkSettingScreen();
          }),
        );
      });
    }
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      test();
    });
  }

  bool _verifying = false;

  Future<void> test() async {
    if (!mounted || _verifying) return;
    setState(() => _verifying = true);
    try {
      final verified = await verifyAuthentication(context);
      if (!mounted || !verified) return;
      if (loginStatus == LoginStatus.notSet) {
        await webDavSyncAuto(context);
        if (!mounted) return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => loginStatus == LoginStatus.notSet
                ? firstLoginScreen
                : const AppScreen()),
      );
    } catch (_) {
      if (mounted) defaultToast(context, "身份验证失败，请重试");
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("身份验证"),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: MaterialButton(
            onPressed: _verifying ? null : test,
            child: const Text(
              '您在之前使用APP时开启了身份验证, 请点这段文字进行身份核查, 核查通过后将会进入APP',
            ),
          ),
        ),
      ),
    );
  }
}
