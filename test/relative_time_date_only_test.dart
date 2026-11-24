import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';

void main() {
  final page = HtmlProbePage(
    uri: Uri.parse('https://example.com/list/'),
    source: '''
      <div class="card" data-id="2 hours ago">
        <a href="/work/one">2 hours ago</a>
        <span class="date">2 hours ago</span>
        <span class="latest">2 hours ago</span>
      </div>
    ''',
    bytes: 1,
  );

  ListExtractionRule makeRule() {
    final fields = defaultListFields();

    // 以前の設定で他項目がONだった場合も再現する。
    fields['title'] = const ListFieldRule(
      selector: 'a',
      localizeRelativeTime: true,
    );
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
      localizeRelativeTime: true,
    );
    fields['id'] = const ListFieldRule(
      mode: ListValueMode.attribute,
      attribute: 'data-id',
      localizeRelativeTime: true,
    );
    fields['date'] = const ListFieldRule(
      selector: '.date',
      localizeRelativeTime: true,
    );
    fields['latestChapter'] = const ListFieldRule(
      selector: '.latest',
      localizeRelativeTime: true,
    );

    return ListExtractionRule(
      pageUrl: page.uri.toString(),
      groupSelector: '.card',
      fields: fields,
    );
  }

  test('日本語化するのは公開日などだけ', () {
    final row = extractListRows(page, makeRule()).rows.single;

    expect(row.values['date'], '2時間前');
    expect(row.values['title'], '2 hours ago');
    expect(row.values['id'], '2 hours ago');
    expect(row.values['latestChapter'], '2 hours ago');
    expect(row.values['url'], 'https://example.com/work/one');
    expect(row.issues, isEmpty);
  });

  test('JSONから復元した設定も公開日などだけ日本語化する', () {
    final restored = ListExtractionRule.parse(makeRule().encodeJson());
    final row = extractListRows(page, restored).rows.single;

    expect(row.values['date'], '2時間前');
    expect(row.values['title'], '2 hours ago');
    expect(row.values['latestChapter'], '2 hours ago');
    expect(row.issues, isEmpty);
  });

  test('別処理の一覧テストでも公開日などだけ日本語化する', () async {
    final report = await extractListRowsSafely(page, makeRule());
    expect(report.rows.single.values['date'], '2時間前');
    expect(report.rows.single.values['latestChapter'], '2 hours ago');
  });
}
