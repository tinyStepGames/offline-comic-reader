import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/chapter_image_url_cache.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_content_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

const chapterUrl = 'https://example.com/chapter/selected/';

SavedSiteRule makeCacheTestSite({String attribute = 'data-src'}) {
  return SavedSiteRule(
    id: 'cache-isolation-test',
    name: 'キャッシュ分離テスト',
    rules: {
      'works': ListExtractionRule(
        pageUrl: 'https://example.com/list/',
        groupSelector: '.work',
        fields: defaultListFields(),
      ),
    },
    images: ChapterImageSettings(
      pageUrl: 'https://example.com/chapter/sample/',
      acquisition: 'staticHtml',
      rule: ChapterImageRule(selector: '#reader img', attribute: attribute),
    ),
    updatedAt: DateTime.utc(2026),
  );
}

HtmlProbePage makeCacheTestPage(String html) {
  return HtmlProbePage(
    uri: Uri.parse(chapterUrl),
    source: html,
    bytes: utf8.encode(html).length,
  );
}

void main() {
  const validHtml =
      '<div id="reader"><img data-src="/01.jpg" src="/02.jpg"></div>';

  test('キャッシュ未指定なら毎回取得する', () async {
    var calls = 0;

    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makeCacheTestPage(validHtml);
      },
    );
    addTearDown(client.close);

    for (var i = 0; i < 2; i++) {
      await client.load(
        site: makeCacheTestSite(),
        chapterUrl: chapterUrl,
        cancelToken: CancelToken(),
      );
    }

    expect(calls, 2);
  });

  test('明示的に渡したキャッシュは別クライアントでも再利用できる', () async {
    final cache = ChapterImageUrlCache();
    var calls = 0;

    final first = RuleContentClient(
      imageUrlCache: cache,
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makeCacheTestPage(validHtml);
      },
    );

    final second = RuleContentClient(
      imageUrlCache: cache,
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makeCacheTestPage(validHtml);
      },
    );

    addTearDown(first.close);
    addTearDown(second.close);

    final a = await first.load(
      site: makeCacheTestSite(),
      chapterUrl: chapterUrl,
      cancelToken: CancelToken(),
    );

    final b = await second.load(
      site: makeCacheTestSite(),
      chapterUrl: chapterUrl,
      cancelToken: CancelToken(),
    );

    expect(calls, 1);
    expect(b, a);
  });

  test('キャッシュ未指定の取得に別クライアントの成功結果を混ぜない', () async {
    final cachedClient = RuleContentClient(
      imageUrlCache: ChapterImageUrlCache(),
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makeCacheTestPage(validHtml),
    );

    final independentClient = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makeCacheTestPage('<div id="reader"></div>'),
    );

    addTearDown(cachedClient.close);
    addTearDown(independentClient.close);

    await cachedClient.load(
      site: makeCacheTestSite(),
      chapterUrl: chapterUrl,
      cancelToken: CancelToken(),
    );

    await expectLater(
      independentClient.load(
        site: makeCacheTestSite(),
        chapterUrl: chapterUrl,
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
  });

  test('キャッシュがあってもキャンセル済みなら拒否する', () async {
    final client = RuleContentClient(
      imageUrlCache: ChapterImageUrlCache(),
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makeCacheTestPage(validHtml),
    );
    addTearDown(client.close);

    await client.load(
      site: makeCacheTestSite(),
      chapterUrl: chapterUrl,
      cancelToken: CancelToken(),
    );

    await expectLater(
      client.load(
        site: makeCacheTestSite(),
        chapterUrl: chapterUrl,
        cancelToken: CancelToken()..cancel(),
      ),
      throwsStateError,
    );
  });

  test('失敗した抽出結果はキャッシュしない', () async {
    var calls = 0;

    final client = RuleContentClient(
      imageUrlCache: ChapterImageUrlCache(),
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makeCacheTestPage('<div id="reader"></div>');
      },
    );
    addTearDown(client.close);

    for (var i = 0; i < 2; i++) {
      await expectLater(
        client.load(
          site: makeCacheTestSite(),
          chapterUrl: chapterUrl,
          cancelToken: CancelToken(),
        ),
        throwsFormatException,
      );
    }

    expect(calls, 2);
  });

  test('画像ルール変更後は取り直す', () async {
    var calls = 0;

    final client = RuleContentClient(
      imageUrlCache: ChapterImageUrlCache(),
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makeCacheTestPage(validHtml);
      },
    );
    addTearDown(client.close);

    final a = await client.load(
      site: makeCacheTestSite(),
      chapterUrl: chapterUrl,
      cancelToken: CancelToken(),
    );

    final b = await client.load(
      site: makeCacheTestSite(attribute: 'src'),
      chapterUrl: chapterUrl,
      cancelToken: CancelToken(),
    );

    expect(calls, 2);
    expect(a.single.path, '/01.jpg');
    expect(b.single.path, '/02.jpg');
  });
}
