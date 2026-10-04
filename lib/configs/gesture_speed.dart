import 'package:flutter/material.dart';
import '../basic/debounced_writer.dart';
import 'package:jasmine/basic/methods.dart';

const _propertyName = "gestureSpeed";
const _defaultGestureSpeed = 1.0;

double _gestureSpeed = _defaultGestureSpeed;
final _writer = DebouncedWriter<double>(
  (value) async {
    await methods.saveProperty(_propertyName, '$value');
  },
  onError: (_, __) => debugPrint('手势速度保存失败'),
);

Future<void> initGestureSpeed() async {
  final value = await methods.loadProperty(_propertyName);
  _gestureSpeed = double.tryParse(value) ?? _defaultGestureSpeed;
  _gestureSpeed = _gestureSpeed.isFinite
      ? _gestureSpeed.clamp(0.2, 3.0)
      : _defaultGestureSpeed;
}

double currentGestureSpeed() => _gestureSpeed;

Widget gestureSpeedSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text("手势速度 : ${_gestureSpeed.toStringAsFixed(1)}x"),
        subtitle: Slider(
          value: _gestureSpeed,
          min: 0.2,
          max: 3.0,
          divisions: 28,
          label: "${_gestureSpeed.toStringAsFixed(1)}x",
          onChanged: (v) {
            final value = (v * 10).roundToDouble() / 10.0;
            setState(() {
              _gestureSpeed = value;
            });
          },
          onChangeEnd: (_) {
            _writer.add(_gestureSpeed);
          },
        ),
        trailing: Text(
          "${_gestureSpeed.toStringAsFixed(1)}x",
          style: const TextStyle(fontSize: 16),
        ),
      );
    },
  );
}
