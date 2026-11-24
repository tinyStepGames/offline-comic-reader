import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/relative_time_text.dart';

void main() {
  const examples = {
    '30 seconds ago': '30秒前',
    '1 second ago': '1秒前',
    '5 minutes ago': '5分前',
    '1 minute ago': '1分前',
    '2 hours ago': '2時間前',
    '1 hour ago': '1時間前',
    '1 day ago': '1日前',
    '3 days ago': '3日前',
    '3 weeks ago': '3週間前',
    '1 week ago': '1週間前',
    '2 months ago': '2か月前',
    '1 month ago': '1か月前',
    '1 year ago': '1年前',
    '2 years ago': '2年前',
    'an hour ago': '1時間前',
    'a day ago': '1日前',
    'a month ago': '1か月前',
    'just now': 'たった今',
    '2 HOURS AGO': '2時間前',
    '  2   hours ago  ': '2時間前',
    '1.5 hours ago': '1.5時間前',
  };

  for (final entry in examples.entries) {
    test('${entry.key}を日本語にする', () {
      expect(localizeEnglishRelativeTime(entry.key), entry.value);
    });
  }

  test('未対応の表示は変更しない', () {
    for (final input in [
      '',
      '2026-11-15',
      'days ago',
      'months ago',
      'minutes ago',
      'yesterday',
      'in 2 hours',
      'Updated 2 hours ago',
      '2時間前',
      '2 hours ago / 10 comments',
    ]) {
      expect(localizeEnglishRelativeTime(input), input);
    }
  });

  test('初期状態はOFF', () {
    expect(const ListFieldRule().localizeRelativeTime, isFalse);
  });

  test('copyWithで日本語化設定を保持する', () {
    const field = ListFieldRule(localizeRelativeTime: true);
    expect(field.copyWith(selector: '.updated').localizeRelativeTime, isTrue);
    expect(
      field.copyWith(localizeRelativeTime: false).localizeRelativeTime,
      isFalse,
    );
  });

  test('項目のJSONに設定を保存して復元する', () {
    const original = ListFieldRule(localizeRelativeTime: true);
    final restored = ListFieldRule.fromJson(original.toJson());
    expect(restored.localizeRelativeTime, isTrue);
  });

  test('不正な型の日本語化設定は読み込まない', () {
    final data = const ListFieldRule().toJson();
    data['localizeRelativeTime'] = 'true';
    expect(() => ListFieldRule.fromJson(data), throwsFormatException);
  });

  final page = HtmlProbePage(
    uri: Uri.parse('https://example.com/list/'),
    source: '''
      <div class="card">
        <a href="/work/one">作品1</a>
        <span class="date">2 hours ago</span>
        <span class="latest">Chapter 123</span>
      </div>
    ''',
    bytes: 1,
  );

  ListExtractionRule makeRule({
    bool localize = true,
    String pattern = '',
    String replacement = '',
  }) {
    final fields = defaultListFields();

    fields['title'] = const ListFieldRule(selector: 'a');
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
    );
    fields['date'] = ListFieldRule(
      selector: '.date',
      localizeRelativeTime: localize,
      pattern: pattern,
      replacement: replacement,
    );
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

  test('ONの項目だけ日本語にする', () {
    final report = extractListRows(page, makeRule());
    final row = report.rows.single;
    expect(row.values['date'], '2時間前');
    expect(row.values['latestChapter'], '最新第123話');
    expect(row.issues, isEmpty);
  });

  test('OFFなら元の表示を維持する', () {
    final report = extractListRows(page, makeRule(localize: false));
    expect(report.rows.single.values['date'], '2 hours ago');
  });

  test('日本語化してから正規表現とテンプレートを適用する', () {
    final report = extractListRows(
      page,
      makeRule(pattern: r'^(\d+)時間前$', replacement: r'更新：$1時間前'),
    );

    expect(report.rows.single.values['date'], '更新：2時間前');
    expect(report.rows.single.issues, isEmpty);
  });

  test('新しいJSONとQRに日本語化設定を保存する', () {
    final rule = makeRule();
    expect(rule.toJson()['version'], 3);
    expect(rule.encodeQr().startsWith('ocr-list:3:'), isTrue);

    for (final input in [rule.encodeJson(), rule.encodeQr()]) {
      final restored = ListExtractionRule.parse(input);
      expect(restored.fields['date']!.localizeRelativeTime, isTrue);
      expect(
        extractListRows(page, restored).rows.single.values['date'],
        '2時間前',
      );
    }
  });

  test('旧バージョン1と2のJSON・QRを読み込む', () {
    for (final version in [1, 2]) {
      final data = makeRule(localize: false).toJson();
      data['version'] = version;

      final fields = data['fields'] as Map;
      for (final value in fields.values) {
        (value as Map).remove('localizeRelativeTime');
      }
      if (version == 1) fields.remove('latestChapter');

      final text = jsonEncode(data);
      final qr =
          'ocr-list:$version:'
          '${base64Url.encode(utf8.encode(text))}';

      for (final input in [text, qr]) {
        final restored = ListExtractionRule.parse(input);
        expect(restored.fields['date']!.localizeRelativeTime, isFalse);
        expect(
          extractListRows(page, restored).rows.single.values['date'],
          '2 hours ago',
        );
      }
    }
  });

  test('別処理の一覧テストでも日本語化できる', () async {
    final report = await extractListRowsSafely(page, makeRule());
    expect(report.rows.single.values['date'], '2時間前');
  });
}
