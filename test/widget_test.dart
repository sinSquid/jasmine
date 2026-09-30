import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/content_loading.dart';

void main() {
  testWidgets('loading state shows progress and its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContentLoading(label: '正在加载')),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在加载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
