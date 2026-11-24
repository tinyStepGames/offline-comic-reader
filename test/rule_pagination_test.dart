import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/page_url_template.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

ListExtractionRule makeRule({
  String pagination = 'https://example.com/list?page={page;1}',
}) {
  final fields = defaultListFields();
  fields['title'] = const ListFieldRule(selector: 'a');
  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  return ListExtractionRule(
    pageUrl: 'https://example.com/list?page=1',
    groupSelector: '.work',
    fields: fields,
    paginationUrl: pagination,
  );
}

SavedSiteRule makeSite(ListExtractionRule rule) => SavedSiteRule(
  id: 'pagination-test',
  name: 'ページ送りテスト',
  rules: {'works': rule},
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('クエリのページ番号を置き換える', () {
    final template = PageUrlTemplate(
      'https://example.com/list?the_page={page;1}&sort=latest',
    );
    expect(template.start, 1);
    expect(template.url(3), 'https://example.com/list?the_page=3&sort=latest');
  });

  test('パス形式・0開始にも対応する', () {
    final template = PageUrlTemplate('https://example.com/page/{page;0}/');
    expect(template.start, 0);
    expect(template.url(2), 'https://example.com/page/2/');
  });

  test('ホスト内のプレースホルダーは拒否する', () {
    expect(
      () => PageUrlTemplate('https://{page;1}.example.com/list'),
      throwsFormatException,
    );
  });

  test('複数プレースホルダーは拒否する', () {
    expect(
      () => PageUrlTemplate('https://example.com/{page;1}/?page={page;1}'),
      throwsFormatException,
    );
  });

  test('別取得元のページ送りURLは拒否する', () {
    expect(
      () => makeRule(
        pagination: 'https://other.example/list?page={page;1}',
      ).validate(),
      throwsFormatException,
    );
  });

  test('フラグメント内のページ番号は拒否する', () {
    expect(
      () => PageUrlTemplate('https://example.com/list#page={page;1}'),
      throwsFormatException,
    );
  });

  test('JSONでページ送り設定を復元する', () {
    final rule = makeRule();
    final restored = ListExtractionRule.parse(rule.encodeJson());

    expect(restored.paginationUrl, rule.paginationUrl);
    expect(restored.toJson()['version'], 5);
  });

  test('小さい設定はQRでも復元できる', () {
    final rule = makeRule();
    final restored = ListExtractionRule.parse(rule.encodeQr());

    expect(restored.paginationUrl, rule.paginationUrl);
  });

  test('ページ送りなしは従来の形式を維持する', () {
    final rule = makeRule(pagination: '');
    final restored = ListExtractionRule.parse(rule.encodeJson());

    expect(rule.toJson()['version'], 3);
    expect(restored.paginationUrl, isEmpty);
  });

  test('作品詳細とページ送りを同じJSONに保存できる', () {
    final base = makeRule();
    final rule = ListExtractionRule(
      pageUrl: base.pageUrl,
      groupSelector: base.groupSelector,
      fields: base.fields,
      paginationUrl: base.paginationUrl,
      details: {'title': const ListFieldRule(selector: 'h1')},
    );

    final restored = ListExtractionRule.parse(rule.encodeJson());
    expect(restored.details['title']!.selector, 'h1');
    expect(restored.paginationUrl, base.paginationUrl);
  });

  test('旧バージョンへのページ送り設定混入を拒否する', () {
    final data = makeRule().toJson();
    data['version'] = 3;

    expect(
      () => ListExtractionRule.parse(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test('1・2・3ページ目をそれぞれのURLから取得する', () async {
    final requested = <String>[];

    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        requested.add(input);
        final number = Uri.parse(input).queryParameters['page'];
        final source =
            '<div class="work">'
            '<a href="/work/$number/">作品$number</a>'
            '</div>';

        return HtmlProbePage(
          uri: Uri.parse(input),
          source: source,
          bytes: utf8.encode(source).length,
        );
      },
    );
    addTearDown(client.close);

    final site = makeSite(makeRule());

    final first = await client.load(
      site: site,
      kind: 'works',
      cancelToken: CancelToken(),
    );
    final second = await client.load(
      site: site,
      kind: 'works',
      pageNumber: 2,
      cancelToken: CancelToken(),
    );
    final third = await client.load(
      site: site,
      kind: 'works',
      pageNumber: 3,
      cancelToken: CancelToken(),
    );

    expect(requested, [
      'https://example.com/list?page=1',
      'https://example.com/list?page=2',
      'https://example.com/list?page=3',
    ]);

    expect(first.items.single.title, '作品1');
    expect(second.items.single.title, '作品2');
    expect(third.items.single.title, '作品3');
  });

  test('ページ送り未設定ならページ番号指定を拒否する', () async {
    var fetched = false;
    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        fetched = true;
        return HtmlProbePage(uri: Uri.parse(input), source: '', bytes: 0);
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(makeRule(pagination: '')),
        kind: 'works',
        pageNumber: 2,
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );

    expect(fetched, isFalse);
  });
}
