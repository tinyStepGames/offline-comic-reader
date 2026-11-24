import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/list_text_transform.dart';

void main() {
  test('最新話の数字を表示用の文字列にする', () {
    expect(
      transformListText(
        'LastChapter: 123',
        pattern: r'(\d+)',
        replacement: r'最新第$1話',
      ),
      '最新第123話',
    );
  });

  test('小数話と複数の参照を使える', () {
    expect(
      transformListText(
        'Vol.2 Chapter 12.5',
        pattern: r'Vol\.(\d+)\s+Chapter\s+(\d+(?:\.\d+)?)',
        replacement: r'第$1巻・最新第$2話',
      ),
      '第2巻・最新第12.5話',
    );
  });

  test('正規表現が空なら変換しない', () {
    expect(
      transformListText('最終話 前編', pattern: '', replacement: r'最新第$1話'),
      '最終話 前編',
    );
  });

  test('一致全体とドル記号を使える', () {
    expect(
      transformListText('Chapter 7', pattern: r'\d+', replacement: r'$$ $0'),
      r'$ 7',
    );
  });

  test('不一致や存在しない参照はエラー', () {
    expect(
      () => transformListText('最終話', pattern: r'(\d+)', replacement: r'$1'),
      throwsFormatException,
    );
    expect(
      () => transformListText('12', pattern: r'(\d+)', replacement: r'$2'),
      throwsFormatException,
    );
  });

  test('空の取得値から話数表示を作らない', () {
    expect(
      transformListText('', pattern: r'(\d*)', replacement: r'最新第$1話'),
      '',
    );
  });

  final page = HtmlProbePage(
    uri: Uri.parse('https://example.com/list/'),
    source: '''
      <div class="card">
        <a href="/work/one">作品1</a>
        <span class="date">2026-11-15</span>
        <span class="latest">LastChapter: 123</span>
      </div>
    ''',
    bytes: 1,
  );

  ListExtractionRule makeRule() {
    final fields = defaultListFields();
    fields['title'] = const ListFieldRule(selector: 'a');
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
    );
    fields['date'] = const ListFieldRule(selector: '.date');
    fields['latestChapter'] = const ListFieldRule(
      selector: '.latest',
      pattern: r'(\d+)',
      replacement: r'最新第$1話',
    );

    return ListExtractionRule(
      pageUrl: page.uri.toString(),
      groupSelector: '.card',
      fields: fields,
    );
  }

  test('公開日と最新話を別々に取得する', () {
    final report = extractListRows(page, makeRule());
    final row = report.rows.single;

    expect(row.values['date'], '2026-11-15');
    expect(row.values['latestChapter'], '最新第123話');
    expect(row.issues, isEmpty);
  });

  test('JSONとQRに整形設定を保持する', () {
    final original = makeRule();
    for (final input in [original.encodeJson(), original.encodeQr()]) {
      final restored = ListExtractionRule.parse(input);
      expect(restored.fields['latestChapter']!.pattern, r'(\d+)');
      expect(restored.fields['latestChapter']!.replacement, r'最新第$1話');
    }
  });

  test('旧JSONと旧QRを読み込める', () {
    final data = makeRule().toJson();
    data['version'] = 1;
    final fields = data['fields'] as Map;
    fields.remove('latestChapter');

    final text = jsonEncode(data);
    final qr = 'ocr-list:1:${base64Url.encode(utf8.encode(text))}';

    for (final input in [text, qr]) {
      final restored = ListExtractionRule.parse(input);
      expect(restored.fields['latestChapter']!.enabled, isFalse);
      expect(restored.fields['title']!.selector, 'a');
    }
  });

  test('別処理による一覧テストでも同じ結果になる', () async {
    final report = await extractListRowsSafely(page, makeRule());
    expect(report.rows.single.values['latestChapter'], '最新第123話');
  });
}
