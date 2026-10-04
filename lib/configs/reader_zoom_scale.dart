import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';

const _keys = [
  'readerZoomMinScale',
  'readerZoomMaxScale',
  'readerZoomDoubleTapScale'
];
final _scales = ValueNotifier<List<double>>([1, 2, 2]);
double get readerZoomMinScale => _scales.value[0];
double get readerZoomMaxScale => _scales.value[1];
double get readerZoomDoubleTapScale => _scales.value[2];

List<double> _normalize(List<double> values) {
  final min = values[0].isFinite ? values[0].clamp(0.2, 1.0) : 1.0;
  final max = values[1].isFinite ? values[1].clamp(1.0, 30.0) : 2.0;
  final tap = values[2].isFinite ? values[2] : 2.0;
  return [min, max, tap.clamp(1.0, math.min(5.0, max))];
}

Future<void> initReaderZoomScale() async {
  final values = <double>[];
  for (var i = 0; i < _keys.length; i++) {
    values.add(double.tryParse(await methods.loadProperty(_keys[i])) ??
        [1.0, 2.0, 2.0][i]);
  }
  _scales.value = _normalize(values);
  _savedScales = List.of(_scales.value);
}

// Disable all three controls during a save: no unbounded chain of snapshots.
final _saving = ValueNotifier<bool>(false);
List<double> _savedScales = [1, 2, 2];
Future<void> _save() async {
  if (_saving.value) return;
  final values = List<double>.of(_scales.value);
  _saving.value = true;
  try {
    for (var i = 0; i < _keys.length; i++) {
      await methods.saveProperty(_keys[i], '${values[i]}');
      _savedScales[i] = values[i];
    }
  } catch (_) {
    _scales.value = _normalize(_savedScales);
    rethrow;
  } finally {
    _saving.value = false;
  }
}

Widget _setting(
    int index, String title, double min, double max, int divisions) {
  return ListenableBuilder(
    listenable: Listenable.merge([_scales, _saving]),
    builder: (context, _) {
      final values = _scales.value;
      final upper = index == 2 ? math.min(max, values[1]) : max;
      return ListTile(
        title: Text('$title : ${values[index].toStringAsFixed(1)}x'),
        subtitle: Slider(
          value: values[index],
          min: min,
          max: upper,
          divisions: divisions,
          onChanged: _saving.value || upper == min
              ? null
              : (value) {
                  final next = List<double>.of(values);
                  next[index] = (value * 10).roundToDouble() / 10;
                  _scales.value = _normalize(next);
                },
          onChangeEnd: (_) async {
            try {
              await _save();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('缩放设置保存失败，请重试')));
              }
            }
          },
        ),
        trailing: Text('${values[index].toStringAsFixed(1)}x'),
      );
    },
  );
}

Widget readerZoomMinScaleSetting() => _setting(0, '缩小最小倍数', 0.2, 1, 8);
Widget readerZoomMaxScaleSetting() => _setting(1, '放大最大倍数', 1, 30, 58);
Widget readerZoomDoubleTapScaleSetting() => _setting(2, '双击放大倍数', 1, 5, 40);
