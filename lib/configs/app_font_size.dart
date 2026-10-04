import 'package:flutter/material.dart';

import '../basic/methods.dart';

enum FontSizeAdjustType {
  fontSizeAdjustCommentContent,
}

final titleMap = {
  FontSizeAdjustType.fontSizeAdjustCommentContent: "评论",
};

final valueMap = {
  FontSizeAdjustType.fontSizeAdjustCommentContent: 0,
};

Future<void> initFontSizeAdjust() async {
  for (var key in titleMap.keys) {
    final str = await methods.loadProperty(key.toString());
    valueMap[key] = (int.tryParse(str) ?? 0).clamp(-5, 5);
  }
}

int currentFontSizeAdjust(FontSizeAdjustType type) {
  return valueMap[type]!;
}

List<Widget> fontSizeAdjustSettings() {
  return [
    for (var key in titleMap.keys) fontSizeAdjustSetting(key),
  ];
}

Widget fontSizeAdjustSetting(FontSizeAdjustType type) => _FontSizeSetting(type);

class _FontSizeSetting extends StatefulWidget {
  final FontSizeAdjustType type;
  const _FontSizeSetting(this.type);
  @override
  State<_FontSizeSetting> createState() => _FontSizeSettingState();
}

class _FontSizeSettingState extends State<_FontSizeSetting> {
  late int _draft = valueMap[widget.type]!;
  bool _saving = false;
  Future<void> _save(double _) async {
    if (_saving) return;
    final value = _draft;
    setState(() => _saving = true);
    try {
      await methods.saveProperty(widget.type.toString(), value.toString());
      valueMap[widget.type] = value;
    } catch (_) {
      if (mounted) {
        _draft = valueMap[widget.type]!;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('字体设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text('文字大小调整 - ${titleMap[widget.type]}'),
        subtitle: Slider(
            value: _draft.toDouble(),
            min: -5,
            max: 5,
            divisions: 10,
            label: '$_draft',
            onChanged: _saving
                ? null
                : (value) => setState(() => _draft = value.toInt()),
            onChangeEnd: _save),
        trailing: Text('$_draft', style: const TextStyle(fontSize: 16)),
      );
}
