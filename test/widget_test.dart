import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/main.dart';

void main() {
  testWidgets('保存画像がない場合に案内と読み方の切り替えを表示する', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderPage(files: [])));

    expect(find.text('保存された画像がありません'), findsOneWidget);
    expect(find.text('縦読み'), findsOneWidget);
    expect(find.text('横読み'), findsOneWidget);

    await tester.tap(find.text('横読み'));
    await tester.pumpAndSettle();

    final horizontal = tester.widget<SegmentedButton<ReadingMode>>(
      find.byType(SegmentedButton<ReadingMode>),
    );

    expect(horizontal.selected, equals({ReadingMode.horizontal}));

    await tester.tap(find.text('縦読み'));
    await tester.pumpAndSettle();

    final vertical = tester.widget<SegmentedButton<ReadingMode>>(
      find.byType(SegmentedButton<ReadingMode>),
    );

    expect(vertical.selected, equals({ReadingMode.vertical}));
  });
}
