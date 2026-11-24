import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_browse_tab.dart';
import 'package:offline_comic_reader/services/site_import_comparison.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/site_search_settings.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';
import 'package:offline_comic_reader/site_bundle_page.dart';
import 'package:offline_comic_reader/site_import_comparison_panel.dart';

ListExtractionRule makeRule({
  String kind = 'works',
  String group = '.item',
  String pagination = '',
  bool details = false,
}) {
  final fields = defaultListFields();
  fields['title'] = const ListFieldRule(selector: '.title');
  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  return ListExtractionRule(
    pageUrl: kind == 'works'
        ? 'https://example.com/list/'
        : 'https://example.com/work/sample/',
    groupSelector: group,
    fields: fields,
    kind: kind,
    acquisition: 'staticHtml',
    paginationUrl: pagination,
    details: details
        ? {'description': const ListFieldRule(selector: '.description')}
        : {},
  );
}

SavedSiteRule makeSite({
  String id = 'AAAAAAAAAAAAAAAAAAAAAA',
  String name = 'Example site',
  DateTime? updatedAt,
  bool full = true,
  String worksGroup = '.item',
  List<SiteBrowseTab>? tabs,
}) => SavedSiteRule(
  id: id,
  name: name,
  updatedAt: updatedAt ?? DateTime.utc(2026, 11, 22),
  rules: {
    'works': makeRule(
      group: worksGroup,
      pagination: full ? 'https://example.com/list/?page={page;1}' : '',
    ),
    if (full) 'chapters': makeRule(kind: 'chapters', details: true),
  },
  images: full
      ? const ChapterImageSettings(
          pageUrl: 'https://example.com/chapter/sample/',
          acquisition: 'staticHtml',
          rule: ChapterImageRule(selector: '#reader img', attribute: 'src'),
        )
      : null,
  tagNavigation: full
      ? TagNavigationSettings(
          rule: makeRule(group: '.tag-item'),
          urlPattern: r'^https://example\.com/genre/(.+)$',
          urlReplacement: r'https://example.com/list/?genre=$1',
        )
      : null,
  searchSettings: full
      ? const SiteSearchSettings(
          urlTemplate: 'https://example.com/search/?q={keyword}',
        )
      : null,
  browseTabs:
      tabs ??
      (full
          ? const [
              SiteBrowseTab(
                id: 'latest',
                title: 'Latest',
                pageUrl: 'https://example.com/latest/',
              ),
              SiteBrowseTab(
                id: 'ranking',
                title: 'Ranking',
                pageUrl: 'https://example.com/ranking/',
              ),
            ]
          : const []),
);

SiteImportChange changeFor(SiteImportComparison comparison, String key) =>
    comparison.changes.singleWhere((change) => change.key == key);

Object? reverseMaps(Object? value) {
  if (value is Map) {
    return {
      for (final key in value.keys.toList().reversed)
        key: reverseMaps(value[key]),
    };
  }
  if (value is List) return value.map(reverseMaps).toList();
  return value;
}

class MemorySiteStore extends SiteRuleStore {
  MemorySiteStore(this.sites)
    : super(
        Directory(
          '${Directory.systemTemp.path}/unused-import-comparison/comics',
        ),
      );

  List<SavedSiteRule> sites;
  int writes = 0;

  @override
  Future<List<SavedSiteRule>> load() async => List.of(sites);

  @override
  Future<SavedSiteRule> importSiteBundle({
    required SavedSiteRule incoming,
    String? targetId,
    DateTime? expectedUpdatedAt,
  }) async {
    writes++;
    throw StateError('Import must not execute in preview/cancel tests');
  }
}

Finder outerScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('site-bundle-scroll')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// 最初から外側一覧を明示する。
/// ドラッグの当たり判定や内側TextFieldのスクロールに依存しない。
Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('site-bundle-scroll')),
    findsOneWidget,
    reason: 'The import page must still be displayed',
  );

  final scrollFinder = outerScrollable();
  expect(scrollFinder, findsOneWidget);

  var position = tester.state<ScrollableState>(scrollFinder).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();

  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      expect(finder, findsOneWidget);
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
      return;
    }

    position = tester.state<ScrollableState>(scrollFinder).position;

    final next = (position.pixels + 240)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    if (next <= position.pixels + 0.1) break;

    position.jumpTo(next);
    await tester.pumpAndSettle();
  }

  fail('The target widget was not built in the import list: $finder');
}

Future<void> tapVisible(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await reveal(tester, finder);
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'The target must be visible and tappable before tapping',
  );
  await tester.tap(finder);

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 確認中は背後の進捗バーが動き続ける。
    // ダイアログの表示フレームと遷移分だけ進める。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> inspectBundle(
  WidgetTester tester,
  MemorySiteStore store,
  SavedSiteRule incoming,
) async {
  await tester.pumpWidget(MaterialApp(home: SiteBundlePage(repository: store)));
  await tester.pumpAndSettle();

  final input = find.byKey(const ValueKey('site-bundle-input'));
  await reveal(tester, input);

  await tester.enterText(input, SiteRuleBundle.fromSite(incoming).encodeJson());

  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();

  await tapVisible(tester, find.byKey(const ValueKey('site-bundle-inspect')));

  // 「内容を確認」が成功してから反映先を操作する。
  await reveal(tester, find.text('形式を確認しました。まだ通信・保存はしていません。'));

  expect(find.text('形式を確認しました。まだ通信・保存はしていません。'), findsOneWidget);
  expect(store.writes, 0);
}

Future<void> selectTarget(WidgetTester tester, SavedSiteRule target) async {
  await tapVisible(
    tester,
    find.byKey(const ValueKey('site-import-mode-update')),
  );

  final finder = find.byKey(const ValueKey('site-import-target'));

  await reveal(tester, finder);

  final dropdown = tester.widget<DropdownButton<String>>(finder);
  expect(dropdown.onChanged, isNotNull);

  dropdown.onChanged!(target.id);
  await tester.pumpAndSettle();

  await reveal(tester, finder);
  expect(tester.widget<DropdownButton<String>>(finder).value, target.id);
}

void main() {
  test('new import does not overwrite a same-name site implicitly', () {
    final comparison = SiteImportComparison.compare(incoming: makeSite());

    expect(comparison.isNew, isTrue);
    expect(comparison.hasRemovals, isFalse);
    expect(comparison.actionText, contains('自動では上書きしません'));
    expect(changeFor(comparison, 'works').kind, SiteImportChangeKind.added);
  });

  test('ID and timestamp are not considered setting changes', () {
    final comparison = SiteImportComparison.compare(
      target: makeSite(),
      incoming: makeSite(
        id: 'BBBBBBBBBBBBBBBBBBBBBB',
        updatedAt: DateTime.utc(2030),
      ),
    );

    expect(comparison.hasChanges, isFalse);
    expect(comparison.hasRemovals, isFalse);
  });

  test('map insertion order is ignored', () {
    final original = makeSite();
    final reordered = SavedSiteRule.fromJson(
      Map<String, dynamic>.from(reverseMaps(original.toJson())! as Map),
    );

    expect(
      SiteImportComparison.compare(
        target: original,
        incoming: reordered,
      ).hasChanges,
      isFalse,
    );
  });

  test('changed work selectors are detected', () {
    final comparison = SiteImportComparison.compare(
      target: makeSite(),
      incoming: makeSite(worksGroup: '.changed'),
    );

    expect(changeFor(comparison, 'works').kind, SiteImportChangeKind.changed);
    expect(
      changeFor(comparison, 'search').kind,
      SiteImportChangeKind.unchanged,
    );
    expect(comparison.toText(), contains('参照元の変更'));
  });

  test('removed settings and nested setting groups are warned', () {
    final comparison = SiteImportComparison.compare(
      target: makeSite(),
      incoming: makeSite(full: false),
    );

    for (final key in [
      'pagination',
      'chapters',
      'details',
      'images',
      'tags',
      'tagTransform',
      'search',
      'tabs',
    ]) {
      expect(
        changeFor(comparison, key).kind,
        SiteImportChangeKind.removed,
        reason: key,
      );
    }

    expect(comparison.hasRemovals, isTrue);
    expect(comparison.toText(), contains('削除される設定があります'));
    expect(comparison.toText(), contains('本文画像：削除されます'));
  });

  test('absent settings on both sides remain unconfigured', () {
    final comparison = SiteImportComparison.compare(
      target: makeSite(full: false),
      incoming: makeSite(full: false),
    );

    expect(
      changeFor(comparison, 'images').kind,
      SiteImportChangeKind.unconfigured,
    );
    expect(comparison.hasChanges, isFalse);
  });

  test('site rename is detected', () {
    final comparison = SiteImportComparison.compare(
      target: makeSite(),
      incoming: makeSite(name: 'Renamed site'),
    );

    expect(changeFor(comparison, 'name').kind, SiteImportChangeKind.changed);
    expect(comparison.actionText, contains('Renamed site'));
  });

  test('tab order is significant', () {
    final original = makeSite();
    final comparison = SiteImportComparison.compare(
      target: original,
      incoming: makeSite(tabs: original.browseTabs.reversed.toList()),
    );

    expect(changeFor(comparison, 'tabs').kind, SiteImportChangeKind.changed);
    expect(comparison.hasRemovals, isFalse);
  });

  test('partial tab deletion is named in the warning', () {
    final original = makeSite();
    final comparison = SiteImportComparison.compare(
      target: original,
      incoming: makeSite(tabs: [original.browseTabs.first]),
    );

    expect(comparison.removedLabels, contains('サイト別タブ「Ranking」'));
  });

  test('comparison does not mutate sites or bundle format', () {
    final target = makeSite();
    final incoming = makeSite(full: false);
    final beforeTarget = jsonEncode(target.toJson());
    final beforeIncoming = jsonEncode(incoming.toJson());
    final beforeBundle = SiteRuleBundle.fromSite(incoming).encodeJson();

    SiteImportComparison.compare(target: target, incoming: incoming).toText();

    expect(jsonEncode(target.toJson()), beforeTarget);
    expect(jsonEncode(incoming.toJson()), beforeIncoming);
    expect(SiteRuleBundle.fromSite(incoming).encodeJson(), beforeBundle);
  });

  test('actual overwrite removes absent settings', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'site-import-comparison-',
    );
    addTearDown(() => sandbox.delete(recursive: true));

    final store = SiteRuleStore(Directory('${sandbox.path}/comics'));
    final saved = await store.importSiteBundle(incoming: makeSite());

    final updated = await store.importSiteBundle(
      incoming: makeSite(full: false),
      targetId: saved.id,
      expectedUpdatedAt: saved.updatedAt,
    );

    expect(updated.id, saved.id);
    expect(updated.images, isNull);
    expect(updated.tagNavigation, isNull);
    expect(updated.searchSettings, isNull);
    expect(updated.browseTabs, isEmpty);
    expect(updated.rules.containsKey('chapters'), isFalse);
    expect(updated.rules['works']!.paginationUrl, isEmpty);
    expect(await store.load(), hasLength(1));
  });

  testWidgets('panel fits a narrow screen with large text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SiteImportComparisonPanel(
                comparison: SiteImportComparison.compare(
                  target: makeSite(),
                  incoming: makeSite(full: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('反映内容の比較'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('site-import-removal-warning')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview and cancelled confirmation do not save', (tester) async {
    final target = makeSite();
    final store = MemorySiteStore([target]);

    await inspectBundle(tester, store, makeSite(full: false));
    await selectTarget(tester, target);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('site-bundle-apply')),
      settle: false,
    );

    expect(find.text('サイト設定を更新しますか？'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('削除される設定があります'),
      ),
      findsOneWidget,
    );

    final cancel = find.widgetWithText(TextButton, 'キャンセル');
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(store.writes, 0);
    expect(store.sites.single, same(target));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed target refreshes comparison before confirmation', (
    tester,
  ) async {
    final target = makeSite();
    final store = MemorySiteStore([target]);

    await inspectBundle(tester, store, makeSite(full: false));
    await selectTarget(tester, target);

    store.sites = [makeSite(updatedAt: DateTime.utc(2027))];

    await tapVisible(
      tester,
      find.byKey(const ValueKey('site-bundle-apply')),
      settle: false,
    );

    expect(find.byType(AlertDialog), findsNothing);
    expect(store.writes, 0);

    final notice = find.textContaining('反映先が変更または削除されました');
    await reveal(tester, notice);

    expect(notice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted target does not silently import as a new site', (
    tester,
  ) async {
    final target = makeSite();
    final store = MemorySiteStore([target]);

    await inspectBundle(tester, store, makeSite(full: false));
    await selectTarget(tester, target);

    store.sites = [];

    await tapVisible(
      tester,
      find.byKey(const ValueKey('site-bundle-apply')),
      settle: false,
    );

    expect(find.byType(AlertDialog), findsNothing);
    expect(store.writes, 0);

    final targetFinder = find.byKey(const ValueKey('site-import-target'));
    await reveal(tester, targetFinder);

    expect(tester.widget<DropdownButton<String>>(targetFinder).value, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('import UI requires an explicit import mode', (tester) async {
    final store = MemorySiteStore([makeSite()]);

    await inspectBundle(tester, store, makeSite());

    final newMode = find.byKey(const ValueKey('site-import-mode-new'));
    await reveal(tester, newMode);
    expect(tester.widget<ChoiceChip>(newMode).selected, isFalse);

    final updateMode = find.byKey(const ValueKey('site-import-mode-update'));
    await reveal(tester, updateMode);
    expect(tester.widget<ChoiceChip>(updateMode).selected, isFalse);

    final apply = find.byKey(const ValueKey('site-bundle-apply'));
    await reveal(tester, apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);

    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new mode explains separate addition and cancel does not save', (
    tester,
  ) async {
    final original = makeSite();
    final store = MemorySiteStore([original]);

    await inspectBundle(tester, store, makeSite());

    await tapVisible(
      tester,
      find.byKey(const ValueKey('site-import-mode-new')),
    );

    final notice = find.byKey(const ValueKey('site-import-new-notice'));
    await reveal(tester, notice);

    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('これは既存サイトとの比較ではありません'),
      ),
      findsOneWidget,
    );

    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('別のサイトとして追加します'),
      ),
      findsOneWidget,
    );

    final apply = find.byKey(const ValueKey('site-bundle-apply'));
    await reveal(tester, apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);

    await tapVisible(tester, apply, settle: false);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('新しいサイトとして追加しますか？'), findsOneWidget);
    expect(store.writes, 0);

    final cancel = find.widgetWithText(TextButton, 'キャンセル');
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel);

    // キャンセルするとbusyが解除されるため、ここでは終了まで待てる。
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(store.writes, 0);
    expect(store.sites.single, same(original));

    await reveal(tester, apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('update mode requires a target after switching from new', (
    tester,
  ) async {
    final store = MemorySiteStore([makeSite()]);

    await inspectBundle(tester, store, makeSite());

    await tapVisible(
      tester,
      find.byKey(const ValueKey('site-import-mode-new')),
    );

    final apply = find.byKey(const ValueKey('site-bundle-apply'));
    await reveal(tester, apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('site-import-mode-update')),
    );

    final targetFinder = find.byKey(const ValueKey('site-import-target'));
    await reveal(tester, targetFinder);
    expect(tester.widget<DropdownButton<String>>(targetFinder).value, '');

    await reveal(tester, apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);

    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected identical site displays an unchanged comparison', (
    tester,
  ) async {
    final target = makeSite();
    final store = MemorySiteStore([target]);

    await inspectBundle(tester, store, makeSite());
    await selectTarget(tester, target);

    final panelFinder = find.byType(SiteImportComparisonPanel);
    await reveal(tester, panelFinder);

    final panel = tester.widget<SiteImportComparisonPanel>(panelFinder);
    expect(panel.comparison.isNew, isFalse);
    expect(panel.comparison.targetName, target.name);
    expect(panel.comparison.hasChanges, isFalse);
    expect(panel.comparison.hasRemovals, isFalse);

    expect(
      panel.comparison.changes.where(
        (change) => change.kind == SiteImportChangeKind.unchanged,
      ),
      isNotEmpty,
    );

    final apply = find.byKey(const ValueKey('site-bundle-apply'));
    await reveal(tester, apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);

    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
