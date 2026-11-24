import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/chapter_order.dart';

void main() {
  test('昇順は取得元の並びを維持する', () {
    expect(chapterDisplayOrder([1, 2, 3], descending: false), [1, 2, 3]);
  });

  test('降順は反転するが元の配列は変更しない', () {
    final original = [1, 2, 3];

    expect(chapterDisplayOrder(original, descending: true), [3, 2, 1]);

    expect(original, [1, 2, 3]);
  });

  test('空の一覧でも動作する', () {
    expect(chapterDisplayOrder<int>([], descending: true), isEmpty);
  });

  test('サイト・言語・作品ごとに設定キーを分離する', () {
    final keys = [
      chapterSortCacheKey(sourceId: 'site-a', language: 'ja', workId: 'work-a'),
      chapterSortCacheKey(sourceId: 'site-a', language: 'en', workId: 'work-a'),
      chapterSortCacheKey(sourceId: 'site-b', language: 'ja', workId: 'work-a'),
      chapterSortCacheKey(sourceId: 'site-a', language: 'ja', workId: 'work-b'),
    ];

    expect(keys.toSet().length, 4);
  });
}
