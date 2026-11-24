import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/page_url_template.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/site_search_plan.dart';
import 'package:offline_comic_reader/services/site_search_settings.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';

ListExtractionRule makeRule(
  String selector, {
  String acquisition = 'staticHtml',
}) => ListExtractionRule(
  pageUrl: 'https://example.com/library/',
  groupSelector: selector,
  fields: defaultListFields(),
  acquisition: acquisition,
);

SavedSiteRule makeSite({bool withTags = true, bool withSearchRule = false}) =>
    SavedSiteRule(
      id: 'AAAAAAAAAAAAAAAAAAAAAA',
      name: '検索ルール優先順位テスト',
      updatedAt: DateTime.utc(2026, 1, 1),
      rules: {'works': makeRule('.normal-card')},
      tagNavigation: withTags
          ? TagNavigationSettings(
              rule: makeRule('.tag-card', acquisition: 'renderedDom'),
              urlPattern: r'^(.*)$',
              urlReplacement: 'https://example.com/unused-tag-url/',
            )
          : null,
      searchSettings: SiteSearchSettings(
        urlTemplate:
            'https://example.com/library/'
            '?search_term={keyword}&the_page={page;1}',
        rule: withSearchRule ? makeRule('.search-card') : null,
      ),
    );

void main() {
  test('検索専用ルールなしならタグ先ルールを使用する', () {
    final original = makeSite();
    final plan = makeSiteSearchPlan(original, 'mahou gakuen');

    expect(plan.rules['works']!.groupSelector, '.tag-card');
    expect(plan.rules['works']!.acquisition, 'renderedDom');

    expect(original.rules['works']!.groupSelector, '.normal-card');

    final uri = Uri.parse(plan.rules['works']!.pageUrl);
    expect(uri.path, '/library/');
    expect(uri.queryParameters['search_term'], 'mahou gakuen');

    // タグのURL変換は検索URLには適用しない。
    expect(uri.path, isNot('/unused-tag-url/'));
  });

  test('タグ先ルールなしなら通常一覧を使用する', () {
    final plan = makeSiteSearchPlan(makeSite(withTags: false), 'mahou');

    expect(plan.rules['works']!.groupSelector, '.normal-card');
  });

  test('検索専用ルールがあれば最優先にする', () {
    final plan = makeSiteSearchPlan(
      makeSite(withSearchRule: true),
      'mahou gakuen',
    );

    expect(plan.rules['works']!.groupSelector, '.search-card');
  });

  test('タグ先ルール使用時も次ページに検索語を維持する', () {
    final plan = makeSiteSearchPlan(makeSite(), 'mahou gakuen no');

    final pagination = PageUrlTemplate(plan.rules['works']!.paginationUrl);

    final next = Uri.parse(pagination.url(2));

    expect(next.queryParameters['search_term'], 'mahou gakuen no');
    expect(next.queryParameters['the_page'], '2');
  });
}
