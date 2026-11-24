import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/list_rule_lab_page.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';

void main() {
  late Directory directory;
  late DownloadStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('list-rule-no-share-');
    store = DownloadStore(directory);
  });

  tearDown(() async {
    store.close();

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  ListExtractionRule makeRule(String kind) {
    return ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.item',
      kind: kind,
      acquisition: 'staticHtml',
      fields: defaultListFields(),
    );
  }

  Future<void> openPage(
    WidgetTester tester, {
    required String kind,
    Future<void> Function(ListExtractionRule rule)? onSaveRule,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ListRuleLabPage(
          store: store,
          initialPage: null,
          initialUrl: 'https://example.com/list/',
          initialSelector: '.item',
          initialAcquisition: 'staticHtml',
          initialRule: makeRule(kind),
          onSaveRule: onSaveRule,
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  for (final kind in ['works', 'chapters']) {
    testWidgets('$kindの編集で個別共有を除き保存操作を残す', (tester) async {
      await openPage(tester, kind: kind);

      expect(find.byTooltip('下書きを保存'), findsOneWidget);
      expect(find.byTooltip('下書きを復元'), findsOneWidget);

      expect(find.widgetWithText(FilledButton, 'サイトに保存'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('通常HTMLを取得'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('通常HTMLを取得'), findsOneWidget);
      expect(find.text('まとまりをページから選ぶ'), findsOneWidget);
      expect(find.text('一覧JSON・QR'), findsNothing);
      expect(find.text('JSONコピー'), findsNothing);
      expect(find.text('QR表示'), findsNothing);

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('専用一覧のサイト保存は引き続き設定を渡す', (tester) async {
    ListExtractionRule? saved;

    await openPage(
      tester,
      kind: 'works',
      onSaveRule: (rule) async {
        saved = rule;
      },
    );

    final saveButton = find.widgetWithText(FilledButton, 'サイトに保存');

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.kind, 'works');
    expect(saved!.groupSelector, '.item');
    expect(saved!.acquisition, 'staticHtml');

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('サイト管理と編集画面に個別共有の参照を残さない', () {
    final manager = File('lib/site_rules_page.dart').readAsStringSync();
    final lab = File('lib/list_rule_lab_page.dart').readAsStringSync();

    expect(manager.contains('ListRuleTransferPage'), isFalse);
    expect(lab.contains('ListRuleTransferPage'), isFalse);

    expect(manager.contains('単一の一覧JSONを取り込む'), isFalse);
    expect(manager.contains('_share('), isFalse);

    expect(manager.contains('サイト一式のJSON・QR'), isTrue);
    expect(manager.contains('サイト一式を取り込む'), isTrue);
    expect(manager.contains('SiteBundlePage('), isTrue);

    expect(lab.contains('下書きを保存'), isTrue);
    expect(lab.contains('下書きを復元'), isTrue);
    expect(lab.contains('一覧としてテスト'), isTrue);
  });
}
