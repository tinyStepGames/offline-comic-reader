import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/saved_download_repository.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

class _OfflineAdapter extends SourceAdapter {
  @override
  String get id => 'sample';

  @override
  String get name => 'Sample';

  @override
  List<SourceTab> get defaultTabs => [];

  @override
  Future<List<SourceTab>> discoverTabs() async =>
      throw StateError('このテストでは通信しません');

  @override
  Future<List<ComicWork>> fetchWorks(BrowseQuery query) async =>
      throw StateError('このテストでは通信しません');

  @override
  Future<List<ComicChapter>> fetchChapters(
    ComicWork work,
    BrowseQuery query,
  ) async => throw StateError('このテストでは通信しません');

  @override
  Future<ChapterContent> fetchContent(ComicChapter chapter) async =>
      throw StateError('このテストでは通信しません');

  @override
  ComicChapter? restoreChapter(Map<String, dynamic> data) => null;

  @override
  void close() {}
}

void main() {
  late Directory root;
  late DownloadStore store;
  late SavedDownloadRepository repository;

  Future<ComicChapter> fixture(String id, {String language = 'ja'}) async {
    final chapter = ComicChapter(
      sourceId: 'sample',
      language: language,
      workId: 'work',
      id: id,
      title: '第$id話',
      url: Uri.parse('https://example.com/$language/$id'),
      storageId: 'sample-$language-$id',
      progressSourceId: 'example.com',
      progressChapterId: '/$language/$id',
    );

    final folder = store.directory(chapter);
    await folder.create(recursive: true);

    // 保存情報・ファイル存在確認用。画像デコードのテストではない。
    await File(p.join(folder.path, '0000.jpg')).writeAsBytes([1, 2, 3, 4]);

    await File(p.join(folder.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'version': 2,
        'episodeId': chapter.storageId,
        'title': chapter.title,
        'sourceUrl': chapter.url.toString(),
        'chapter': chapter.toJson(),
        'complete': true,
        'pages': ['0000.jpg'],
      }),
    );

    return chapter;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('saved-comic-test-');
    store = DownloadStore(root);
    repository = SavedDownloadRepository(store, _OfflineAdapter());
  });

  tearDown(() async {
    store.close();
    await root.delete(recursive: true);
  });

  test('保存完了話を通信なしで取得し、容量を集計する', () async {
    final chapter = await fixture('01');
    final scan = await repository.scan();

    var expected = 0;
    await for (final entry in store.directory(chapter).list()) {
      if (entry is File) expected += await entry.length();
    }

    expect(scan.chapters.length, 1);
    expect(scan.bytes, expected);
    expect(scan.issues, isEmpty);
  });

  test('保存情報のない未完了フォルダは一覧へ出さない', () async {
    final pending = Directory(p.join(root.path, 'pending'));
    await pending.create();
    await File(p.join(pending.path, '0000.jpg.part')).writeAsBytes([1]);

    expect((await repository.scan()).chapters, isEmpty);
  });

  test('不足ファイルのある話は正常な保存済みとして扱わない', () async {
    final chapter = await fixture('01');
    await File(p.join(store.directory(chapter).path, '0000.jpg')).delete();

    final scan = await repository.scan();

    expect(scan.chapters, isEmpty);
    expect(scan.issues.length, 1);
  });

  test('選択した話だけ削除し、別の話と管理データを残す', () async {
    final first = await fixture('01');
    final second = await fixture('02');

    final marker = File(p.join(root.path, '_library', 'keep.txt'));
    await marker.parent.create(recursive: true);
    await marker.writeAsString('お気に入り・履歴等の管理領域');

    final scan = await repository.scan();
    final target = scan.chapters.firstWhere(
      (item) => item.chapter.id == first.id,
    );

    await repository.deleteChapter(target);

    expect(await store.directory(first).exists(), isFalse);
    expect(await store.directory(second).exists(), isTrue);
    expect(await marker.exists(), isTrue);
  });

  test('言語が異なる保存済み作品は別グループになる', () async {
    final ja = await fixture('01');
    final en = await fixture('01', language: 'en');

    expect(savedWorkKey(ja), isNot(savedWorkKey(en)));
    expect((await repository.scan()).chapters.length, 2);
  });
}
