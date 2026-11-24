import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/sources/peppercarrot_adapter.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

void main() {
  test('日本語と英語を初期タブとして提供する', () {
    final adapter = PepperCarrotAdapter();
    addTearDown(adapter.close);

    expect(adapter.defaultTabs.map((tab) => tab.id), ['ja', 'en']);
  });

  test('既存英語版の保存IDと閲覧位置キーを維持する', () {
    final adapter = PepperCarrotAdapter();
    addTearDown(adapter.close);

    final chapter = adapter.parseChapter(
      'https://www.peppercarrot.com/en/webcomic/'
          'ep01_Potion-of-Flight.html',
      'Episode 1',
    );

    expect(chapter.storageId, 'peppercarrot-en-ep01');
    expect(chapter.progressSourceId, 'www.peppercarrot.com');
    expect(
      chapter.progressChapterId,
      '/en/webcomic/ep01_Potion-of-Flight.html',
    );
  });

  test('日本語版と英語版の保存先を分離する', () {
    final adapter = PepperCarrotAdapter();
    addTearDown(adapter.close);

    final chapter = adapter.parseChapter(
      'https://www.peppercarrot.com/ja/webcomic/'
          'ep01_Potion-of-Flight.html',
      '第1話',
    );

    expect(chapter.language, 'ja');
    expect(chapter.storageId, 'peppercarrot-ja-ep01');
  });

  test('タブ取得条件を保存・復元できる', () {
    const query = BrowseQuery(
      language: 'ja',
      feed: 'weekly-ranking',
      genre: 'fantasy',
      cursor: 'page-2',
    );

    final restored = BrowseQuery.fromJson(query.toJson());

    expect(restored.language, 'ja');
    expect(restored.feed, 'weekly-ranking');
    expect(restored.genre, 'fantasy');
    expect(restored.cursor, 'page-2');
  });

  test('別ホストのチャプターURLを拒否する', () {
    final adapter = PepperCarrotAdapter();
    addTearDown(adapter.close);

    expect(
      () => adapter.parseChapter(
        'https://example.com/en/webcomic/ep01_Test.html',
        'Test',
      ),
      throwsFormatException,
    );
  });
}
