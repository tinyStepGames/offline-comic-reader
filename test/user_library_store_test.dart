import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/user_library_store.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

void main() {
  late Directory root;
  late UserLibraryStore store;

  const ja = SourceTab('ja', '日本語', BrowseQuery(language: 'ja'));
  const en = SourceTab('en', 'English', BrowseQuery(language: 'en'));

  final work = ComicWork(
    id: 'sample',
    title: 'サンプル作品',
    url: Uri.parse('https://example.com/work'),
  );

  ComicChapter chapter(String id) => ComicChapter(
    sourceId: 'sample-source',
    language: 'ja',
    workId: 'sample',
    id: id,
    title: '第$id話',
    url: Uri.parse('https://example.com/ja/$id'),
    storageId: 'sample-ja-$id',
    progressSourceId: 'example.com',
    progressChapterId: '/ja/$id',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comic-library-test-');
    store = UserLibraryStore(root);
  });

  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

  test('お気に入りを保存し、新しいストアから復元できる', () async {
    await store.toggleFavorite('sample-source', ja, work);

    final restored = UserLibraryStore(root);
    await restored.load();

    expect(restored.isFavorite('sample-source', ja, work), isTrue);
    restored.dispose();
  });

  test('サイトと言語を区別し、お気に入りを解除できる', () async {
    await store.toggleFavorite('sample-source', ja, work);
    await store.toggleFavorite('sample-source', en, work);
    await store.toggleFavorite('another-source', ja, work);

    expect(store.favorites.length, 3);

    await store.toggleFavorite('sample-source', ja, work);

    expect(store.favorites.length, 2);
    expect(store.isFavorite('sample-source', ja, work), isFalse);
    expect(store.isFavorite('sample-source', en, work), isTrue);
    expect(store.isFavorite('another-source', ja, work), isTrue);
  });

  test('同じ作品の履歴は最新の1話だけ残る', () async {
    await store.remember('sample-source', ja, work, chapter('01'));
    await store.remember('sample-source', ja, work, chapter('02'));
    await store.remember('sample-source', ja, work, chapter('01'));

    expect(store.history.length, 1);
    expect(store.history.first.chapter!.id, '01');

    final restored = UserLibraryStore(root);
    await restored.load();

    expect(restored.history.first.chapter!.id, '01');
    restored.dispose();
  });

  test('履歴を消しても、お気に入りは残る', () async {
    await store.toggleFavorite('sample-source', ja, work);
    await store.remember('sample-source', ja, work, chapter('01'));

    await store.clearHistory('sample-source');

    expect(store.history, isEmpty);
    expect(store.favorites.length, 1);
  });
}
