import 'package:flutter/material.dart';
import 'package:jasmine/configs/app_font_size.dart';
import '../../basic/commons.dart';

class TextPreviewScreen extends StatefulWidget {
  final String text;

  const TextPreviewScreen({
    required this.text,
    Key? key,
  }) : super(key: key);

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  @override
  Widget build(BuildContext context) {
    final contentFontSize = (Theme.of(context).textTheme.bodyMedium?.fontSize ??
            14) +
        currentFontSizeAdjust(FontSizeAdjustType.fontSizeAdjustCommentContent);

    return Scaffold(
      appBar: AppBar(
        title: const Text('评论全文'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => copyToClipBoard(context, widget.text),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: SelectableText(
          widget.text,
          style: TextStyle(
            fontSize: contentFontSize,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
