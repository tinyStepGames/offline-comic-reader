import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/list_rule_lab_page.dart';
import 'package:offline_comic_reader/work_details_editor_page.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';

void main() {
  late Directory directory;
  late DownloadStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rule-editor-unsaved-');
    store = DownloadStore(directory);
  });

  tearDown(() async {
    store.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  ListExtractionRule makeRule({
    String kind = 'works',
    Map<String, ListFieldRule> details = const {},
  }) => ListExtractionRule(
    pageUrl: 'https://example.com/list/',
    groupSelector: '.item',
    kind: kind,
    acquisition: 'staticHtml',
    fields: defaultListFields(),
    details: details,
  );

  Future<void> open(
    WidgetTester tester,
    Widget page, {
    List<Object?>? results,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute<Object?>(builder: (_) => page),
                );
                results?.add(result);
              },
              child: const Text('open settings'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
  }

  Widget listPage({Future<void> Function(ListExtractionRule)? save}) =>
      ListRuleLabPage(
        store: store,
        initialPage: null,
        initialUrl: 'https://example.com/list/',
        initialSelector: '.item',
        initialAcquisition: 'staticHtml',
        initialRule: makeRule(),
        onSaveRule: save,
      );

  Finder textField(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  /// TextField内部のScrollableではなく、画面本体のListViewを使う。
  Finder pageScrollable() => find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;

  /// 先頭へ戻してから下方向に探すため、
  /// 上側へ戻る操作・画面外の未作成項目の両方に対応する。
  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = pageScrollable();
    final state = tester.state<ScrollableState>(scrollable);

    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      target,
      240,
      scrollable: scrollable,
      maxScrolls: 80,
    );
    await tester.pumpAndSettle();

    expect(target, findsOneWidget, reason: 'スクロール後に操作対象が1件存在すること');

    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> changeGroup(WidgetTester tester) async {
    final field = textField('1件分のまとまり');
    await reveal(tester, field);
    await tester.enterText(field, '.changed');
    await tester.pumpAndSettle();
  }

  Future<void> saveList(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'サイトに保存');
    await reveal(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  Future<void> closeTestPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('一覧ルールの変更時に戻る確認を出す', (tester) async {
    await open(tester, listPage());
    await changeGroup(tester);
    await back(tester);

    expect(find.text('変更が保存されていません'), findsOneWidget);

    await tester.tap(find.text('編集を続ける'));
    await tester.pumpAndSettle();

    final field = textField('1件分のまとまり');
    await reveal(tester, field);

    expect(tester.widget<TextField>(field).controller!.text, '.changed');

    await closeTestPage(tester);
  });

  testWidgets('専用一覧の保存成功後は確認しない', (tester) async {
    ListExtractionRule? saved;

    await open(
      tester,
      listPage(
        save: (rule) async {
          saved = rule;
        },
      ),
    );

    await changeGroup(tester);
    await saveList(tester);

    expect(saved?.groupSelector, '.changed');

    await back(tester);

    expect(find.text('変更が保存されていません'), findsNothing);
    expect(find.text('open settings'), findsOneWidget);

    await closeTestPage(tester);
  });

  testWidgets('専用一覧の保存失敗後は未保存として扱う', (tester) async {
    await open(
      tester,
      listPage(
        save: (_) async {
          throw StateError('保存失敗テスト');
        },
      ),
    );

    await changeGroup(tester);
    await saveList(tester);
    await back(tester);

    expect(find.text('変更が保存されていません'), findsOneWidget);

    await closeTestPage(tester);
  });

  testWidgets('一覧プレビューの切替だけでは未保存にしない', (tester) async {
    await open(tester, listPage());

    final toggle = find.widgetWithText(SwitchListTile, '表紙画像を通信して表示');

    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    await back(tester);

    expect(find.text('変更が保存されていません'), findsNothing);
    expect(find.text('open settings'), findsOneWidget);

    await closeTestPage(tester);
  });

  testWidgets('作品詳細は設定を反映して親へ返せる', (tester) async {
    final results = <Object?>[];

    await open(
      tester,
      WorkDetailsEditorPage(
        rule: makeRule(
          kind: 'chapters',
          details: {'title': const ListFieldRule(selector: 'h1')},
        ),
        page: null,
      ),
      results: results,
    );

    final expansion = find.widgetWithText(ExpansionTile, '作品タイトル');

    await reveal(tester, expansion);
    await tester.tap(expansion);
    await tester.pumpAndSettle();

    final selector = find.byWidgetPredicate(
      (widget) => widget is TextFormField && widget.initialValue == 'h1',
    );

    await reveal(tester, selector);
    await tester.enterText(selector, '.work-title');
    await tester.pumpAndSettle();

    final apply = find.widgetWithText(FilledButton, '設定を反映して戻る');

    await reveal(tester, apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(find.text('変更が保存されていません'), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, isA<WorkDetailEditResult>());

    final result = results.single! as WorkDetailEditResult;
    expect(result.fields['title']?.selector, '.work-title');
    expect(find.text('open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await closeTestPage(tester);
  });

  test('対象の6編集画面に共通確認処理を接続する', () {
    const paths = [
      'lib/list_rule_lab_page.dart',
      'lib/work_details_editor_page.dart',
      'lib/chapter_image_lab_page.dart',
      'lib/tag_navigation_editor_page.dart',
      'lib/site_search_editor_page.dart',
      'lib/site_browse_tabs_editor_page.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();

      expect(
        source.contains('with EditorUnsavedChanges<'),
        isTrue,
        reason: path,
      );
      expect(
        source.contains('guardEditor(_buildEditor(context))'),
        isTrue,
        reason: path,
      );
      expect(
        source.contains('leading: editorBackButton'),
        isTrue,
        reason: path,
      );
    }
  });
}
