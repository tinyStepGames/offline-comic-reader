import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';

void main() {
  final page = HtmlProbePage(
    uri: Uri.parse('https://example.com/list/'),
    source: '''
      <div class="list">
        <a class="work" id="one" href="/comic/one/"
          style="background: url('/covers/one.jpg')">作品1</a>
        <a class="work" id="two" href="/comic/two/"
          style='background: url("/covers/two.jpg")'>作品2</a>
      </div>
      <p class="outside">外側</p>
    ''',
    bytes: 1,
  );

  ListExtractionRule rule() {
    final fields = defaultListFields();
    fields['thumbnail'] = const ListFieldRule(
      mode: ListValueMode.cssUrl,
      attribute: 'style',
    );
    fields['id'] = const ListFieldRule(
      mode: ListValueMode.attribute,
      attribute: 'id',
    );

    return ListExtractionRule(
      pageUrl: page.uri.toString(),
      groupSelector: '.list > a.work',
      fields: fields,
    );
  }

  test('タイトル・リンク・背景画像・IDを同じ作品ごとに取得', () {
    final report = extractListRows(page, rule());

    expect(report.total, 2);
    expect(report.rows[0].values['title'], '作品1');
    expect(report.rows[0].values['url'], 'https://example.com/comic/one/');
    expect(
      report.rows[0].values['thumbnail'],
      'https://example.com/covers/one.jpg',
    );
    expect(report.rows[0].values['id'], 'one');
    expect(report.rows[1].values['title'], '作品2');
    expect(report.rows[1].values['id'], 'two');
    expect(report.rows[0].issues, isEmpty);
  });

  test('項目のセレクターはまとまりの内側だけを検索する', () {
    final original = rule();
    original.fields['title'] = const ListFieldRule(selector: '.outside');

    final report = extractListRows(page, original);
    expect(report.rows[0].values['title'], '');
    expect(report.rows[0].issues, isNotEmpty);
  });

  test('カード内の子要素からタイトルとリンクを取得', () {
    final nested = HtmlProbePage(
      uri: page.uri,
      source: '''
        <div class="card"><h2>名前</h2><a href="/read/">読む</a></div>
      ''',
      bytes: 1,
    );

    final fields = defaultListFields();
    fields['title'] = const ListFieldRule(selector: 'h2');
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
    );

    final report = extractListRows(
      nested,
      ListExtractionRule(
        pageUrl: page.uri.toString(),
        groupSelector: '.card',
        fields: fields,
      ),
    );

    expect(report.rows.single.values['title'], '名前');
    expect(report.rows.single.values['url'], 'https://example.com/read/');
  });

  test('一覧JSONとQR内容を往復できる', () {
    final original = rule();
    final json = ListExtractionRule.parse(original.encodeJson());
    final qr = ListExtractionRule.parse(original.encodeQr());

    expect(json.groupSelector, original.groupSelector);
    expect(qr.fields['thumbnail']!.mode, ListValueMode.cssUrl);
    expect(qr.fields['url']!.attribute, 'href');
  });

  test('取得ページと違うURLの設定ではテストしない', () {
    final original = rule();
    final different = ListExtractionRule(
      pageUrl: 'https://example.com/other/',
      groupSelector: original.groupSelector,
      fields: original.fields,
    );
    expect(() => extractListRows(page, different), throwsFormatException);
  });

  test('CSSのurl抽出と危険なリンクの拒否', () {
    expect(
      firstCssUrl('background:url(https://example.com/a.jpg)'),
      'https://example.com/a.jpg',
    );

    final invalid = HtmlProbePage(
      uri: page.uri,
      source: '<a class="work" href="javascript:alert(1)">作品</a>',
      bytes: 1,
    );

    final original = rule();
    final report = extractListRows(
      invalid,
      ListExtractionRule(
        pageUrl: page.uri.toString(),
        groupSelector: 'a.work',
        fields: original.fields,
      ),
    );

    expect(report.rows.single.values['url'], '');
    expect(report.rows.single.issues, isNotEmpty);
  });
}
