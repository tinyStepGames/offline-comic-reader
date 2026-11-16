import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/reading_progress.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/rule_downloads.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';
import 'package:path/path.dart' as p;

const siteA = 'AAAAAAAAAAAAAAAAAAAAAA';
const siteB = 'BBBBBBBBBBBBBBBBBBBBBB';

ComicChapter chapter({
  String siteId = siteA,
  String work = 'https://example.com/work/a/',
  String url = 'https://example.com/chapter/1/',
}) => ruleSavedChapter(
  siteId: siteId,
  workUrl: work,
  chapterUrl: url,
  title: '第1話',
);

Future<void> writeComplete(DownloadStore store, ComicChapter item) async {
  final folder = store.directory(item);
  await folder.create(recursive: true);

  // 小さなPNG。保存情報・ファイル参照のテストに使用する。
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
    'AAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );

  await File(p.join(folder.path, '0000.jpg')).writeAsBytes(png);
  await File(p.join(folder.path, 'manifest.json')).writeAsString(
    jsonEncode({
      'version': 2,
      'episodeId': item.storageId,
      'chapter': item.toJson(),
      'complete': true,
      'pages': ['0000.jpg'],
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late DownloadStore store;
  late RuleDownloads downloads;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('custom-comic-');
    store = DownloadStore(root, maxConcurrentImages: 4);
    downloads = RuleDownloads(store);
  });

  tearDown(() async {
    store.close();
    downloads.state.dispose();
    await root.delete(recursive: true);
  });

  test('フラグメントの有無で保存IDを変えない', () {
    expect(
      chapter().storageId,
      chapter(url: 'https://example.com/chapter/1/#reader').storageId,
    );
  });

  test('サイトとクエリが違う場合は別保存にする', () {
    expect(chapter().storageId, isNot(chapter(siteId: siteB).storageId));
    expect(
      chapter().storageId,
      isNot(chapter(url: 'https://example.com/chapter/1/?edition=2').storageId),
    );
  });

  test('作品URLを知らない読書画面から同じ保存IDを作れる', () {
    expect(
      chapter().storageId,
      chapter(work: 'https://example.com/chapter/1/').storageId,
    );
  });

  test('オンラインとオフラインの閲覧位置キーが一致する', () {
    final item = chapter();
    final offline = ReadingKey(
      sourceId: item.progressSourceId,
      chapterId: item.progressChapterId,
    );
    final online = ReadingKey(
      sourceId: 'custom-site:$siteA',
      chapterId: 'https://example.com/chapter/1/',
    );

    expect(offline.fileId, online.fileId);
  });

  test('不正なサイトIDと別取得元の作品URLを拒否する', () {
    expect(() => chapter(siteId: '../invalid'), throwsFormatException);
    expect(
      () => chapter(work: 'https://other.example/work/'),
      throwsFormatException,
    );
  });

  test('未保存なら通信せず空リストを返す', () async {
    expect(await downloads.files(chapter()), isEmpty);
  });

  test('保存後は別インスタンスからローカル画像を開ける', () async {
    final item = chapter();
    await writeComplete(store, item);

    final reopenedStore = DownloadStore(root);
    final reopened = RuleDownloads(reopenedStore);
    addTearDown(() {
      reopened.state.dispose();
      reopenedStore.close();
    });

    final files = await reopened.files(
      chapter(work: 'https://example.com/chapter/1/'),
    );

    expect(files, hasLength(1));
    expect(await files.single.exists(), isTrue);
  });

  test('保存済み一覧で別サイトの話を混ぜない', () async {
    await writeComplete(store, chapter());
    await writeComplete(store, chapter(siteId: siteB));

    final scan = await downloads.scan(siteA);

    expect(scan.chapters, hasLength(1));
    expect(scan.chapters.single.chapter.sourceId, 'custom-site:$siteA');
    expect(scan.issues, isEmpty);
  });

  test('画像不足の保存を正常扱いしない', () async {
    final item = chapter();
    await writeComplete(store, item);
    await File(p.join(store.directory(item).path, '0000.jpg')).delete();

    await expectLater(downloads.files(item), throwsFormatException);
  });
}
