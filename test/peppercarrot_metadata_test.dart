import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/sources/peppercarrot_adapter.dart';
import 'package:offline_comic_reader/sources/peppercarrot_metadata.dart';

void main() {
  test('日本語の公開日キャプションから日付を取得する', () {
    expect(pepperCarrotPublishedDate('公開日: 2023-04-26。'), '2023-04-26');
  });

  test('英語ラベルでも同じ日付形式を取得する', () {
    expect(pepperCarrotPublishedDate('Published: 2023-04-26.'), '2023-04-26');
  });

  test('日付なし・非対応形式は推測しない', () {
    expect(pepperCarrotPublishedDate(null), isNull);
    expect(pepperCarrotPublishedDate(''), isNull);
    expect(pepperCarrotPublishedDate('近日公開'), isNull);
    expect(pepperCarrotPublishedDate('04/26/2023'), isNull);
  });

  test('存在しない日付は取り込まない', () {
    expect(pepperCarrotPublishedDate('2023-02-29'), isNull);
    expect(pepperCarrotPublishedDate('2023-04-31'), isNull);
    expect(pepperCarrotPublishedDate('2024-02-29'), '2024-02-29');
  });

  test('日付が複数ある場合は推測しない', () {
    expect(pepperCarrotPublishedDate('公開 2023-04-26 / 更新 2023-05-01'), isNull);
  });

  test('日付を復元しても保存ID・閲覧位置キーは変えない', () {
    final adapter = PepperCarrotAdapter();

    try {
      final chapter = adapter.parseChapter(
        'https://www.peppercarrot.com/ja/webcomic/ep38_The-Healer.html',
        'エピソード 38: ヒーラー',
        publishedDateText: '2023-04-26',
      );

      final restored = adapter.restoreChapter({'chapter': chapter.toJson()});

      expect(restored, isNotNull);
      expect(restored!.publishedDateText, '2023-04-26');
      expect(restored.storageId, chapter.storageId);
      expect(restored.progressSourceId, chapter.progressSourceId);
      expect(restored.progressChapterId, chapter.progressChapterId);
    } finally {
      adapter.close();
    }
  });
}
