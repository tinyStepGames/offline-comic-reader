import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/page_url_template.dart';
import 'package:offline_comic_reader/services/site_browse_tab.dart';
import 'package:offline_comic_reader/services/site_browse_tab_plan.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/site_search_settings.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';
import 'package:offline_comic_reader/site_browse_tabs_view.dart';

ListExtractionRule ruleFor(
  String selector, {
  String acquisition = 'staticHtml',
}) => ListExtractionRule(
  pageUrl: 'https://example.com/list/',
  groupSelector: selector,
  fields: defaultListFields(),
  acquisition: acquisition,
);

SiteBrowseTab tabFor({
  String id = 'popular',
  String title = '人気',
  String source = 'works',
  ListExtractionRule? custom,
}) => SiteBrowseTab(
  id: id,
  title: title,
  pageUrl: 'https://example.com/library/?sort=popular&page=1',
  paginationUrl: 'https://example.com/library/?sort=popular&page={page;1}',
  ruleSource: source,
  customRule: custom,
);

SavedSiteRule siteFor({
  List<SiteBrowseTab> tabs = const [],
  bool withTags = true,
}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'タブテスト',
  updatedAt: DateTime.utc(2026, 1, 1),
  rules: {'works': ruleFor('.normal')},
  tagNavigation: withTags
      ? TagNavigationSettings(
          rule: ruleFor('.tags', acquisition: 'renderedDom'),
        )
      : null,
  searchSettings: const SiteSearchSettings(
    urlTemplate: 'https://example.com/?q={keyword}',
  ),
  browseTabs: tabs,
);

void main() {
  test('通常一覧の抽出ルールを使いURLだけタブ用にする', () {
    final original = siteFor(tabs: [tabFor()]);
    final plan = makeSiteBrowseTabPlan(original, original.browseTabs.single);

    expect(plan.rules['works']!.groupSelector, '.normal');
    expect(
      Uri.parse(plan.rules['works']!.pageUrl).queryParameters['sort'],
      'popular',
    );
    expect(original.rules['works']!.pageUrl, 'https://example.com/list/');
    expect(plan.searchSettings, isNotNull);
    expect(plan.browseTabs.length, 1);
  });

  test('タグ先ルールのセレクターと取得方法を使う', () {
    final tab = tabFor(source: 'tags');
    final plan = makeSiteBrowseTabPlan(siteFor(tabs: [tab]), tab);

    expect(plan.rules['works']!.groupSelector, '.tags');
    expect(plan.rules['works']!.acquisition, 'renderedDom');
  });

  test('タグ先が未設定なら通常一覧へ戻る', () {
    final tab = tabFor(source: 'tags');
    final plan = makeSiteBrowseTabPlan(
      siteFor(tabs: [tab], withTags: false),
      tab,
    );

    expect(plan.rules['works']!.groupSelector, '.normal');
  });

  test('タブ専用ルールを使用する', () {
    final tab = tabFor(source: 'custom', custom: ruleFor('.custom'));

    final plan = makeSiteBrowseTabPlan(siteFor(tabs: [tab]), tab);
    expect(plan.rules['works']!.groupSelector, '.custom');
  });

  test('ページ送りでタブの並び順条件を維持する', () {
    final tab = tabFor();
    final plan = makeSiteBrowseTabPlan(siteFor(tabs: [tab]), tab);
    final next = Uri.parse(
      PageUrlTemplate(plan.rules['works']!.paginationUrl).url(2),
    );

    expect(next.queryParameters['page'], '2');
    expect(next.queryParameters['sort'], 'popular');
  });

  test('他サイトのタブURLを拒否する', () {
    const tab = SiteBrowseTab(
      id: 'foreign',
      title: '別サイト',
      pageUrl: 'https://other.example/list/',
    );

    expect(() => tab.validateFor(siteFor().rules), throwsFormatException);
  });

  test('タブIDの重複を拒否する', () {
    expect(
      () => SiteBrowseTab.validateList([tabFor(), tabFor()], siteFor().rules),
      throwsFormatException,
    );
  });

  test('専用指定なのに専用ルールがない設定を拒否する', () {
    expect(() => tabFor(source: 'custom').validate(), throwsFormatException);
  });

  test('タブなしの既存サイトJSONを読み込める', () {
    final site = siteFor();
    final restored = SavedSiteRule.fromJson(site.toJson());

    expect(restored.browseTabs, isEmpty);
  });

  test('サイト一式JSONとQRでタブ・検索・タグを保持する', () {
    final site = siteFor(tabs: [tabFor()]);
    final bundle = SiteRuleBundle.fromSite(site);

    expect(bundle.toJson()['version'], 4);

    for (final encoded in [bundle.encodeJson(), bundle.encodeQr()]) {
      final restored = SiteRuleBundle.parse(encoded).site;

      expect(restored.browseTabs.single.title, '人気');
      expect(restored.searchSettings, isNotNull);
      expect(restored.tagNavigation, isNotNull);
    }
  });

  test('保存・名前変更・通常一覧変更・検索変更・複製でもタブを保持する', () async {
    final temporary = await Directory.systemTemp.createTemp('site-tabs-');

    try {
      final store = SiteRuleStore(Directory('${temporary.path}/comics'));
      var site = await store.save(name: 'test', rule: ruleFor('.normal'));

      site = await store.saveBrowseTabs(
        id: site.id,
        tabs: [tabFor()],
        expectedUpdatedAt: site.updatedAt,
      );

      await store.rename(site.id, 'renamed');

      site = await store.save(
        id: site.id,
        name: 'renamed',
        rule: ruleFor('.changed'),
      );

      expect(site.browseTabs.single.id, 'popular');

      site = await store.saveSearchSettings(
        id: site.id,
        settings: const SiteSearchSettings(
          urlTemplate: 'https://example.com/?q={keyword}',
        ),
        expectedUpdatedAt: site.updatedAt,
      );

      expect(site.browseTabs.single.title, '人気');

      final copy = await store.duplicate(site.id);
      expect(copy.browseTabs.single.title, '人気');

      site = await store.saveBrowseTabs(
        id: site.id,
        tabs: [],
        expectedUpdatedAt: site.updatedAt,
      );

      expect(site.browseTabs, isEmpty);
      expect(site.rules['works']!.groupSelector, '.changed');
      expect(site.searchSettings, isNotNull);
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('古い更新日時でタブ設定を上書きできない', () async {
    final temporary = await Directory.systemTemp.createTemp('site-tabs-stale-');

    try {
      final store = SiteRuleStore(Directory('${temporary.path}/comics'));
      final site = await store.save(name: 'test', rule: ruleFor('.normal'));

      await expectLater(
        store.saveBrowseTabs(
          id: site.id,
          tabs: [tabFor()],
          expectedUpdatedAt: DateTime.utc(1999),
        ),
        throwsStateError,
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  testWidgets('タブを押すと選んだ一覧の設定へ切り替わる', (tester) async {
    final tabs = [
      tabFor(source: 'tags'),
      tabFor(
        id: 'ranking',
        title: 'ランキング',
        source: 'custom',
        custom: ruleFor('.ranking'),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: SiteBrowseTabsView(
          site: siteFor(tabs: tabs),
          pageBuilder: (context, site, header) => Scaffold(
            appBar: AppBar(title: const Text('テスト'), bottom: header),
            body: Text(
              site.rules['works']!.groupSelector,
              key: const ValueKey('active-selector'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('.normal'), findsOneWidget);
    expect(find.text('.tags'), findsNothing);

    await tester.tap(find.text('人気'));
    await tester.pumpAndSettle();

    expect(find.text('.tags'), findsOneWidget);
    expect(find.text('.normal'), findsNothing);

    await tester.tap(find.text('ランキング'));
    await tester.pumpAndSettle();

    expect(find.text('.ranking'), findsOneWidget);
    expect(find.text('.tags'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
