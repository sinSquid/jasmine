import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/login.dart';

enum DailySignStatus {
  unchecked,
  checking,
  signed,
  error,
}

DailySignStatus dailySignStatus = DailySignStatus.unchecked;

final dailySignEvent = Event();
int _revision = 0;
void resetDailySignStatus() {
  _revision++;
  _setDailySignStatus(DailySignStatus.unchecked);
}

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
}

String dailySignStatusLabel() {
  switch (dailySignStatus) {
    case DailySignStatus.checking:
      return "检测中...";
    case DailySignStatus.signed:
      return "已打卡";
    case DailySignStatus.error:
      return "打卡失败";
    case DailySignStatus.unchecked:
    default:
      return "未检测打卡";
  }
}

Future<void> checkDailySignStatus(BuildContext context,
    {bool toast = false}) async {
  if (loginStatus != LoginStatus.loginSuccess) {
    _setDailySignStatus(DailySignStatus.unchecked);
    return;
  }
  if (dailySignStatus == DailySignStatus.checking) return;
  final revision = _revision;
  final session = sessionRevision;
  final uid = selfInfo.uid;
  bool current() =>
      revision == _revision &&
      session == sessionRevision &&
      loginStatus == LoginStatus.loginSuccess;
  _setDailySignStatus(DailySignStatus.checking);
  try {
    final msg = await methods.daily(uid);
    if (!current()) return;
    if (toast) {
      defaultToast(context, msg.isNotEmpty ? msg : "已打卡");
    }
    _setDailySignStatus(DailySignStatus.signed);
  } catch (_) {
    if (!current()) return;
    debugPrient('打卡失败');
    if (toast) {
      defaultToast(context, '打卡失败，请重试');
    }
    _setDailySignStatus(DailySignStatus.error);
  }
}
