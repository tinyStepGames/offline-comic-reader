import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/rule_layout_store.dart';

void main() {
  late Directory directory;
  late RuleLayoutStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rule-layout-test-');
    store = RuleLayoutStore(directory: directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('未設定のサイトはTable', () async {
    expect(await store.read('site-a'), isFalse);
  });

  test('保存したCollectionを別インスタンスでも復元できる', () async {
    await store.write('site-a', true);

    final reopened = RuleLayoutStore(directory: directory);
    expect(await reopened.read('site-a'), isTrue);
  });

  test('サイトごとに表示形式を保存する', () async {
    await store.write('site-a', true);
    await store.write('site-b', false);

    expect(await store.read('site-a'), isTrue);
    expect(await store.read('site-b'), isFalse);
  });

  test('Tableに戻した設定も復元できる', () async {
    await store.write('site-a', true);
    await store.write('site-a', false);

    final reopened = RuleLayoutStore(directory: directory);
    expect(await reopened.read('site-a'), isFalse);
  });

  test('連続保存では最後の選択を残す', () async {
    await Future.wait([
      store.write('site-a', true),
      store.write('site-a', false),
      store.write('site-a', true),
    ]);

    expect(await store.read('site-a'), isTrue);
  });

  test('保存ファイルが破損していてもTableで開ける', () async {
    await store.write('site-a', true);

    final file = await directory
        .list(recursive: true)
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .single;

    await file.writeAsString('broken json');

    expect(await store.read('site-a'), isFalse);
  });
}
