import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/rule_acquisition_notice.dart';

void main() {
  Future<void> showNotice(
    WidgetTester tester, {
    required String acquisition,
    required bool pageAvailable,
    bool canFetchStaticHere = true,
    String title = '現在の取得方式（保存対象）',
    String saveHint = 'サイトに保存して確定します。',
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RuleAcquisitionNotice(
                acquisition: acquisition,
                pageAvailable: pageAvailable,
                canFetchStaticHere: canFetchStaticHere,
                title: title,
                saveHint: saveHint,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  String modeText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('rule-acquisition-mode')))
      .data!;

  String pageText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('rule-acquisition-page')))
      .data!;

  testWidgets('通常HTMLの設定と未取得状態を別々に表示する', (tester) async {
    await showNotice(tester, acquisition: 'staticHtml', pageAvailable: false);

    expect(modeText(tester), '通常HTML');
    expect(pageText(tester), '対象URLのHTML：未取得、または入力URL変更後');
    expect(find.text('現在の取得方式（保存対象）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('表示後HTML設定でも未取得状態を区別する', (tester) async {
    await showNotice(tester, acquisition: 'renderedDom', pageAvailable: false);

    expect(modeText(tester), '表示後HTML');
    expect(pageText(tester), '対象URLのHTML：未取得、または入力URL変更後');
  });

  testWidgets('取得済み状態を表示する', (tester) async {
    await showNotice(tester, acquisition: 'renderedDom', pageAvailable: true);

    expect(modeText(tester), '表示後HTML');
    expect(pageText(tester), '対象URLのHTML：取得済み');
  });

  testWidgets('渡された取得方式の変更を表示へ反映する', (tester) async {
    await showNotice(tester, acquisition: 'staticHtml', pageAvailable: true);

    expect(modeText(tester), '通常HTML');

    await showNotice(tester, acquisition: 'renderedDom', pageAvailable: true);

    expect(modeText(tester), '表示後HTML');

    await showNotice(tester, acquisition: 'staticHtml', pageAvailable: true);

    expect(modeText(tester), '通常HTML');
  });

  testWidgets('作品詳細では親へ反映する説明を表示する', (tester) async {
    await showNotice(
      tester,
      acquisition: 'renderedDom',
      pageAvailable: false,
      canFetchStaticHere: false,
      title: '親画面へ反映する取得方式',
      saveHint: '設定を反映して戻り、一覧画面で保存します。',
    );

    expect(find.text('親画面へ反映する取得方式'), findsOneWidget);
    expect(find.text('設定を反映して戻り、一覧画面で保存します。'), findsOneWidget);
    expect(find.textContaining('前の一覧設定画面で通常HTMLを取得'), findsOneWidget);
  });

  testWidgets('未対応の方式を通常HTMLと誤表示しない', (tester) async {
    await showNotice(tester, acquisition: 'unknown', pageAvailable: false);

    expect(modeText(tester), '未対応の取得方式');
  });

  testWidgets('狭い画面と大きい文字でもオーバーフローしない', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await showNotice(
      tester,
      acquisition: 'renderedDom',
      pageAvailable: true,
      textScale: 2,
    );

    expect(modeText(tester), '表示後HTML');
    expect(tester.takeException(), isNull);
  });

  test('3画面に取得方式の表示を接続する', () {
    const paths = [
      'lib/list_rule_lab_page.dart',
      'lib/chapter_image_lab_page.dart',
      'lib/work_details_editor_page.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();

      expect(
        source.contains("import 'rule_acquisition_notice.dart';"),
        isTrue,
        reason: path,
      );
      expect(source.contains('RuleAcquisitionNotice('), isTrue, reason: path);
    }
  });
}
