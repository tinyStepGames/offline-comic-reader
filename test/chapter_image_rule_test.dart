import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/html_probe.dart';

HtmlProbePage makePage(
  String source, {
  String url = 'https://example.com/work/chapter-1/',
}) => HtmlProbePage(
  uri: Uri.parse(url),
  source: source,
  bytes: utf8.encode(source).length,
);

void main() {
  const rule = ChapterImageRule(selector: '#reader img');

  test('HTML順を維持し、ファイル名で並べ替えない', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="/images/10.jpg">
          <img src="/images/2.jpg">
          <img src="/images/1.jpg">
        </div>
      '''),
      rule: rule,
    );

    expect(report.images.map((uri) => uri.path).toList(), [
      '/images/10.jpg',
      '/images/2.jpg',
      '/images/1.jpg',
    ]);
    expect(report.isUsable, isTrue);
  });

  test('本文の外にある広告・表紙は取得しない', () {
    final report = extractChapterImages(
      page: makePage('''
        <img src="/advertisement.jpg">
        <div id="reader"><img src="/page-1.jpg"></div>
        <img src="/cover.jpg">
      '''),
      rule: rule,
    );

    expect(report.matchedCount, 1);
    expect(report.images.single.path, '/page-1.jpg');
  });

  test('相対URLを取得ページ基準で解決する', () {
    final report = extractChapterImages(
      page: makePage('<div id="reader"><img src="01.jpg"></div>'),
      rule: rule,
    );

    expect(
      report.images.single.toString(),
      'https://example.com/work/chapter-1/01.jpg',
    );
  });

  test('base hrefを相対URL解決に使う', () {
    final report = extractChapterImages(
      page: makePage('''
        <html>
          <head><base href="https://cdn.example.com/pages/"></head>
          <body><div id="reader"><img src="01.webp"></div></body>
        </html>
      '''),
      rule: rule,
    );

    expect(
      report.images.single.toString(),
      'https://cdn.example.com/pages/01.webp',
    );
  });

  test('data-srcは明示して使い、srcへ勝手に切り替えない', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="/placeholder.gif" data-src="/real-page.jpg">
        </div>
      '''),
      rule: const ChapterImageRule(
        selector: '#reader img',
        attribute: 'data-src',
      ),
    );

    expect(report.images.single.path, '/real-page.jpg');
    expect(report.isUsable, isTrue);
  });

  test('署名などのクエリ文字列・エンコードを保持する', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="https://cdn.example.com/a%23b.webp?token=a%2Bb&amp;expires=123#view">
        </div>
      '''),
      rule: rule,
    );

    expect(
      report.images.single.toString(),
      'https://cdn.example.com/a%23b.webp?token=a%2Bb&expires=123',
    );
  });

  test('完全に同じURLのみ最初の1件を残す', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="/page.jpg?v=1">
          <img src="/page.jpg?v=1#duplicate">
          <img src="/page.jpg?v=2">
        </div>
      '''),
      rule: rule,
    );

    expect(report.matchedCount, 3);
    expect(report.images.length, 2);
    expect(report.duplicateCount, 1);
    expect(report.isUsable, isTrue);
  });

  test('空属性が1つでもあれば正常扱いにしない', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="/page-1.jpg">
          <img>
          <img src="/page-3.jpg">
        </div>
      '''),
      rule: rule,
    );

    expect(report.images.length, 2);
    expect(report.issues.single, contains('候補2'));
    expect(report.isUsable, isFalse);
  });

  test('HTTP・data・javascript・認証情報付きURLを拒否する', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="http://example.com/page.jpg">
          <img src="data:image/png;base64,abc">
          <img src="javascript:alert(1)">
          <img src="https://user:password@example.com/page.jpg">
        </div>
      '''),
      rule: rule,
    );

    expect(report.images, isEmpty);
    expect(report.issues.length, 4);
    expect(report.isUsable, isFalse);
  });

  test('HTTPSの別ドメイン・拡張子なしURLにも対応する', () {
    final report = extractChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="//cdn.example.com/image?id=123">
        </div>
      '''),
      rule: rule,
    );

    expect(
      report.images.single.toString(),
      'https://cdn.example.com/image?id=123',
    );
    expect(report.isUsable, isTrue);
  });

  test('0件は正常扱いにしない', () {
    final report = extractChapterImages(
      page: makePage('<div id="reader"></div>'),
      rule: rule,
    );

    expect(report.matchedCount, 0);
    expect(report.issues, isNotEmpty);
    expect(report.isUsable, isFalse);
  });

  test('不正なbase hrefは黙って無視しない', () {
    expect(
      () => extractChapterImages(
        page: makePage('''
          <base href="javascript:alert(1)">
          <div id="reader"><img src="01.jpg"></div>
        '''),
        rule: rule,
      ),
      throwsFormatException,
    );
  });

  test('srcset・styleを単一画像URLとして誤解析しない', () {
    for (final attribute in ['srcset', 'data-srcset', 'style']) {
      expect(
        () =>
            ChapterImageRule(selector: 'img', attribute: attribute).validate(),
        throwsFormatException,
      );
    }
  });

  test('本文画像ルールをJSONで復元できる', () {
    const original = ChapterImageRule(
      selector: '.reader img',
      attribute: 'data-src',
    );

    final restored = ChapterImageRule.parse(original.encodeJson());

    expect(restored.selector, original.selector);
    expect(restored.attribute, original.attribute);
  });

  test('未対応の設定項目を黙って捨てない', () {
    final data = rule.toJson();
    data['unknownSetting'] = true;

    expect(
      () => ChapterImageRule.parse(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test('画像候補2000件超は絞り込みを求める', () {
    final source =
        '<div id="reader">'
        '${List.filled(2001, '<img src="/page.jpg">').join()}'
        '</div>';

    expect(
      () => extractChapterImages(page: makePage(source), rule: rule),
      throwsFormatException,
    );
  });
}
