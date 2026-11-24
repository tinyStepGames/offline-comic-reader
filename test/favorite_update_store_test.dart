import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/favorite_update_store.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

void main() {
  late Directory root;
  late FavoriteUpdateStore store;

  ComicChapter chapter(String id) => ComicChapter(
    sourceId: 'sample',
    language: 'ja',
    workId: 'work',
    id: id,
    title: '第$id話',
    url: Uri.parse('https://example.com/ja/$id'),
    storageId: 'sample-ja-$id',
    progressSourceId: 'example.com',
    progressChapterId: '/ja/$id',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comic-updates-test-');
    store = FavoriteUpdateStore(root);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('初回は比較基準だけを登録し、再起動相当でも復元できる', () async {
    final result = await store.apply('work-ja', [chapter('01')]);

    expect(result, isNull);

    final restored = await FavoriteUpdateStore(root).read('work-ja');
    expect(restored!.knownIds, {'01'});
    expect(restored.newIds, isEmpty);
  });

  test('追加分だけを新着にし、再確認しても未読の新着を維持する', () async {
    await store.apply('work-ja', [chapter('01')]);

    expect(await store.apply('work-ja', [chapter('01'), chapter('02')]), 1);

    expect(await store.apply('work-ja', [chapter('01'), chapter('02')]), 0);

    expect((await store.read('work-ja'))!.newIds, {'02'});
  });

  test('開いた話だけ新着から外す', () async {
    await store.apply('work-ja', [chapter('01')]);
    await store.apply('work-ja', [chapter('01'), chapter('02'), chapter('03')]);

    await store.markRead('work-ja', '02');

    expect((await store.read('work-ja'))!.newIds, {'03'});
  });

  test('空の一覧で以前の記録を消さない', () async {
    await store.apply('work-ja', [chapter('01')]);

    await expectLater(
      store.apply('work-ja', []),
      throwsA(isA<FormatException>()),
    );

    expect((await store.read('work-ja'))!.knownIds, {'01'});
  });

  test('一度消えた既知の話が戻っても新着にしない', () async {
    await store.apply('work-ja', [chapter('01'), chapter('02')]);
    await store.apply('work-ja', [chapter('01')]);

    expect(await store.apply('work-ja', [chapter('01'), chapter('02')]), 0);

    expect((await store.read('work-ja'))!.newIds, isEmpty);
  });

  test('作品キーが違えば比較基準を分離する', () async {
    await store.apply('work-ja', [chapter('01')]);
    await store.apply('other-work', [chapter('01')]);

    await store.apply('work-ja', [chapter('01'), chapter('02')]);

    expect((await store.read('work-ja'))!.newIds, {'02'});
    expect((await store.read('other-work'))!.newIds, isEmpty);
  });
}
