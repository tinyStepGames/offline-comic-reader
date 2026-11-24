import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';

void main() {
  test('フラグメントのないURLに不要なハッシュを付けない', () {
    final uri = htmlProbeUri('https://example.com/list/');
    expect(uri.toString(), 'https://example.com/list/');
    expect(uri.hasFragment, isFalse);
  });

  test('空または文字付きのフラグメントを取り除く', () {
    for (final input in [
      'https://example.com/list/#',
      'https://example.com/list/#chapters',
    ]) {
      final uri = htmlProbeUri(input);
      expect(uri.toString(), 'https://example.com/list/');
      expect(uri.hasFragment, isFalse);
    }
  });

  test('クエリとURL内のエンコードされたハッシュは保持する', () {
    final uri = htmlProbeUri(
      'https://example.com/a%23b/?page=2&q=%23tag#chapters',
    );

    expect(uri.toString(), 'https://example.com/a%23b/?page=2&q=%23tag');
  });

  test('正規化後のURLで一覧を抽出できる', () {
    const source = '<div class="card"><a href="/work/one/">作品1</a></div>';

    final page = HtmlProbePage(
      uri: Uri.parse('https://example.com/list/'),
      source: source,
      bytes: source.length,
    );

    final fields = defaultListFields();
    fields['title'] = const ListFieldRule(selector: 'a');
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
    );

    final rule = ListExtractionRule(
      pageUrl: 'https://example.com/list/#chapters',
      groupSelector: '.card',
      fields: fields,
    );

    final report = extractListRows(page, rule);
    expect(report.rows.single.values['title'], '作品1');
    expect(report.rows.single.values['url'], 'https://example.com/work/one/');
    expect(report.rows.single.issues, isEmpty);
  });
}
