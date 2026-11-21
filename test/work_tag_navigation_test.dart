import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/tag_browse_plan.dart';
import 'package:offline_comic_reader/services/work_page_details.dart';
import 'package:offline_comic_reader/services/work_tag_link.dart';
import 'package:offline_comic_reader/work_details_panel.dart';

void main() {
  SavedSiteRule makeSite({
    String pagination = '',
    String acquisition = 'staticHtml',
  }) {
    ListExtractionRule rule(String kind) {
      final fields = defaultListFields();

      fields['title'] = const ListFieldRule(selector: 'a');

      fields['url'] = const ListFieldRule(
        selector: 'a',
        mode: ListValueMode.attribute,
        attribute: 'href',
      );

      return ListExtractionRule(
        pageUrl: kind == 'works'
            ? 'https://example.com/list/'
            : 'https://example.com/work/sample/',
        groupSelector: kind == 'works' ? '.work' : '.chapter',
        fields: fields,
        kind: kind,
        acquisition: acquisition,
        paginationUrl: kind == 'works' ? pagination : '',
        details: kind == 'chapters'
            ? const {'tags': ListFieldRule(selector: '.tags a')}
            : const {},
      );
    }

    return SavedSiteRule(
      id: 'abcdefghijklmnopqrstuv',
      name: 'テスト',
      rules: {'works': rule('works'), 'chapters': rule('chapters')},
      updatedAt: DateTime.utc(2026),
    );
  }

  WorkTagLink tag([String path = '/genre/fantasy/']) {
    return WorkTagLink(
      label: 'ファンタジー',
      url: Uri.parse('https://example.com$path'),
    );
  }

  test('タグ名と相対hrefを対応させて取得する', () async {
    final site = makeSite();

    const source = '''
      <div class="tags">
        <a href="/genre/fantasy/">ファンタジー</a>
        <a href="/genre/adventure/"><span>冒険</span></a>
        <a>リンクなし</a>
        <a href="https://other.example/tag/">外部</a>
      </div>
      <div class="chapter">
        <a href="/chapter/1/">第1話</a>
      </div>
    ''';

    final result = await extractWorkPageDetailsSafely(
      HtmlProbePage(
        uri: Uri.parse('https://example.com/work/sample/'),
        source: source,
        bytes: source.length,
      ),
      site.rules['chapters']!,
    );

    expect(result.tags, ['ファンタジー', '冒険', 'リンクなし', '外部']);

    expect(result.tagLinks.length, 2);

    expect(
      result.tagLinks.first.url.toString(),
      'https://example.com/genre/fantasy/',
    );

    expect(result.issues, isNotEmpty);
  });

  test('リンク内のspanを選んだ場合も親のhrefを取得する', () {
    final document = html.parse(
      '<a href="/genre/fantasy/">'
      '<span>ファンタジー</span>'
      '</a>',
    );

    final result = workTagLinkForElement(
      element: document.querySelector('span')!,
      label: 'ファンタジー',
      pageUri: Uri.parse('https://example.com/work/1/'),
      baseUri: Uri.parse('https://example.com/work/1/'),
    );

    expect(result!.url, tag().url);
  });

  test('単一の内側リンクも取得できる', () {
    final document = html.parse(
      '<div class="tag">'
      '<a href="/genre/fantasy/">ファンタジー</a>'
      '</div>',
    );

    final result = workTagLinkForElement(
      element: document.querySelector('.tag')!,
      label: 'ファンタジー',
      pageUri: Uri.parse('https://example.com/work/1/'),
      baseUri: Uri.parse('https://example.com/work/1/'),
    );

    expect(result!.url, tag().url);
  });

  test('複数リンクを1タグとして勝手に採用しない', () {
    final document = html.parse(
      '<div>'
      '<a href="/a">A</a>'
      '<a href="/b">B</a>'
      '</div>',
    );

    expect(
      () => workTagLinkForElement(
        element: document.querySelector('div')!,
        label: 'A B',
        pageUri: Uri.parse('https://example.com/work/1/'),
        baseUri: Uri.parse('https://example.com/work/1/'),
      ),
      throwsFormatException,
    );
  });

  test('javascriptのタグリンクは拒否する', () {
    final document = html.parse('<a href="javascript:void(0)">タグ</a>');

    expect(
      () => workTagLinkForElement(
        element: document.querySelector('a')!,
        label: 'タグ',
        pageUri: Uri.parse('https://example.com/work/1/'),
        baseUri: Uri.parse('https://example.com/work/1/'),
      ),
      throwsFormatException,
    );
  });

  test('ページ内リンクは表示専用のタグとして残す', () {
    final document = html.parse('<a href="#section">タグ</a>');

    final result = workTagLinkForElement(
      element: document.querySelector('a')!,
      label: 'タグ',
      pageUri: Uri.parse('https://example.com/work/1/'),
      baseUri: Uri.parse('https://example.com/work/1/'),
    );

    expect(result, isNull);
  });

  test('タグ用ルールを作っても元のサイト設定を変更しない', () {
    final site = makeSite();
    final original = site.rules['works']!.encodeJson();

    final plan = makeTagBrowsePlan(site, tag());

    expect(plan.site.id, site.id);

    expect(
      plan.site.rules['works']!.pageUrl,
      'https://example.com/genre/fantasy/',
    );

    expect(plan.site.rules['chapters'], site.rules['chapters']);

    expect(site.rules['works']!.encodeJson(), original);
  });

  test('クエリ方式のページ送りはタグのパスと検索条件を維持する', () {
    final site = makeSite(
      pagination: 'https://example.com/list/?the_page={page;1}',
    );

    final plan = makeTagBrowsePlan(site, tag('/genre/fantasy/?sort=latest'));

    expect(
      plan.site.rules['works']!.paginationUrl,
      'https://example.com/genre/fantasy/'
      '?sort=latest&the_page={page;1}',
    );

    expect(plan.notice, isNull);
  });

  test('パス末尾方式のページ送りをタグへ適用する', () {
    final site = makeSite(
      pagination: 'https://example.com/list/page/{page;1}/',
    );

    final plan = makeTagBrowsePlan(site, tag());

    expect(
      plan.site.rules['works']!.paginationUrl,
      'https://example.com/genre/fantasy/page/{page;1}/',
    );
  });

  test('推測できないページ送りは通常一覧へ戻さず無効化する', () {
    final site = makeSite(pagination: 'https://example.com/archive/{page;1}/');

    final plan = makeTagBrowsePlan(site, tag());

    expect(plan.site.rules['works']!.paginationUrl, isEmpty);

    expect(plan.notice, isNotNull);

    expect(
      plan.site.rules['works']!.pageUrl,
      'https://example.com/genre/fantasy/',
    );
  });

  test('別の取得元のタグは開かない', () {
    expect(
      () => makeTagBrowsePlan(
        makeSite(),
        WorkTagLink(
          label: '外部',
          url: Uri.parse('https://other.example/genre/'),
        ),
      ),
      throwsFormatException,
    );
  });

  test('表示後HTMLの設定も引き継ぐ', () {
    final plan = makeTagBrowsePlan(makeSite(acquisition: 'renderedDom'), tag());

    expect(plan.site.rules['works']!.acquisition, 'renderedDom');
  });

  test('タグ一覧の2ページ目もタグURLから取得する', () async {
    final plan = makeTagBrowsePlan(
      makeSite(pagination: 'https://example.com/list/?the_page={page;1}'),
      tag(),
    );

    String? requested;

    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        requested = input;

        const source =
            '<div class="work">'
            '<a href="/work/2/">作品2</a>'
            '</div>';

        return HtmlProbePage(
          uri: Uri.parse(input),
          source: source,
          bytes: source.length,
        );
      },
    );

    addTearDown(client.close);

    final result = await client.load(
      site: plan.site,
      kind: 'works',
      pageNumber: 2,
      cancelToken: CancelToken(),
    );

    expect(requested, 'https://example.com/genre/fantasy/?the_page=2');

    expect(result.items.single.title, '作品2');

    expect(result.items.single.url.toString(), 'https://example.com/work/2/');
  });

  testWidgets('リンク付きタグだけをタップ可能にする', (tester) async {
    WorkTagLink? selected;

    final link = tag();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkDetailsPanel(
            details: WorkPageDetails(
              tags: const ['ファンタジー', 'リンクなし'],
              tagLinks: [link],
            ),
            onTagTap: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.byType(Chip), findsOneWidget);

    await tester.tap(find.text('ファンタジー'));
    await tester.pump();

    expect(selected, same(link));
    expect(tester.takeException(), isNull);
  });
}
