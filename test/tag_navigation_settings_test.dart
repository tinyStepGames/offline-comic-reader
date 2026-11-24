import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/page_url_template.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/tag_browse_plan.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';
import 'package:offline_comic_reader/services/work_tag_link.dart';

ListExtractionRule worksRule({
  String selector = '.normal-card',
  String pageUrl = 'https://example.com/latest/',
  String paginationUrl = '',
  String acquisition = 'staticHtml',
}) => ListExtractionRule(
  pageUrl: pageUrl,
  groupSelector: selector,
  fields: defaultListFields(),
  paginationUrl: paginationUrl,
  acquisition: acquisition,
);

SavedSiteRule sampleSite({TagNavigationSettings? settings}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'テストサイト',
  rules: {'works': worksRule()},
  updatedAt: DateTime.utc(2026, 1, 1),
  tagNavigation: settings,
);

TagNavigationSettings sampleSettings() => TagNavigationSettings(
  rule: worksRule(
    selector: '.tag-card',
    pageUrl: 'https://example.com/library/?genre=sample&page=1',
    paginationUrl: 'https://example.com/library/?genre=sample&page={page;1}',
    acquisition: 'renderedDom',
  ),
  urlPattern: r'^https://example\.com/genre/([^/?#]+)/?$',
  urlReplacement:
      r'https://example.com/library/?genre=$1&page=1&orderby=updated&order=desc',
);

void main() {
  test('専用設定は通常一覧とは別のセレクターと取得方法を保持する', () {
    final original = sampleSite(settings: sampleSettings());

    final plan = makeTagBrowsePlan(
      original,
      WorkTagLink(
        label: 'Fantasy',
        url: Uri.parse('https://example.com/genre/fantasy/'),
      ),
    );

    final rule = plan.site.rules['works']!;

    expect(original.rules['works']!.groupSelector, '.normal-card');
    expect(rule.groupSelector, '.tag-card');
    expect(rule.acquisition, 'renderedDom');
    expect(rule.kind, 'works');
    expect(Uri.parse(rule.pageUrl).queryParameters['genre'], 'fantasy');
    expect(Uri.parse(rule.pageUrl).queryParameters['orderby'], 'updated');
    expect(Uri.parse(rule.pageUrl).queryParameters['order'], 'desc');
  });

  test('タグ先の次ページでもタグ条件と更新順を維持する', () {
    final plan = makeTagBrowsePlan(
      sampleSite(settings: sampleSettings()),
      WorkTagLink(
        label: 'Seinen',
        url: Uri.parse('https://example.com/genre/seinen/'),
      ),
    );

    final pagination = PageUrlTemplate(plan.site.rules['works']!.paginationUrl);

    final next = Uri.parse(pagination.url(2));

    expect(next.path, '/library/');
    expect(next.queryParameters['genre'], 'seinen');
    expect(next.queryParameters['page'], '2');
    expect(next.queryParameters['orderby'], 'updated');
    expect(next.queryParameters['order'], 'desc');
  });

  test('専用設定がないサイトでは通常一覧を流用する', () {
    final plan = makeTagBrowsePlan(
      sampleSite(),
      WorkTagLink(
        label: 'Fantasy',
        url: Uri.parse('https://example.com/genre/fantasy/'),
      ),
    );

    expect(plan.site.rules['works']!.groupSelector, '.normal-card');
    expect(
      plan.site.rules['works']!.pageUrl,
      'https://example.com/genre/fantasy/',
    );
  });

  test('変換設定が空ならタグURLをそのまま使用する', () {
    final target = tagNavigationTargetUri(
      Uri.parse('https://example.com/genre/fantasy/#top'),
      allowedOrigin: 'https://example.com',
    );

    expect(target.toString(), 'https://example.com/genre/fantasy/');
    expect(target.hasFragment, isFalse);
  });

  test('別の取得元へのURL変換を拒否する', () {
    expect(
      () => tagNavigationTargetUri(
        Uri.parse('https://example.com/genre/fantasy/'),
        allowedOrigin: 'https://example.com',
        pattern: r'^(.*)$',
        replacement: 'https://other.example/list/',
      ),
      throwsFormatException,
    );
  });

  test('タグ先ルールの取得元が異なる場合は拒否する', () {
    final settings = TagNavigationSettings(
      rule: worksRule(pageUrl: 'https://other.example/list/'),
    );

    expect(
      () => settings.validateFor(sampleSite().rules.values),
      throwsFormatException,
    );
  });

  test('サイト保存情報のJSON往復でタグ先設定を保持する', () {
    final site = sampleSite(settings: sampleSettings());
    final restored = SavedSiteRule.fromJson(site.toJson());

    expect(restored.tagNavigation!.rule.groupSelector, '.tag-card');
    expect(restored.tagNavigation!.urlPattern, sampleSettings().urlPattern);
  });

  test('タグ先設定なしの旧サイトJSONも読み込める', () {
    final site = sampleSite();
    expect(site.toJson().containsKey('tagNavigation'), isFalse);

    final restored = SavedSiteRule.fromJson(site.toJson());

    expect(restored.tagNavigation, isNull);
    expect(restored.rules['works']!.groupSelector, '.normal-card');
  });

  test('サイト一式JSONとQRでタグ先設定を保持する', () {
    final bundle = SiteRuleBundle.fromSite(
      sampleSite(settings: sampleSettings()),
    );

    expect(bundle.toJson()['version'], 2);

    final fromJson = SiteRuleBundle.parse(bundle.encodeJson());
    final fromQr = SiteRuleBundle.parse(bundle.encodeQr());

    expect(fromJson.site.tagNavigation!.rule.groupSelector, '.tag-card');
    expect(
      fromQr.site.tagNavigation!.urlReplacement,
      sampleSettings().urlReplacement,
    );
  });

  test('タグ先設定なしの共有形式はバージョン1を維持する', () {
    final bundle = SiteRuleBundle.fromSite(sampleSite());

    expect(bundle.toJson()['version'], 1);
    expect(SiteRuleBundle.parse(bundle.encodeQr()).site.tagNavigation, isNull);
  });

  test('画面向けURL変換も別Isolateから同じ結果を返す', () async {
    final target = await resolveTagNavigationUrl(
      input: Uri.parse('https://example.com/genre/fantasy/'),
      allowedOrigin: 'https://example.com',
      pattern: sampleSettings().urlPattern,
      replacement: sampleSettings().urlReplacement,
    );

    expect(target.queryParameters['genre'], 'fantasy');
    expect(target.queryParameters['orderby'], 'updated');
  });

  test('通常一覧保存・名前変更・複製・削除操作で設定を適切に保持する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tag-navigation-test-',
    );

    try {
      final store = SiteRuleStore(Directory('${directory.path}/comics'));

      var saved = await store.save(name: 'テスト', rule: worksRule());

      saved = await store.saveTagNavigation(
        id: saved.id,
        settings: sampleSettings(),
        expectedUpdatedAt: saved.updatedAt,
      );

      saved = await store.save(
        id: saved.id,
        name: saved.name,
        rule: worksRule(selector: '.changed-normal'),
      );

      expect(saved.tagNavigation!.rule.groupSelector, '.tag-card');

      await store.rename(saved.id, '名前変更');

      var loaded = (await store.load()).single;
      expect(loaded.name, '名前変更');
      expect(loaded.tagNavigation!.rule.groupSelector, '.tag-card');

      final copy = await store.duplicate(loaded.id);
      expect(copy.tagNavigation!.rule.groupSelector, '.tag-card');
      expect(copy.id, isNot(loaded.id));

      await store.saveTagNavigation(
        id: loaded.id,
        settings: null,
        expectedUpdatedAt: loaded.updatedAt,
      );

      loaded = (await store.load()).firstWhere((site) => site.id == saved.id);

      expect(loaded.tagNavigation, isNull);
      expect(loaded.rules['works']!.groupSelector, '.changed-normal');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('編集中に変更されたサイトへの上書きを拒否する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tag-navigation-stale-test-',
    );

    try {
      final store = SiteRuleStore(Directory('${directory.path}/comics'));

      final saved = await store.save(name: 'テスト', rule: worksRule());

      await expectLater(
        store.saveTagNavigation(
          id: saved.id,
          settings: sampleSettings(),
          expectedUpdatedAt: DateTime.utc(1999),
        ),
        throwsStateError,
      );

      expect((await store.load()).single.tagNavigation, isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
