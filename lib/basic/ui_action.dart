import 'dart:async';
import 'package:flutter/material.dart';
import 'commons.dart';

final _busyActions = Expando<bool>('ui actions');

/// Owns errors and prevents reentry for one mounted UI context.
Future<void> runUiAction(BuildContext context, FutureOr<void> Function() action,
    {String failureMessage = '操作失败，请重试'}) async {
  if (!context.mounted || _busyActions[context] == true) return;
  _busyActions[context] = true;
  try {
    await action();
  } catch (_) {
    defaultToast(context, failureMessage);
  } finally {
    _busyActions[context] = false;
  }
}

/// Config values may finish persisting after the settings tile is removed.
/// Apply the state change, but never rebuild a disposed element.
class SettingsBuilder extends StatefulWidget {
  final StatefulWidgetBuilder builder;
  const SettingsBuilder({super.key, required this.builder});
  @override
  State<SettingsBuilder> createState() => _SettingsBuilderState();
}

class _SettingsBuilderState extends State<SettingsBuilder> {
  void _update(VoidCallback change) {
    change();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _update);
}
