import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_content_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

SavedSiteRule makeSite({
  String acquisition = 'staticHtml',
  bool withImages = true,
}) => SavedSiteRule(
  id: 'content-test',
  name: '本文取得テスト',
  rules: {
    'works': ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.work',
      fields: defaultListFields(),
    ),
  },
  images: withImages
      ? ChapterImageSettings(
          pageUrl: 'https://example.com/chapter/sample/',
          acquisition: acquisition,
          rule: const ChapterImageRule(
            selector: '#reader img',
            attribute: 'data-src',
          ),
        )
      : null,
  updatedAt: DateTime.utc(2026),
);

HtmlProbePage makePage(
  String source, {
  String url = 'https://example.com/chapter/selected/',
}) => HtmlProbePage(
  uri: Uri.parse(url),
  source: source,
  bytes: utf8.encode(source).length,
);

void main() {
  test('サンプルではなく選択チャプターURLから取得する', () async {
    String? requested;
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        requested = input;
        expect(allowedOrigin, 'https://example.com');
        return makePage('''
          <div id="reader">
            <img data-src="02.jpg">
            <img data-src="01.jpg">
          </div>
        ''');
      },
    );
    addTearDown(client.close);

    final images = await client.load(
      site: makeSite(),
      chapterUrl: 'https://example.com/chapter/selected/#view',
      cancelToken: CancelToken(),
    );

    expect(requested, 'https://example.com/chapter/selected/');
    expect(images.map((image) => image.toString()).toList(), [
      'https://example.com/chapter/selected/02.jpg',
      'https://example.com/chapter/selected/01.jpg',
    ]);
  });

  test('1枚でも空属性があれば部分成功でリーダーへ渡さない', () async {
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makePage('''
        <div id="reader">
          <img data-src="/01.jpg">
          <img>
        </div>
      '''),
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        chapterUrl: 'https://example.com/chapter/selected/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
  });

  test('画像0件ではリーダーへ渡さない', () async {
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makePage('<div id="reader"></div>'),
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        chapterUrl: 'https://example.com/chapter/selected/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
  });

  test('別取得元のチャプターへは通信しない', () async {
    var fetched = false;
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        fetched = true;
        return makePage('');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        chapterUrl: 'https://other.example/chapter/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
    expect(fetched, isFalse);
  });

  test('別取得元の転送後HTMLを採用しない', () async {
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makePage(
            '<div id="reader"><img data-src="/01.jpg"></div>',
            url: 'https://other.example/chapter/',
          ),
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        chapterUrl: 'https://example.com/chapter/selected/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
  });

  test('キャンセル済みなら通信しない', () async {
    var fetched = false;
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        fetched = true;
        return makePage('');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        chapterUrl: 'https://example.com/chapter/selected/',
        cancelToken: CancelToken()..cancel(),
      ),
      throwsStateError,
    );
    expect(fetched, isFalse);
  });

  test('取得中にキャンセルされたHTMLも採用しない', () async {
    final token = CancelToken();
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        token.cancel();
        return makePage('<div id="reader"><img data-src="/01.jpg"></div>');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        chapterUrl: 'https://example.com/chapter/selected/',
        cancelToken: token,
      ),
      throwsStateError,
    );
  });

  test('表示後HTML方式では専用の取得処理へ渡す', () async {
    final client = RuleContentClient();
    addTearDown(client.close);
    String? requested;

    final images = await client.load(
      site: makeSite(acquisition: 'renderedDom'),
      chapterUrl: 'https://example.com/chapter/selected/',
      cancelToken: CancelToken(),
      renderedFetcher:
          (
            input, {
            required cancelToken,
            required allowedOrigin,
            required groupSelector,
          }) async {
            requested = input;
            expect(groupSelector, '#reader img');
            expect(allowedOrigin, 'https://example.com');
            return makePage('<div id="reader"><img data-src="/01.jpg"></div>');
          },
    );

    expect(requested, 'https://example.com/chapter/selected/');
    expect(images.single.path, '/01.jpg');
  });

  test('本文画像未設定なら通信前に拒否する', () async {
    var fetched = false;
    final client = RuleContentClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        fetched = true;
        return makePage('');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(withImages: false),
        chapterUrl: 'https://example.com/chapter/selected/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
    expect(fetched, isFalse);
  });
}
