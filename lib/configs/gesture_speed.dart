import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';

const _propertyName = "gestureSpeed";
const _defaultGestureSpeed = 1.0;

double _gestureSpeed = _defaultGestureSpeed;
Future<void> initGestureSpeed() async {
  final value = await methods.loadProperty(_propertyName);
  _gestureSpeed = double.tryParse(value) ?? _defaultGestureSpeed;
  _gestureSpeed = _gestureSpeed.isFinite
      ? _gestureSpeed.clamp(0.2, 3.0)
      : _defaultGestureSpeed;
}

double currentGestureSpeed() => _gestureSpeed;

Widget gestureSpeedSetting() => const _GestureSpeedSetting();

class _GestureSpeedSetting extends StatefulWidget {
  const _GestureSpeedSetting();
  @override
  State<_GestureSpeedSetting> createState() => _GestureSpeedSettingState();
}

class _GestureSpeedSettingState extends State<_GestureSpeedSetting> {
  late double _draft = _gestureSpeed;
  bool _saving = false;
  Future<void> _save(double _) async {
    if (_saving) return;
    final value = _draft;
    setState(() => _saving = true);
    try {
      await methods.saveProperty(_propertyName, '$value');
      _gestureSpeed = value;
    } catch (_) {
      _draft = _gestureSpeed;
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('手势速度保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text('手势速度 : ${_draft.toStringAsFixed(1)}x'),
        subtitle: Slider(
            value: _draft,
            min: 0.2,
            max: 3.0,
            divisions: 28,
            label: '${_draft.toStringAsFixed(1)}x',
            onChanged: _saving
                ? null
                : (value) =>
                    setState(() => _draft = (value * 10).roundToDouble() / 10),
            onChangeEnd: _save),
        trailing: Text('${_draft.toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 16)),
      );
}
