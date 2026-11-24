import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_url_cache.dart';

void main() {
  final first = Uri.parse('https://example.com/1.jpg');
  final second = Uri.parse('https://example.com/2.jpg');
  final time = DateTime.utc(2026, 1, 1);

  test('同じキーの画像URLを再利用する', () {
    final cache = ChapterImageUrlCache();
    cache.put('a', [first], now: time);

    expect(cache.get('a', now: time), [first]);
    expect(cache.get('b', now: time), isNull);
  });

  test('3分で期限切れになる', () {
    final cache = ChapterImageUrlCache();
    cache.put('a', [first], now: time);

    expect(cache.get('a', now: time.add(const Duration(minutes: 3))), isNull);
  });

  test('参照しても有効期限を延長しない', () {
    final cache = ChapterImageUrlCache();
    cache.put('a', [first], now: time);

    expect(cache.get('a', now: time.add(const Duration(minutes: 2))), [first]);

    expect(cache.get('a', now: time.add(const Duration(minutes: 3))), isNull);
  });

  test('入力リストから独立した変更不可の一覧を返す', () {
    final cache = ChapterImageUrlCache();
    final original = [first];

    cache.put('a', original, now: time);
    original.add(second);

    final result = cache.get('a', now: time);
    expect(result, [first]);
    expect(() => result!.add(second), throwsUnsupportedError);
  });

  test('最近使っていない項目から除く', () {
    final cache = ChapterImageUrlCache(maxEntries: 2);
    cache.put('a', [first], now: time);
    cache.put('b', [first], now: time);

    cache.get('a', now: time);
    cache.put('c', [second], now: time);

    expect(cache.get('a', now: time), [first]);
    expect(cache.get('b', now: time), isNull);
    expect(cache.get('c', now: time), [second]);
  });

  test('画像URL総数の上限を守る', () {
    final cache = ChapterImageUrlCache(maxImages: 2);
    cache.put('a', [first, second], now: time);
    cache.put('b', [second], now: time);

    expect(cache.get('a', now: time), isNull);
    expect(cache.get('b', now: time), [second]);
  });

  test('空の結果は保存しない', () {
    final cache = ChapterImageUrlCache();
    cache.put('a', [], now: time);
    expect(cache.get('a', now: time), isNull);
  });

  test('時計が過去へ戻った場合は再取得する', () {
    final cache = ChapterImageUrlCache();
    cache.put('a', [first], now: time);

    expect(
      cache.get('a', now: time.subtract(const Duration(seconds: 1))),
      isNull,
    );
  });
}
