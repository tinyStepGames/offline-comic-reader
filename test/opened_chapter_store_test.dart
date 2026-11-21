import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/opened_chapter_store.dart';

void main() {
  late Directory directory;
  late OpenedChapterStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('opened-chapter-test-');
    store = OpenedChapterStore(directoryProvider: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('未記録のサイトは空になる', () async {
    expect(await store.read(siteId: 'a'), isEmpty);
  });

  test('ストアを作り直しても記録が残る', () async {
    await store.mark(siteId: 'a', chapterUrl: 'https://example.com/chapter/1/');

    final reopened = OpenedChapterStore(
      directoryProvider: () async => directory,
    );

    expect(await reopened.read(siteId: 'a'), {
      'https://example.com/chapter/1/',
    });
  });

  test('サイトごとに記録を分ける', () async {
    await store.mark(siteId: 'a', chapterUrl: 'https://example.com/chapter/1/');

    expect(await store.read(siteId: 'b'), isEmpty);
  });

  test('フラグメントを除きクエリを保持する', () async {
    await store.mark(
      siteId: 'a',
      chapterUrl: 'https://example.com/chapter/1/?lang=ja#page2',
    );

    expect(await store.read(siteId: 'a'), {
      'https://example.com/chapter/1/?lang=ja',
    });
  });

  test('重複記録しない', () async {
    for (var i = 0; i < 2; i++) {
      await store.mark(
        siteId: 'a',
        chapterUrl: 'https://example.com/chapter/1/',
      );
    }

    expect((await store.read(siteId: 'a')).length, 1);
  });

  test('並行記録でも両方を保持する', () async {
    await Future.wait([
      store.mark(siteId: 'a', chapterUrl: 'https://example.com/chapter/1/'),
      store.mark(siteId: 'a', chapterUrl: 'https://example.com/chapter/2/'),
    ]);

    expect(await store.read(siteId: 'a'), {
      'https://example.com/chapter/1/',
      'https://example.com/chapter/2/',
    });
  });

  test('不正なURLは記録しない', () async {
    await expectLater(
      store.mark(siteId: 'a', chapterUrl: 'file:///private/image.jpg'),
      throwsFormatException,
    );

    expect(await store.read(siteId: 'a'), isEmpty);
  });

  test('破損した記録を上書きしない', () async {
    await store.mark(siteId: 'a', chapterUrl: 'https://example.com/chapter/1/');

    final file = await directory
        .list()
        .where((entry) => entry.path.endsWith('.json'))
        .cast<File>()
        .first;

    await file.writeAsString('{"version":999}');

    await expectLater(
      store.mark(siteId: 'a', chapterUrl: 'https://example.com/chapter/2/'),
      throwsFormatException,
    );

    expect(await file.readAsString(), '{"version":999}');
  });
}
