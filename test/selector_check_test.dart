import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/selector_check.dart';

void main() {
  const source = '''
<html><body>
  <div id="details">
    <div itemprop="description">短い説明</div>

    <div itemprop="description">全文の説明</div>
  </div>
  <ul>
    <li class="work"><a href="/work/a">作品A</a></li>
    <li class="work"><a href="/work/b">作品B</a></li>
  </ul>
</body></html>
''';

  test('ID・属性・隣接関係のセレクターを照合できる', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: [
        '#details',
        '[itemprop="description"] + [itemprop="description"]',
      ],
    );

    expect(results[0]['count'], 1);
    expect(results[1]['count'], 1);
    expect(results[1]['error'], '');
    expect(results[1]['previews'], ['全文の説明']);
  });

  test('first-childと隣接関係は空白テキストに左右されない', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: ['#details > div:first-child + div'],
    );

    expect(results.single['error'], '');
    expect(results.single['previews'], ['全文の説明']);
  });

  test('まとまり内のリンクを取得できる', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: ['a'],
      scope: '.work',
      valueMode: 'attribute',
      attribute: 'href',
    );

    expect(results.single['count'], 2);
    expect(results.single['previews'], ['/work/a', '/work/b']);
  });

  test('空のセレクターはまとまり自身を表す', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: [''],
      scope: '.work',
    );

    expect(results.single['count'], 2);
    expect(results.single['error'], '');
  });

  test('一致0件をエラーとは分けて返す', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: ['.missing'],
    );

    expect(results.single['count'], 0);
    expect(results.single['error'], '');
  });

  test('位置系関数は一致0件の条件でも採用しない', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: ['.missing:nth-of-type(2)'],
    );

    expect(results.single['error'], isNotEmpty);
  });

  test('まとまりの未対応条件も検出する', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: ['a'],
      scope: 'li:nth-of-type(2)',
    );

    expect(results.single['error'], isNotEmpty);
  });

  test('不正なセレクターは確認結果にエラーを返す', () async {
    final results = await checkSelectorCandidates(
      source: source,
      selectors: ['div['],
    );

    expect(results.single['error'], isNotEmpty);
  });

  test('プレビューは先頭3件・各240文字までに制限する', () async {
    final longText = List.filled(500, 'あ').join();
    final longSource = List.filled(5, '<p>$longText</p>').join();

    final results = await checkSelectorCandidates(
      source: longSource,
      selectors: ['p'],
    );

    final previews = results.single['previews'] as List;
    expect(results.single['count'], 5);
    expect(previews.length, 3);
    expect((previews.first as String).length, 241);
  });
}
