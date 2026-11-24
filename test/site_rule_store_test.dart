import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

void main() {
  late Directory sandbox;
  late Directory comics;
  late SiteRuleStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('site-rule-store-');
    comics = Directory('${sandbox.path}/comics');
    store = SiteRuleStore(comics);
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  ListExtractionRule rule({String kind = 'works', String selector = '.card'}) =>
      ListExtractionRule(
        pageUrl: 'https://example.com/list/',
        groupSelector: selector,
        fields: defaultListFields(),
        kind: kind,
      );

  test('初回は空', () async {
    expect(await store.load(), isEmpty);
  });

  test('名前付き保存と別インスタンスからの復元', () async {
    final saved = await store.save(name: 'サイトA', rule: rule());
    final restored = await SiteRuleStore(comics).load();

    expect(restored.single.id, saved.id);
    expect(restored.single.name, 'サイトA');
    expect(restored.single.rules['works']!.groupSelector, '.card');
  });

  test('同じサイトの作品一覧とチャプター一覧を別々に保持', () async {
    final saved = await store.save(name: 'サイトA', rule: rule());

    await store.save(
      id: saved.id,
      name: 'サイトA',
      rule: rule(kind: 'chapters', selector: '.chapter'),
    );

    final site = (await store.load()).single;
    expect(site.rules['works']!.groupSelector, '.card');
    expect(site.rules['chapters']!.groupSelector, '.chapter');

    await store.save(
      id: saved.id,
      name: 'サイトA',
      rule: rule(selector: '.new-card'),
    );

    final updated = (await store.load()).single;
    expect(updated.rules['works']!.groupSelector, '.new-card');
    expect(updated.rules['chapters']!.groupSelector, '.chapter');
  });

  test('名前変更で設定を失わない', () async {
    final saved = await store.save(name: 'サイトA', rule: rule());
    await store.rename(saved.id, 'サイトB');

    final site = (await store.load()).single;
    expect(site.name, 'サイトB');
    expect(site.rules['works']!.groupSelector, '.card');
  });

  test('複製は別IDとなり、元の設定を残す', () async {
    final saved = await store.save(name: 'サイトA', rule: rule());
    final copy = await store.duplicate(saved.id);

    expect(copy.id, isNot(saved.id));
    expect(copy.name, 'サイトA（複製）');
    expect((await store.load()).length, 2);

    await store.delete(copy.id);
    expect((await store.load()).single.id, saved.id);
  });

  test('複数インスタンスからの同時保存で取りこぼさない', () async {
    final other = SiteRuleStore(comics);

    await Future.wait([
      store.save(name: 'サイトA', rule: rule()),
      other.save(name: 'サイトB', rule: rule()),
    ]);

    expect((await store.load()).map((site) => site.name).toSet(), {
      'サイトA',
      'サイトB',
    });
  });

  test('空の名前や存在しない保存先は拒否する', () async {
    await expectLater(
      store.save(name: '  ', rule: rule()),
      throwsFormatException,
    );
    await expectLater(
      store.save(id: 'missing', name: 'サイトA', rule: rule()),
      throwsStateError,
    );
    expect(await store.load(), isEmpty);
  });

  test('破損した保存情報を空扱いで上書きしない', () async {
    await store.save(name: 'サイトA', rule: rule());

    final file = File('${sandbox.path}/_site_rules/sites.json');
    await file.writeAsString('broken-json');

    await expectLater(store.load(), throwsFormatException);
    await expectLater(
      store.save(name: 'サイトB', rule: rule()),
      throwsFormatException,
    );
    expect(await file.readAsString(), 'broken-json');
  });

  test('サイト設定の削除では漫画保存フォルダーを変更しない', () async {
    await comics.create(recursive: true);
    final image = File('${comics.path}/sample.jpg');
    await image.writeAsBytes([1, 2, 3]);

    final saved = await store.save(name: 'サイトA', rule: rule());
    await store.delete(saved.id);

    expect(await store.load(), isEmpty);
    expect(await image.readAsBytes(), [1, 2, 3]);
  });

  test('日本語化と正規表現の設定を保持する', () async {
    final fields = defaultListFields();
    fields['date'] = const ListFieldRule(
      selector: '.date',
      localizeRelativeTime: true,
    );
    fields['latestChapter'] = const ListFieldRule(
      selector: '.latest',
      pattern: r'(\d+)',
      replacement: r'最新第$1話',
    );

    await store.save(
      name: 'サイトA',
      rule: ListExtractionRule(
        pageUrl: 'https://example.com/list/',
        groupSelector: '.card',
        fields: fields,
      ),
    );

    final restored = (await store.load()).single.rules['works']!;
    expect(restored.fields['date']!.localizeRelativeTime, isTrue);
    expect(restored.fields['latestChapter']!.pattern, r'(\d+)');
    expect(restored.fields['latestChapter']!.replacement, r'最新第$1話');
  });
}
