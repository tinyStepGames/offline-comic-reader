import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:offline_comic_reader/services/last_opened_site_store.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late LastOpenedSiteStore store;

  const siteA = 'abcdefghijklmnopqrstuv';
  const siteB = 'ABCDEFGHIJKLMNOPQRSTUV';

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('last-site-test-');
    root = Directory(p.join(temporary.path, 'comics'));
    await root.create();
    store = LastOpenedSiteStore(root);
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('未設定ならサイト一覧用のnullを返す', () async {
    expect(await store.read(), isNull);
  });

  test('別インスタンスから最後のサイトを復元できる', () async {
    await store.write(siteA);

    expect(await LastOpenedSiteStore(root).read(), siteA);
  });

  test('内蔵サイトも保存できる', () async {
    await store.write(LastOpenedSiteStore.builtinSiteId);

    expect(await store.read(), LastOpenedSiteStore.builtinSiteId);
  });

  test('連続保存は最後の選択を保持する', () async {
    final first = store.write(siteA);
    final second = LastOpenedSiteStore(root).write(siteB);

    await Future.wait([first, second]);

    expect(await store.read(), siteB);
  });

  test('壊れた設定はnullとして扱う', () async {
    final file = File(
      p.join(temporary.path, '_ui_preferences', 'last-opened-site.json'),
    );

    await file.parent.create(recursive: true);
    await file.writeAsString('{broken');

    expect(await store.read(), isNull);
  });

  test('不正な保存IDを採用しない', () async {
    final file = File(
      p.join(temporary.path, '_ui_preferences', 'last-opened-site.json'),
    );

    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': 1, 'siteId': '../invalid'}),
    );

    expect(await store.read(), isNull);
    await expectLater(store.write('../invalid'), throwsFormatException);
  });

  test('過大な設定はnullとして扱う', () async {
    final file = File(
      p.join(temporary.path, '_ui_preferences', 'last-opened-site.json'),
    );

    await file.parent.create(recursive: true);
    await file.writeAsString('A' * 5000);

    expect(await store.read(), isNull);
  });
}
