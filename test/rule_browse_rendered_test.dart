import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rendered_rule_capture.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

void main() {
  ListExtractionRule rule({
    String acquisition = 'renderedDom',
    String kind = 'works',
  }) {
    final fields = defaultListFields();
    fields['title'] = const ListFieldRule(selector: '.name');
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
    );
    fields['date'] = const ListFieldRule(
      selector: '.date',
      localizeRelativeTime: true,
    );

    return ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.item',
      fields: fields,
      acquisition: acquisition,
      kind: kind,
    );
  }

  SavedSiteRule site(ListExtractionRule template) => SavedSiteRule(
    id: 'test',
    name: 'テスト',
    rules: {template.kind: template},
    updatedAt: DateTime.utc(2026),
  );

  HtmlProbePage page(
    String input, [
    String source =
        '<div class="item"><b class="name">作品A</b>'
        '<a href="/work/a">表紙</a><a href="/work/a">詳細</a>'
        '<span class="date">2 hours ago</span></div>',
  ]) => HtmlProbePage(
    uri: Uri.parse(input),
    source: source,
    bytes: utf8.encode(source).length,
  );

  test('表示後HTML設定では専用の取得処理だけを呼ぶ', () async {
    var normalCalls = 0;
    var renderedCalls = 0;
    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        normalCalls++;
        return page(input);
      },
    );
    addTearDown(client.close);

    final result = await client.load(
      site: site(rule()),
      kind: 'works',
      cancelToken: CancelToken(),
      renderedFetcher:
          (
            input, {
            required cancelToken,
            required allowedOrigin,
            required groupSelector,
          }) async {
            renderedCalls++;
            expect(groupSelector, '.item');
            expect(allowedOrigin, 'https://example.com');
            return page(input);
          },
    );

    expect(normalCalls, 0);
    expect(renderedCalls, 1);
    expect(result.items.single.title, '作品A');
    expect(result.items.single.date, '2時間前');
    expect(result.items.single.url.toString(), 'https://example.com/work/a');
  });

  test('通常HTML設定では表示後HTMLの取得処理を呼ばない', () async {
    var normalCalls = 0;
    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        normalCalls++;
        return page(input);
      },
    );
    addTearDown(client.close);

    await client.load(
      site: site(rule(acquisition: 'staticHtml')),
      kind: 'works',
      cancelToken: CancelToken(),
      renderedFetcher:
          (
            input, {
            required cancelToken,
            required allowedOrigin,
            required groupSelector,
          }) async => throw StateError('呼ばれてはいけません'),
    );
    expect(normalCalls, 1);
  });

  test('表示後HTMLでも選択した作品URLを使う', () async {
    final client = RuleBrowseClient();
    addTearDown(client.close);
    String? requested;

    await client.load(
      site: site(rule(kind: 'chapters')),
      kind: 'chapters',
      targetUrl: 'https://example.com/work/selected/',
      cancelToken: CancelToken(),
      renderedFetcher:
          (
            input, {
            required cancelToken,
            required allowedOrigin,
            required groupSelector,
          }) async {
            requested = input;
            return page(input);
          },
    );

    expect(requested, 'https://example.com/work/selected/');
  });

  test('表示後HTMLの取得中にキャンセルされたら抽出しない', () async {
    final client = RuleBrowseClient();
    addTearDown(client.close);
    final token = CancelToken();

    await expectLater(
      client.load(
        site: site(rule()),
        kind: 'works',
        cancelToken: token,
        renderedFetcher:
            (
              input, {
              required cancelToken,
              required allowedOrigin,
              required groupSelector,
            }) async {
              token.cancel();
              return page(input);
            },
      ),
      throwsStateError,
    );
  });

  test('候補は明示指定時だけ収集し、採用結果は変えない', () async {
    final template = rule();
    final input = page(template.pageUrl);
    final normal = extractListRows(input, template);
    final detailed = await extractListRowsSafely(
      input,
      template,
      collectCandidates: true,
    );

    expect(normal.rows.single.candidates, isEmpty);
    expect(detailed.rows.single.matchCounts['url'], 2);
    expect(detailed.rows.single.candidates['url'], ['/work/a', '/work/a']);
    expect(detailed.rows.single.candidates['date'], ['2 hours ago']);
    expect(detailed.rows.single.values['date'], '2時間前');
    expect(detailed.rows.single.values, normal.rows.single.values);
  });

  test('候補は50件まで、総一致件数は保持する', () {
    final template = rule();
    final links = List.generate(
      65,
      (index) => '<a href="/$index">$index</a>',
    ).join();
    final result = extractListRows(
      page(
        template.pageUrl,
        '<div class="item"><b class="name">作品</b>$links</div>',
      ),
      template,
      collectCandidates: true,
    );

    expect(result.rows.single.matchCounts['url'], 65);
    expect(result.rows.single.candidates['url']!.length, 50);
  });

  test('表示後HTMLの別オリジンは拒否する', () {
    expect(
      () => decodeRenderedRulePage(
        jsonEncode({
          'url': 'https://other.example/list/',
          'source': '<html></html>',
        }),
        allowedOrigin: 'https://example.com',
      ),
      throwsFormatException,
    );
  });

  test('表示後HTMLの2MiB制限はUTF-8のバイト数で判定する', () {
    expect(
      () => decodeRenderedRulePage(
        jsonEncode({
          'url': 'https://example.com/list/',
          'source': List.filled(710000, 'あ').join(),
        }),
        allowedOrigin: 'https://example.com',
      ),
      throwsFormatException,
    );
  });

  test('表示後HTMLでも不要なフラグメントは除去する', () {
    final result = decodeRenderedRulePage(
      jsonEncode({
        'url': 'https://example.com/list/#chapters',
        'source': '<html></html>',
      }),
      allowedOrigin: 'https://example.com',
    );
    expect(result.uri.toString(), 'https://example.com/list/');
    expect(result.uri.hasFragment, isFalse);
  });
}
