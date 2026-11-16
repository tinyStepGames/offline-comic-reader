import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_reading_order.dart';

void main() {
  List<String> ordered(List<String> values) =>
      chapterReadingOrder<String>(values, titleOf: (value) => value);

  test('取得順が逆でも1話から順番に読む', () {
    expect(ordered(['Chapter 3', 'Chapter 2', 'Chapter 1']), [
      'Chapter 1',
      'Chapter 2',
      'Chapter 3',
    ]);
  });

  test('一覧の昇順降順によらず2話の次は3話、前は1話', () {
    for (final input in [
      ['Chapter 1', 'Chapter 2', 'Chapter 3'],
      ['Chapter 3', 'Chapter 2', 'Chapter 1'],
    ]) {
      final chapters = ordered(input);
      final current = chapters.indexOf('Chapter 2');

      expect(chapters[current - 1], 'Chapter 1');
      expect(chapters[current + 1], 'Chapter 3');
    }
  });

  test('10話を2話より前に並べない', () {
    expect(ordered(['第10話', '第2話', '第1話']), ['第1話', '第2話', '第10話']);
  });

  test('全角数字と小数の話数を扱う', () {
    expect(ordered(['第３話', '第２．５話', '第２話']), ['第２話', '第２．５話', '第３話']);
  });

  test('番号不明の番外編は後ろに置き、取得順を維持する', () {
    expect(ordered(['番外編B', '第2話', '番外編A', '第1話']), [
      '第1話',
      '第2話',
      '番外編B',
      '番外編A',
    ]);
  });

  test('設定で抽出した話数をタイトルより優先する', () {
    final values = [(title: '後編', number: '2'), (title: '前編', number: '1')];

    final result = chapterReadingOrder(
      values,
      titleOf: (item) => item.title,
      explicitNumberOf: (item) => item.number,
    );

    expect(result.map((item) => item.title).toList(), ['前編', '後編']);
  });

  test('別作品のチャプターを混ぜない', () {
    final values = [
      (work: 'B', title: '第1話'),
      (work: 'A', title: '第2話'),
      (work: 'B', title: '第2話'),
      (work: 'A', title: '第1話'),
    ];

    final result = chapterReadingOrder(
      values,
      titleOf: (item) => item.title,
      workKeyOf: (item) => item.work,
    );

    expect(result.map((item) => '${item.work}:${item.title}').toList(), [
      'A:第1話',
      'A:第2話',
      'B:第1話',
      'B:第2話',
    ]);
  });

  test('日付や巻数だけでは話数と判断しない', () {
    expect(chapterNumberForReading('更新日 2026-11-16'), isNull);
    expect(chapterNumberForReading('Volume 2'), isNull);
    expect(chapterNumberForReading('番外編'), isNull);
  });

  test('複数の異なる話数があるタイトルは推測しない', () {
    expect(chapterNumberForReading('第2話・第3話'), isNull);
  });

  test('元のリストを変更しない', () {
    final source = ['第3話', '第2話', '第1話'];
    ordered(source);

    expect(source, ['第3話', '第2話', '第1話']);
  });
}
