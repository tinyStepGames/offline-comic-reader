import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/page_url_template.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/site_search_plan.dart';
import 'package:offline_comic_reader/services/site_search_settings.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';
import 'package:offline_comic_reader/site_search_page.dart';

ListExtractionRule sampleWorks({String selector = '.normal'}) {
  final fields = defaultListFields();
  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  return ListExtractionRule(
    pageUrl: 'https://example.com/list/',
    groupSelector: selector,
    fields: fields,
  );
}

SiteSearchSettings sampleSearch({
  bool custom = false,
  String encoding = 'plus',
}) => SiteSearchSettings(
  urlTemplate:
      'https://example.com/search/?q={keyword}&page={page;1}&order=updated',
  spaceEncoding: encoding,
  rule: custom ? sampleWorks(selector: '.search-result') : null,
);

SavedSiteRule sampleSite({
  SiteSearchSettings? settings,
  TagNavigationSettings? tagSettings,
}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: '検索テスト',
  rules: {'works': sampleWorks()},
  updatedAt: DateTime.utc(2026, 1, 1),
  searchSettings: settings,
  tagNavigation: tagSettings,
);

void main() {
  for (final encoding in ['plus', 'percent']) {
    for (final keyword in [
      '魔法 学園',
      'C++ 入門',
      'A&B test',
      '100% 本',
      'a?b=c#d',
      '作品/タイトル',
      '{page;9} test',
      '%20 literal',
      'hello 🌟',
    ]) {
      test('$encoding方式で検索語を壊さない：$keyword', () {
        final template = SiteSearchUrlTemplate(
          'https://example.com/search/?q={keyword}&page={page;1}&fixed=1',
          spaceEncoding: encoding,
        );

        final url = template.url(keyword);
        final parsed = Uri.parse(url);

        expect(parsed.queryParameters['q'], keyword);
        expect(parsed.queryParameters['page'], '1');
        expect(parsed.queryParameters['fixed'], '1');
        expect(parsed.queryParameters.length, 3);
        expect(parsed.origin, 'https://example.com');
        expect(parsed.hasFragment, isFalse);
      });
    }
  }

  test('全角・連続スペースを1個の半角スペースに統一する', () {
    final template = SiteSearchUrlTemplate('https://example.com/?q={keyword}');

    final parsed = Uri.parse(template.url('  魔法　　学園   冒険  '));
    expect(parsed.queryParameters['q'], '魔法 学園 冒険');
  });

  test('空白統一を無効にした場合は内部のスペースを維持する', () {
    final template = SiteSearchUrlTemplate(
      'https://example.com/?q={keyword}',
      normalizeSpaces: false,
    );

    final parsed = Uri.parse(template.url('  魔法　 学園  '));
    expect(parsed.queryParameters['q'], '魔法　 学園');
  });

  test('plusとpercentの送信方式を区別する', () {
    final plus = sampleSearch().template.url('C++ book');
    final percent = sampleSearch(encoding: 'percent').template.url('C++ book');

    expect(plus, contains('C%2B%2B+book'));
    expect(percent, contains('C%2B%2B%20book'));
  });

  test('パス型URLでも空白とスラッシュを検索語としてエンコードする', () {
    final template = SiteSearchUrlTemplate(
      'https://example.com/search/{keyword}/page/{page;1}/',
    );

    final url = template.url('魔法 学園/外伝', page: 2);

    expect(url, contains('%20'));
    expect(url, contains('%2F'));
    expect(url, endsWith('/page/2/'));
    expect(Uri.parse(url).origin, 'https://example.com');
  });

  test('空の検索語を拒否する', () {
    expect(() => sampleSearch().template.url('　   '), throwsFormatException);
  });

  test('検索語をホストやクエリ名へ埋め込む設定を拒否する', () {
    expect(
      () => SiteSearchUrlTemplate('https://{keyword}.example.com/'),
      throwsFormatException,
    );
    expect(
      () => SiteSearchUrlTemplate('https://example.com/?{keyword}=x'),
      throwsFormatException,
    );
  });

  test('別の取得元の検索設定を拒否する', () {
    const settings = SiteSearchSettings(
      urlTemplate: 'https://other.example/?q={keyword}',
    );

    expect(
      () => settings.validateFor(sampleSite().rules),
      throwsFormatException,
    );
  });

  test('次ページにも検索語と固定条件が残る', () {
    final plan = makeSiteSearchPlan(
      sampleSite(settings: sampleSearch()),
      'C++ 魔法',
    );

    final template = PageUrlTemplate(plan.rules['works']!.paginationUrl);

    final next = Uri.parse(template.url(2));

    expect(next.queryParameters['q'], 'C++ 魔法');
    expect(next.queryParameters['page'], '2');
    expect(next.queryParameters['order'], 'updated');
  });

  test('検索専用セレクターを使用し通常一覧を変更しない', () {
    final original = sampleSite(settings: sampleSearch(custom: true));

    final plan = makeSiteSearchPlan(original, '魔法 学園');

    expect(original.rules['works']!.groupSelector, '.normal');
    expect(plan.rules['works']!.groupSelector, '.search-result');
    expect(plan.searchSettings, isNotNull);
  });

  test('検索結果の1ページ目と2ページ目を同じ検索語で取得する', () async {
    final requested = <Uri>[];

    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        final uri = Uri.parse(input);
        requested.add(uri);
        final page = uri.queryParameters['page'];

        final html =
            '<article class="search-result">'
            '<a href="/work/$page/">Result $page</a>'
            '</article>';

        return HtmlProbePage(
          uri: uri,
          source: html,
          bytes: utf8.encode(html).length,
        );
      },
    );

    try {
      final plan = makeSiteSearchPlan(
        sampleSite(settings: sampleSearch(custom: true)),
        '魔法 C++',
      );

      final first = await client.load(
        site: plan,
        kind: 'works',
        cancelToken: CancelToken(),
      );

      final second = await client.load(
        site: plan,
        kind: 'works',
        pageNumber: 2,
        cancelToken: CancelToken(),
      );

      expect(first.items.single.url.toString(), 'https://example.com/work/1/');
      expect(second.items.single.url.toString(), 'https://example.com/work/2/');
      expect(requested.map((uri) => uri.queryParameters['q']).toList(), [
        '魔法 C++',
        '魔法 C++',
      ]);
    } finally {
      client.close();
    }
  });

  test('サイト一式JSONとQRで検索・タグ設定を一緒に保持する', () {
    final site = sampleSite(
      settings: sampleSearch(custom: true),
      tagSettings: TagNavigationSettings(rule: sampleWorks()),
    );

    final bundle = SiteRuleBundle.fromSite(site);
    expect(bundle.toJson()['version'], 3);

    for (final encoded in [bundle.encodeJson(), bundle.encodeQr()]) {
      final restored = SiteRuleBundle.parse(encoded).site;

      expect(restored.searchSettings!.urlTemplate, sampleSearch().urlTemplate);
      expect(restored.searchSettings!.rule!.groupSelector, '.search-result');
      expect(restored.tagNavigation, isNotNull);
    }
  });

  test('検索設定のない既存JSONも読み込める', () {
    final original = sampleSite();
    final restored = SavedSiteRule.fromJson(original.toJson());

    expect(restored.searchSettings, isNull);
    expect(SiteRuleBundle.fromSite(original).toJson()['version'], 1);
  });

  test('通常一覧・名前・タグの変更後も検索設定を保持する', () async {
    final temporary = await Directory.systemTemp.createTemp('site-search-');

    try {
      final store = SiteRuleStore(Directory('${temporary.path}/comics'));
      var site = await store.save(name: 'test', rule: sampleWorks());

      site = await store.saveSearchSettings(
        id: site.id,
        settings: sampleSearch(),
        expectedUpdatedAt: site.updatedAt,
      );

      site = await store.save(
        id: site.id,
        name: site.name,
        rule: sampleWorks(selector: '.changed'),
      );

      expect(site.searchSettings, isNotNull);

      await store.rename(site.id, 'renamed');
      site = (await store.load()).single;

      site = await store.saveTagNavigation(
        id: site.id,
        settings: TagNavigationSettings(rule: sampleWorks()),
        expectedUpdatedAt: site.updatedAt,
      );

      expect(site.searchSettings, isNotNull);

      final copy = await store.duplicate(site.id);
      expect(copy.searchSettings, isNotNull);

      site = await store.saveSearchSettings(
        id: site.id,
        settings: null,
        expectedUpdatedAt: site.updatedAt,
      );

      expect(site.searchSettings, isNull);
      expect(site.tagNavigation, isNotNull);
      expect(site.rules['works']!.groupSelector, '.changed');
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('古い更新日時での検索設定上書きを拒否する', () async {
    final temporary = await Directory.systemTemp.createTemp('search-stale-');

    try {
      final store = SiteRuleStore(Directory('${temporary.path}/comics'));
      final site = await store.save(name: 'test', rule: sampleWorks());

      await expectLater(
        store.saveSearchSettings(
          id: site.id,
          settings: sampleSearch(),
          expectedUpdatedAt: DateTime.utc(1999),
        ),
        throwsStateError,
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  testWidgets('空白だけの検索は結果画面を開かず案内する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SiteSearchPage(site: sampleSite(settings: sampleSearch())),
      ),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('検索語を入力してください'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
