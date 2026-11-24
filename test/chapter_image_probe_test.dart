import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_probe.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/html_probe.dart';

HtmlProbePage makePage(String source) => HtmlProbePage(
  uri: Uri.parse('https://example.com/chapter/'),
  source: source,
  bytes: utf8.encode(source).length,
);

void main() {
  test('別Isolateで画像URLをHTML順に取得できる', () async {
    final report = await probeChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="/02.jpg">
          <img src="/01.jpg">
        </div>
      '''),
      rule: const ChapterImageRule(selector: '#reader img'),
    );

    expect(report.isUsable, isTrue);
    expect(report.images.map((uri) => uri.path).toList(), [
      '/02.jpg',
      '/01.jpg',
    ]);
  });

  test('診断内容も画面側へ返せる', () async {
    final report = await probeChapterImages(
      page: makePage('''
        <div id="reader">
          <img src="/01.jpg">
          <img>
        </div>
      '''),
      rule: const ChapterImageRule(selector: '#reader img'),
    );

    expect(report.isUsable, isFalse);
    expect(report.images.length, 1);
    expect(report.issues.single, contains('候補2'));
  });

  test('不正なセレクターの失敗を呼び出し元へ返す', () async {
    await expectLater(
      probeChapterImages(
        page: makePage('<img src="/01.jpg">'),
        rule: const ChapterImageRule(selector: 'img['),
      ),
      throwsFormatException,
    );
  });
}
