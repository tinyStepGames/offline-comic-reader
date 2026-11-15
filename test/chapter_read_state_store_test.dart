import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_read_state_store.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

void main() {
  late Directory root;
  late ChapterReadStateStore store;

  ComicChapter chapter({
    String source = 'sample',
    String language = 'ja',
    String work = 'work',
    String id = '01',
  }) => ComicChapter(
    sourceId: source,
    language: language,
    workId: work,
    id: id,
    title: '第$id話',
    url: Uri.parse('https://example.com/$language/$id'),
    storageId: '$source-$language-$work-$id',
    progressSourceId: 'example.com',
    progressChapterId: '/$language/$id',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comic-read-state-test-');
    store = ChapterReadStateStore(root);
  });

  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

  test('初期状態は未読、開くと読書中になる', () async {
    final item = chapter();
    await store.load();

    expect(store.stateOf(item), ChapterReadState.unread);

    await store.markOpened(item);

    expect(store.stateOf(item), ChapterReadState.reading);
  });

  test('読了の話を開き直しても読了を維持する', () async {
    final item = chapter();

    await store.setChapterState(item, ChapterReadState.completed);
    await store.markOpened(item);

    expect(store.stateOf(item), ChapterReadState.completed);
  });

  test('手動で未読に戻した記録を旧閲覧位置の移行で上書きしない', () async {
    final item = chapter();

    await store.markOpened(item);
    await store.setChapterState(item, ChapterReadState.unread);
    await store.importStarted(item);

    expect(store.stateOf(item), ChapterReadState.unread);
  });

  test('新しいストアから読了を復元できる', () async {
    final item = chapter();
    await store.setChapterState(item, ChapterReadState.completed);

    final restored = ChapterReadStateStore(root);
    await restored.load();

    expect(restored.stateOf(item), ChapterReadState.completed);
    restored.dispose();
  });

  test('サイト・言語・作品・話数で記録を区別する', () async {
    final original = chapter();

    await store.setChapterState(original, ChapterReadState.completed);

    expect(store.stateOf(chapter(source: 'another')), ChapterReadState.unread);
    expect(store.stateOf(chapter(language: 'en')), ChapterReadState.unread);
    expect(store.stateOf(chapter(work: 'another')), ChapterReadState.unread);
    expect(store.stateOf(chapter(id: '02')), ChapterReadState.unread);
  });

  test('保存要求が重なっても最後の指定を保持する', () async {
    final item = chapter();

    await Future.wait([
      store.markOpened(item),
      store.setChapterState(item, ChapterReadState.completed),
      store.setChapterState(item, ChapterReadState.unread),
    ]);

    expect(store.stateOf(item), ChapterReadState.unread);
  });
}
