import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/chapter_details.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

ComicChapter sampleChapter(String id, {String? date}) => ComicChapter(
  sourceId: 'sample',
  language: 'ja',
  workId: 'work',
  id: id,
  title: '第$id話',
  url: Uri.parse('https://example.com/$id'),
  storageId: 'sample-$id',
  progressSourceId: 'example.com',
  progressChapterId: '/$id',
  publishedDateText: date,
);

void main() {
  test('日付がなくても表示場所のラベルを返す', () {
    expect(chapterDateLabel(sampleChapter('01')), '公開日：—');
  });

  test('サイト固有の日付形式を勝手に変換しない', () {
    final chapter = sampleChapter('01', date: '2026年11月・日付不明');

    expect(chapterDateLabel(chapter), '公開日：2026年11月・日付不明');

    expect(
      ComicChapter.fromJson(chapter.toJson()).publishedDateText,
      '2026年11月・日付不明',
    );
  });

  test('日付項目のない古いJSONも復元できる', () {
    final old = sampleChapter('01').toJson()..remove('publishedDateText');

    expect(ComicChapter.fromJson(old).publishedDateText, isNull);
  });

  test('履歴がなければ元の一覧の先頭を選ぶ', () {
    final chapters = [sampleChapter('01'), sampleChapter('02')];

    expect(readingEntryChapter(chapters, null)!.id, '01');
  });

  test('履歴があればその話を選び、なければ別の話に置き換えない', () {
    final chapters = [sampleChapter('01'), sampleChapter('02')];

    expect(readingEntryChapter(chapters, '02')!.id, '02');

    expect(readingEntryChapter(chapters, '99'), isNull);
  });
}
