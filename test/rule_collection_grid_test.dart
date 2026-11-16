import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/rule_collection_grid.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';

RuleBrowseItem makeItem(int index, {bool canOpen = true}) => RuleBrowseItem(
  title: '作品$index とても長いタイトルでもカードの高さが変わらないことを確認',
  url: canOpen ? Uri.parse('https://example.com/work/$index/') : null,
  thumbnail: null,
  date: '1時間前',
  latestChapter: '第49話',
  issues: const [],
);

Widget buildPage(
  List<RuleBrowseItem> items, {
  double textScale = 1,
  ValueChanged<RuleBrowseItem>? onOpen,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: CustomScrollView(
        slivers: [RuleCollectionSliver(items: items, onOpen: onOpen ?? (_) {})],
      ),
    ),
  ),
);

void main() {
  testWidgets('Collectionに話数と公開日を表示する', (tester) async {
    await tester.pumpWidget(buildPage([makeItem(1)]));

    expect(find.text('第49話  1時間前'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('話数・公開日が未取得でも正常に表示する', (tester) async {
    const item = RuleBrowseItem(
      title: '補足情報なしの作品',
      url: null,
      thumbnail: null,
      date: '',
      latestChapter: '',
      issues: [],
    );

    await tester.pumpWidget(buildPage([item]));

    expect(find.text('補足情報なしの作品'), findsOneWidget);
    expect(find.text('第49話  1時間前'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('スマホ相当の幅では3列で表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage(List.generate(6, makeItem)));

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 3);
    expect(find.byIcon(Icons.image_outlined), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC相当の幅では列数を増やす', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage(List.generate(6, makeItem)));

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, greaterThan(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字を拡大してもカードがオーバーフローしない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      buildPage(List.generate(4, makeItem), textScale: 2),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('作品タップで既存の遷移処理を呼べる', (tester) async {
    final item = makeItem(1);
    RuleBrowseItem? opened;

    await tester.pumpWidget(
      buildPage([item], onOpen: (value) => opened = value),
    );

    await tester.tap(find.text(item.title));
    await tester.pump();

    expect(opened, same(item));
    expect(tester.takeException(), isNull);
  });

  testWidgets('リンクがない作品は開かない', (tester) async {
    final item = makeItem(1, canOpen: false);
    var called = false;

    await tester.pumpWidget(buildPage([item], onOpen: (_) => called = true));

    await tester.tap(find.text(item.title));
    await tester.pump();

    expect(called, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('0件でも正常に表示する', (tester) async {
    await tester.pumpWidget(buildPage([]));
    expect(tester.takeException(), isNull);
  });
}
