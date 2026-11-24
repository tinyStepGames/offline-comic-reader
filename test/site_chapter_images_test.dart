import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

void main() {
  late Directory sandbox;
  late Directory comics;
  late SiteRuleStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('site-images-test-');
    comics = Directory('${sandbox.path}/comics');
    store = SiteRuleStore(comics);
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  ListExtractionRule listRule({
    String kind = 'works',
    String selector = '.card',
    String origin = 'https://example.com',
  }) => ListExtractionRule(
    pageUrl: '$origin/list/',
    groupSelector: selector,
    fields: defaultListFields(),
    kind: kind,
  );

  ChapterImageSettings settings({
    String acquisition = 'staticHtml',
    String origin = 'https://example.com',
  }) => ChapterImageSettings(
    pageUrl: '$origin/chapter/sample/',
    acquisition: acquisition,
    rule: const ChapterImageRule(
      selector: '#reader img',
      attribute: 'data-src',
    ),
  );

  test('旧サイト設定は本文画像未設定として読み込める', () async {
    await store.save(name: 'サイトA', rule: listRule());

    final site = (await store.load()).single;
    expect(site.images, isNull);
    expect(site.toJson().containsKey('images'), isFalse);
  });

  test('本文画像設定を別インスタンスでも復元できる', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());

    await store.saveImages(id: site.id, settings: settings());

    final restored = (await SiteRuleStore(comics).load()).single;
    expect(restored.images!.pageUrl, 'https://example.com/chapter/sample/');
    expect(restored.images!.acquisition, 'staticHtml');
    expect(restored.images!.rule.selector, '#reader img');
    expect(restored.images!.rule.attribute, 'data-src');
  });

  test('表示後HTMLの取得方式も保存する', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());

    await store.saveImages(
      id: site.id,
      settings: settings(acquisition: 'renderedDom'),
    );

    expect((await store.load()).single.images!.acquisition, 'renderedDom');
  });

  test('作品一覧更新・チャプター追加でも本文画像設定を失わない', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());
    await store.saveImages(id: site.id, settings: settings());

    await store.save(
      id: site.id,
      name: 'サイトA',
      rule: listRule(selector: '.new-card'),
    );

    await store.save(
      id: site.id,
      name: 'サイトA',
      rule: listRule(kind: 'chapters', selector: '.chapter'),
    );

    final updated = (await store.load()).single;
    expect(updated.images!.rule.attribute, 'data-src');
    expect(updated.rules['works']!.groupSelector, '.new-card');
    expect(updated.rules['chapters']!.groupSelector, '.chapter');
  });

  test('本文画像保存でも作品一覧・チャプター一覧を失わない', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());

    await store.save(
      id: site.id,
      name: 'サイトA',
      rule: listRule(kind: 'chapters'),
    );
    await store.saveImages(id: site.id, settings: settings());

    expect((await store.load()).single.rules.keys.toSet(), {
      'works',
      'chapters',
    });
  });

  test('名前変更・複製でも本文画像設定を維持する', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());
    await store.saveImages(id: site.id, settings: settings());
    await store.rename(site.id, '変更後');

    final copy = await store.duplicate(site.id);
    expect(copy.images!.rule.selector, '#reader img');
    expect(copy.id, isNot(site.id));

    final original = (await store.load()).firstWhere(
      (value) => value.id == site.id,
    );
    expect(original.name, '変更後');
    expect(original.images!.rule.attribute, 'data-src');
  });

  test('別サイトへの誤保存は拒否し、既存設定を維持する', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());
    await store.saveImages(id: site.id, settings: settings());

    await expectLater(
      store.saveImages(
        id: site.id,
        settings: settings(origin: 'https://other.example'),
      ),
      throwsFormatException,
    );

    expect(
      (await store.load()).single.images!.pageUrl,
      'https://example.com/chapter/sample/',
    );
  });

  test('一覧の取得元を変更して本文画像との対応を壊す更新は拒否する', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());
    await store.saveImages(id: site.id, settings: settings());

    await expectLater(
      store.save(
        id: site.id,
        name: 'サイトA',
        rule: listRule(origin: 'https://other.example'),
      ),
      throwsFormatException,
    );

    expect(
      (await store.load()).single.rules['works']!.pageUrl,
      'https://example.com/list/',
    );
  });

  test('設定JSONで取得方式を保持し、未対応方式は拒否する', () {
    final original = settings(acquisition: 'renderedDom');
    final restored = ChapterImageSettings.parse(original.encodeJson());
    expect(restored.acquisition, 'renderedDom');

    final invalid = original.toJson();
    invalid['acquisition'] = 'unknown';
    expect(
      () => ChapterImageSettings.parse(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  test('初回の書き換え前に既存サイト設定をバックアップする', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());
    final file = File('${sandbox.path}/_site_rules/sites.json');
    final before = await file.readAsString();

    await store.saveImages(id: site.id, settings: settings());

    final backup = File('${file.path}.before-body-rules-v1.bak');
    expect(await backup.readAsString(), before);

    await store.rename(site.id, '変更後');
    expect(await backup.readAsString(), before);
  });

  test('破損した本文画像設定を空扱いで上書きしない', () async {
    final site = await store.save(name: 'サイトA', rule: listRule());
    await store.saveImages(id: site.id, settings: settings());

    final file = File('${sandbox.path}/_site_rules/sites.json');
    final data = jsonDecode(await file.readAsString()) as Map;
    final sites = data['sites'] as List;
    final imageSettings = (sites.single as Map)['images'] as Map;
    imageSettings['acquisition'] = 'broken';
    final broken = jsonEncode(data);
    await file.writeAsString(broken);

    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.rename(site.id, '変更後'), throwsFormatException);
    expect(await file.readAsString(), broken);
  });

  test('本文画像設定の保存で漫画ファイルを変更しない', () async {
    await comics.create(recursive: true);
    final image = File('${comics.path}/existing.jpg');
    await image.writeAsBytes([1, 2, 3]);

    final site = await store.save(name: 'サイトA', rule: listRule());
    await store.saveImages(id: site.id, settings: settings());

    expect(await image.readAsBytes(), [1, 2, 3]);
  });
}
