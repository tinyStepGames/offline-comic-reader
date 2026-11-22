import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_browse_tab.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/site_search_settings.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';

ListExtractionRule completeRule({
  required String pageUrl,
  String kind = 'works',
  String group = '.work',
  String acquisition = 'renderedDom',
  String pagination = '',
  bool withDetails = false,
}) {
  final fields = defaultListFields();

  fields['title'] = const ListFieldRule(selector: '.title');

  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  fields['thumbnail'] = const ListFieldRule(
    selector: 'img.cover',
    mode: ListValueMode.attribute,
    attribute: 'src',
  );

  fields['latestChapter'] = const ListFieldRule(
    selector: '.latest',
    pattern: r'(\d+)',
    replacement: r'最新第$1話',
  );

  fields['date'] = const ListFieldRule(
    selector: '.date',
    enabled: true,
    localizeRelativeTime: true,
  );

  return ListExtractionRule(
    pageUrl: pageUrl,
    kind: kind,
    acquisition: acquisition,
    groupSelector: group,
    fields: fields,
    paginationUrl: pagination,
    details: withDetails
        ? {
            'title': const ListFieldRule(
              selector: 'h1',
              pattern: r'日本語[：:]\s*([^\r\n]+)',
              replacement: r'$1',
            ),
            'description': const ListFieldRule(selector: '.description'),
            'thumbnail': const ListFieldRule(
              selector: 'img.main-cover',
              mode: ListValueMode.attribute,
              attribute: 'src',
            ),
            'tags': const ListFieldRule(selector: 'a.tag'),
          }
        : {},
  );
}

SavedSiteRule completeSite() {
  return SavedSiteRule(
    id: 'AAAAAAAAAAAAAAAAAAAAAA',
    name: '設定一式の往復テスト',
    updatedAt: DateTime.utc(2026, 11, 21),
    rules: {
      'works': completeRule(
        pageUrl: 'https://example.com/list/',
        pagination: 'https://example.com/list/?page={page;1}',
      ),
      'chapters': completeRule(
        pageUrl: 'https://example.com/work/sample/',
        kind: 'chapters',
        group: '.chapter',
        acquisition: 'staticHtml',
        withDetails: true,
      ),
    },
    images: const ChapterImageSettings(
      pageUrl: 'https://example.com/chapter/sample/',
      acquisition: 'staticHtml',
      rule: ChapterImageRule(selector: '#reader img', attribute: 'data-src'),
    ),
    tagNavigation: TagNavigationSettings(
      rule: completeRule(
        pageUrl: 'https://example.com/tags/?genre=action',
        group: '.tag-work',
        pagination: 'https://example.com/tags/?genre=action&page={page;1}',
      ),
      urlPattern: r'^https://example\.com/genre/([^/?#]+)/?$',
      urlReplacement: r'https://example.com/tags/?genre=$1',
    ),
    searchSettings: SiteSearchSettings(
      urlTemplate: 'https://example.com/search/?q={keyword}&page={page;1}',
      spaceEncoding: 'percent',
      rule: completeRule(
        pageUrl: 'https://example.com/search/?q=sample',
        group: '.search-work',
        acquisition: 'staticHtml',
      ),
    ),
    browseTabs: [
      const SiteBrowseTab(
        id: 'latest',
        title: '最新',
        pageUrl: 'https://example.com/latest/',
        paginationUrl: 'https://example.com/latest/?page={page;1}',
      ),
      const SiteBrowseTab(
        id: 'genres',
        title: 'ジャンル',
        pageUrl: 'https://example.com/tags/?genre=action',
        ruleSource: 'tags',
      ),
      SiteBrowseTab(
        id: 'ranking',
        title: 'ランキング',
        pageUrl: 'https://example.com/ranking/',
        ruleSource: 'custom',
        customRule: completeRule(
          pageUrl: 'https://example.com/ranking/',
          group: '.rank-work',
          acquisition: 'staticHtml',
        ),
      ),
    ],
  );
}

void verifyCompleteSettings(SiteRuleBundle restored) {
  final site = restored.site;

  expect(restored.toJson()['version'], 4);
  expect(site.rules.keys.toSet(), {'works', 'chapters'});

  expect(site.rules['works']!.acquisition, 'renderedDom');
  expect(site.rules['chapters']!.acquisition, 'staticHtml');

  expect(
    site.rules['works']!.paginationUrl,
    'https://example.com/list/?page={page;1}',
  );

  expect(site.rules['works']!.fields['latestChapter']!.replacement, r'最新第$1話');

  expect(site.rules['works']!.fields['date']!.localizeRelativeTime, isTrue);

  expect(
    site.rules['chapters']!.details['title']!.pattern,
    r'日本語[：:]\s*([^\r\n]+)',
  );

  expect(site.rules['chapters']!.details['tags']!.selector, 'a.tag');

  expect(site.images!.acquisition, 'staticHtml');
  expect(site.images!.rule.selector, '#reader img');
  expect(site.images!.rule.attribute, 'data-src');

  expect(
    site.tagNavigation!.urlPattern,
    r'^https://example\.com/genre/([^/?#]+)/?$',
  );

  expect(
    site.tagNavigation!.urlReplacement,
    r'https://example.com/tags/?genre=$1',
  );

  expect(
    site.tagNavigation!.rule.paginationUrl,
    'https://example.com/tags/?genre=action&page={page;1}',
  );

  expect(site.searchSettings!.spaceEncoding, 'percent');
  expect(site.searchSettings!.rule!.groupSelector, '.search-work');

  expect(
    Uri.parse(
      site.searchSettings!.template.url('mahou gakuen'),
    ).queryParameters['q'],
    'mahou gakuen',
  );

  expect(
    Uri.parse(
      site.searchSettings!.template.url('魔法 学園 & +'),
    ).queryParameters['q'],
    '魔法 学園 & +',
  );

  expect(site.browseTabs.map((tab) => tab.title).toList(), [
    '最新',
    'ジャンル',
    'ランキング',
  ]);

  expect(site.browseTabs.map((tab) => tab.ruleSource).toList(), [
    'works',
    'tags',
    'custom',
  ]);

  expect(site.browseTabs.last.customRule!.groupSelector, '.rank-work');

  expect(
    site.browseTabs.first.paginationUrl,
    'https://example.com/latest/?page={page;1}',
  );
}

void main() {
  test('全機能を含むサイト一式がJSONで欠落せず往復する', () {
    final original = SiteRuleBundle.fromSite(completeSite());

    final restored = SiteRuleBundle.parse(original.encodeJson());

    expect(restored.toJson(), original.toJson());
    verifyCompleteSettings(restored);
  });

  test('全機能を含むサンプル設定が1枚用QRデータで往復する', () {
    final original = SiteRuleBundle.fromSite(completeSite());
    final payload = original.encodeQr();

    expect(payload, startsWith(SiteRuleBundle.prefix));
    expect(payload.length, lessThanOrEqualTo(SiteRuleBundle.maxQrCharacters));

    final restored = SiteRuleBundle.parse(payload);

    expect(restored.toJson(), original.toJson());
    verifyCompleteSettings(restored);
  });

  test('共有JSONの最上位項目をサイト設定のみに限定する', () {
    final data = SiteRuleBundle.fromSite(completeSite()).toJson();

    expect(data.keys.toSet(), {
      'format',
      'version',
      'name',
      'rules',
      'images',
      'tagNavigation',
      'searchSettings',
      'browseTabs',
    });

    for (final key in [
      'id',
      'updatedAt',
      'cookies',
      'history',
      'favorites',
      'readingProgress',
      'openedChapters',
      'imageUrlCache',
      'downloads',
    ]) {
      expect(data.containsKey(key), isFalse, reason: key);
    }
  });

  test('個人データ用の最上位項目が混ざったJSONを拒否する', () {
    final data = SiteRuleBundle.fromSite(completeSite()).toJson();

    for (final key in [
      'cookies',
      'history',
      'favorites',
      'readingProgress',
      'openedChapters',
      'imageUrlCache',
      'downloads',
    ]) {
      expect(
        () => SiteRuleBundle.parse(jsonEncode({...data, key: []})),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('従来のバージョン1から4も読み込める', () {
    final all = SiteRuleBundle.fromSite(completeSite()).toJson();

    for (final version in [1, 2, 3, 4]) {
      final data = Map<String, dynamic>.from(all);
      data['version'] = version;

      if (version < 4) data.remove('browseTabs');
      if (version < 3) data.remove('searchSettings');
      if (version < 2) data.remove('tagNavigation');

      final restored = SiteRuleBundle.parse(jsonEncode(data));

      expect(restored.site.images, isNotNull);
      expect(restored.site.rules.length, 2);
      expect(restored.site.tagNavigation != null, version >= 2);
      expect(restored.site.searchSettings != null, version >= 3);
      expect(restored.site.browseTabs.isNotEmpty, version >= 4);
    }
  });

  test('新規追加・更新・再読み込みでも全設定を保持する', () async {
    final root = await Directory.systemTemp.createTemp('complete-site-bundle-');

    addTearDown(() => root.delete(recursive: true));

    final store = SiteRuleStore(Directory('${root.path}/comics'));

    final original = SiteRuleBundle.fromSite(completeSite());
    final incoming = SiteRuleBundle.parse(original.encodeJson()).site;

    final first = await store.importSiteBundle(incoming: incoming);
    final second = await store.importSiteBundle(incoming: incoming);

    expect(first.id, isNot(second.id));

    expect(SiteRuleBundle.fromSite(first).toJson(), original.toJson());

    final updated = await store.importSiteBundle(
      incoming: incoming,
      targetId: first.id,
      expectedUpdatedAt: first.updatedAt,
    );

    expect(updated.id, first.id);

    final loaded = await store.load();
    expect(loaded.length, 2);

    final target = loaded.singleWhere((site) => site.id == first.id);
    final untouched = loaded.singleWhere((site) => site.id == second.id);

    verifyCompleteSettings(SiteRuleBundle.fromSite(target));

    expect(SiteRuleBundle.fromSite(target).toJson(), original.toJson());

    expect(untouched.toJson(), second.toJson());
  });

  test('通常HTML確認は1回だけで全体設定と取得方式を変えない', () async {
    final bundle = SiteRuleBundle.fromSite(completeSite());
    final before = jsonEncode(bundle.toJson());
    var calls = 0;

    final result = await checkSiteBundleStatic(
      bundle,
      cancelToken: CancelToken(),
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;

        expect(input, 'https://example.com/list/?page=1');

        expect(allowedOrigin, 'https://example.com');

        const html = '''
<div class="work">
  <a href="/work/selected/"><span class="title">確認作品</span></a>
  <img class="cover" src="/cover.jpg">
  <span class="latest">12</span>
  <span class="date">2 hours ago</span>
</div>
''';

        return HtmlProbePage(
          uri: Uri.parse(input),
          source: html,
          bytes: utf8.encode(html).length,
        );
      },
    );

    expect(calls, 1);
    expect(result.items.single.title, '確認作品');
    expect(jsonEncode(bundle.toJson()), before);

    verifyCompleteSettings(bundle);
  });
}
