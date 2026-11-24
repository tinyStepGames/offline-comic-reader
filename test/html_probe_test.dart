import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';

void main() {
  final page = HtmlProbePage(
    uri: Uri.parse('https://example.com/catalog/index.html'),
    source: '''
      <html><head></head><body>
        <figure>
          <a href="../comic/abc123/">
            <img src="/images/cover.jpg" data-src="/large.jpg">
          </a>
          <figcaption><a href="../comic/abc123/">作品A</a></figcaption>
        </figure>
      </body></html>
    ''',
    bytes: 100,
  );

  test('文字列を抽出する', () {
    final result = extractProbeValues(
      page: page,
      selector: 'figcaption a',
      mode: HtmlValueMode.text,
    );
    expect(result.matchedCount, 1);
    expect(result.values, ['作品A']);
  });

  test('hrefを絶対URLへ変換する', () {
    final result = extractProbeValues(
      page: page,
      selector: 'figcaption a',
      mode: HtmlValueMode.attribute,
      attribute: 'href',
    );
    expect(result.values, ['https://example.com/comic/abc123/']);
  });

  test('任意の属性と未定義属性を取得する', () {
    expect(
      extractProbeValues(
        page: page,
        selector: 'img',
        mode: HtmlValueMode.attribute,
        attribute: 'data-src',
      ).values,
      ['https://example.com/large.jpg'],
    );

    expect(
      extractProbeValues(
        page: page,
        selector: 'img',
        mode: HtmlValueMode.attribute,
        attribute: 'missing',
      ).values,
      [''],
    );
  });

  test('innerHTMLを取得する', () {
    expect(
      extractProbeValues(
        page: page,
        selector: 'figcaption',
        mode: HtmlValueMode.innerHtml,
      ).values.single,
      contains('<a'),
    );
  });

  test('表示上限を設けても総一致件数を保持する', () {
    final large = HtmlProbePage(
      uri: page.uri,
      source: List.filled(250, '<p>test</p>').join(),
      bytes: 100,
    );

    final result = extractProbeValues(
      page: large,
      selector: 'p',
      mode: HtmlValueMode.text,
    );

    expect(result.matchedCount, 250);
    expect(result.values.length, 200);
  });

  test('不正な取得URLを拒否する', () {
    for (final url in [
      'file:///test.html',
      'http://example.com/',
      'https://user:pass@example.com/',
      'not-a-url',
    ]) {
      expect(() => htmlProbeUri(url), throwsFormatException);
    }
  });

  test('UTF-8を読み取り未対応文字コードを拒否する', () {
    expect(
      decodeProbeHtml(utf8.encode('<p>日本語</p>'), 'text/html'),
      contains('日本語'),
    );

    expect(
      () => decodeProbeHtml(
        utf8.encode('<p>test</p>'),
        'text/html; charset=Shift_JIS',
      ),
      throwsFormatException,
    );
  });
}
