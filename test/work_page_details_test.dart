import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/work_page_details.dart';
import 'package:offline_comic_reader/work_details_panel.dart';

void main() {
  final page = HtmlProbePage(
    uri: Uri.parse('https://example.com/work/1/'),
    source: '''
      <h1>English: A title<br>日本語: 日本語タイトル</h1>
      <img class="cover" src="/cover.jpg">
      <section class="description">
        English: English description
        日本語: 日本語の説明
        2行目の説明
      </section>
      <div class="genres"><a>冒険</a><a>異世界</a><a>冒険</a></div>
      <div class="chapter"><a href="/c/10">Chapter 10</a></div>
      <div class="chapter"><a href="/c/2">Chapter 2</a></div>
      <div class="chapter"><a href="/c/extra">番外編</a></div>
      <div class="chapter"><a href="/c/12">Chapter 12.5</a></div>
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

    return ListExtractionRule(
      pageUrl: page.uri.toString(),
      groupSelector: '.chapter',
      fields: fields,
      kind: 'chapters',
      details: const {
        'title': ListFieldRule(
          selector: 'h1',
          pattern: r'日本語[：:]\s*([^\r\n]+)',
          replacement: r'$1',
        ),
        'thumbnail': ListFieldRule(
          selector: '.cover',
          mode: ListValueMode.attribute,
          attribute: 'src',
        ),
        'description': ListFieldRule(
          selector: '.description',
          pattern: r'日本語[：:]\s*([\s\S]*)',
          replacement: r'$1',
        ),
        'tags': ListFieldRule(selector: '.genres a'),
        'chapterNumber': ListFieldRule(
          selector: 'a',
          pattern: r'Chapter\s*(\d+(?:\.\d+)?)',
          replacement: r'$1',
        ),
      },
    );
  }

  test('作品詳細はページ全体から取得し、日本語部分を抽出する', () async {
    final result = await extractWorkPageDetailsSafely(page, makeRule());
    expect(result.title, '日本語タイトル');
    expect(result.thumbnail.toString(), 'https://example.com/cover.jpg');
    expect(result.description, contains('日本語の説明'));
    expect(result.description, contains('2行目の説明'));
    expect(result.description, isNot(contains('English description')));
    expect(result.tags, ['冒険', '異世界']);
    expect(result.chapterNumbers, ['10', '2', '', '12.5']);
  });

  test('作品詳細設定をJSONで復元する', () {
    final rule = makeRule();
    expect(rule.toJson()['version'], 4);
    final restored = ListExtractionRule.parse(rule.encodeJson());
    expect(restored.details['title']!.pattern, rule.details['title']!.pattern);
    expect(restored.details['description']!.replacement, r'$1');
  });

  test('新しいQR形式も読める', () {
    final rule = makeRule();
    final qr =
        'ocr-list:4:${base64Url.encode(utf8.encode(jsonEncode(rule.toJson())))}';
    final restored = ListExtractionRule.parse(qr);
    expect(restored.details.keys, contains('chapterNumber'));
  });

  test('詳細未設定のルールは従来の形式を維持する', () {
    final original = makeRule();
    final rule = ListExtractionRule(
      pageUrl: original.pageUrl,
      groupSelector: original.groupSelector,
      fields: original.fields,
      kind: original.kind,
    );
    expect(rule.toJson()['version'], 3);
    expect(rule.encodeQr(), startsWith('ocr-list:3:'));
    expect(ListExtractionRule.parse(rule.encodeJson()).details, isEmpty);
  });

  test('昇順と降順は文字列順ではなく数値順', () {
    final values = ['10', '2', '', '12.5', '特別編'];
    expect(
      sortChapterItems(values, (value) => value, ChapterListOrder.ascending),
      ['2', '10', '12.5', '', '特別編'],
    );
    expect(
      sortChapterItems(values, (value) => value, ChapterListOrder.descending),
      ['12.5', '10', '2', '', '特別編'],
    );
    expect(values, ['10', '2', '', '12.5', '特別編']);
  });

  test('同じ話数は元の相対順序を保持する', () {
    final values = ['12前編', '12後編', '2'];
    final sorted = sortChapterItems(
      values,
      (value) => value.startsWith('12') ? '12' : value,
      ChapterListOrder.ascending,
    );
    expect(sorted, ['2', '12前編', '12後編']);
  });

  test('サイト順の逆順は番外編も含めて反転する', () {
    expect(
      sortChapterItems(
        ['3', '番外編', '1'],
        (value) => value,
        ChapterListOrder.reverse,
      ),
      ['1', '番外編', '3'],
    );
  });

  test('未対応の詳細項目は保存できない', () {
    final data = makeRule().toJson();
    (data['details'] as Map)['unknown'] = const ListFieldRule(
      selector: 'h1',
    ).toJson();
    expect(
      () => ListExtractionRule.parse(jsonEncode(data)),
      throwsFormatException,
    );
  });

  testWidgets('説明の展開と折りたたみができる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkDetailsPanel(
              details: WorkPageDetails(
                title: '作品タイトル',
                description: '説明1\n説明2\n説明3\n説明4\n説明5\n説明6\n説明7',
                tags: ['冒険'],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('作品タイトル'), findsOneWidget);
    expect(find.text('冒険'), findsOneWidget);
    await tester.tap(find.text('続きを読む'));
    await tester.pump();
    expect(find.text('閉じる'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
