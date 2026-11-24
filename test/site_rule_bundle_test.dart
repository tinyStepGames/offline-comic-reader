import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

ListExtractionRule sampleRule(
  String kind, {
  String acquisition = 'renderedDom',
  String? pageUrl,
}) {
  final fields = defaultListFields();

  fields['title'] = const ListFieldRule(selector: 'a');

  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  fields['date'] = const ListFieldRule(
    selector: '.date',
    enabled: true,
    localizeRelativeTime: true,
  );

  fields['latestChapter'] = const ListFieldRule(
    selector: '.latest',
    pattern: r'(\d+)',
    replacement: r'最新第$1話',
  );

  return ListExtractionRule(
    pageUrl:
        pageUrl ??
        (kind == 'works'
            ? 'https://example.com/list/'
            : 'https://example.com/work/sample/'),
    kind: kind,
    acquisition: acquisition,
    groupSelector: '.entry',
    fields: fields,
    paginationUrl: kind == 'works'
        ? 'https://example.com/list/?page={page;1}'
        : '',
    details: kind == 'chapters'
        ? {
            'description': const ListFieldRule(selector: '.description'),
            'tags': const ListFieldRule(selector: '.tag'),
          }
        : {},
  );
}

SavedSiteRule sampleSite({String? worksUrl}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'テストサイト',
  updatedAt: DateTime.utc(2026, 11, 17),
  rules: {
    'works': sampleRule('works', pageUrl: worksUrl),
    'chapters': sampleRule('chapters'),
  },
  images: const ChapterImageSettings(
    pageUrl: 'https://example.com/chapter/1/',
    acquisition: 'renderedDom',
    rule: ChapterImageRule(selector: '.reader img', attribute: 'data-src'),
  ),
);

void main() {
  test('JSONと1枚のQRでサイト設定一式を復元できる', () {
    final bundle = SiteRuleBundle.fromSite(sampleSite());

    for (final encoded in [bundle.encodeJson(), bundle.encodeQr()]) {
      final restored = SiteRuleBundle.parse(encoded);

      expect(restored.toJson(), bundle.toJson());

      expect(
        restored.site.rules['chapters']!.details['tags']!.selector,
        '.tag',
      );

      expect(
        restored.site.rules['works']!.fields['date']!.localizeRelativeTime,
        isTrue,
      );

      expect(
        restored.site.rules['works']!.fields['latestChapter']!.replacement,
        r'最新第$1話',
      );

      expect(restored.site.images!.rule.attribute, 'data-src');

      expect(restored.site.images!.acquisition, 'renderedDom');
    }
  });

  test('移植データに保存先ID・日時・個人データを含めない', () {
    final data = SiteRuleBundle.fromSite(sampleSite()).toJson();

    expect(data.keys.toSet(), {'format', 'version', 'name', 'rules', 'images'});

    expect(data.containsKey('id'), isFalse);
    expect(data.containsKey('updatedAt'), isFalse);
    expect(data.containsKey('cookies'), isFalse);
    expect(data.containsKey('history'), isFalse);
  });

  test('未対応バージョンや余分な項目は拒否する', () {
    final data = SiteRuleBundle.fromSite(sampleSite()).toJson();

    expect(
      () => SiteRuleBundle.parse(jsonEncode({...data, 'version': 999})),
      throwsFormatException,
    );

    expect(
      () => SiteRuleBundle.parse(jsonEncode({...data, 'cookies': 'secret'})),
      throwsFormatException,
    );

    expect(() => SiteRuleBundle.parse('{"broken":'), throwsFormatException);
  });

  test('壊れたQRと過大展開する圧縮設定を拒否する', () {
    expect(
      () => SiteRuleBundle.parse('${SiteRuleBundle.prefix}broken'),
      throwsFormatException,
    );

    final source = List<int>.filled(SiteRuleBundle.maxJsonBytes + 1, 65);
    final encoded = base64Url.encode(gzip.encode(source));

    expect(
      () => SiteRuleBundle.parse('${SiteRuleBundle.prefix}$encoded'),
      throwsFormatException,
    );
  });

  test('別の取得元の本文画像設定は反映前に拒否する', () {
    final data = SiteRuleBundle.fromSite(sampleSite()).toJson();

    final images = Map<String, dynamic>.from(data['images'] as Map);
    images['pageUrl'] = 'https://other.example/chapter/1/';

    expect(
      () => SiteRuleBundle.parse(jsonEncode({...data, 'images': images})),
      throwsFormatException,
    );
  });

  test('1枚のQRに収まらない場合もJSONを欠落させない', () {
    final random = Random(42);
    const alphabet =
        'abcdefghijklmnopqrstuvwxyz'
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        '0123456789';

    final noise = List.generate(
      3000,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();

    final bundle = SiteRuleBundle.fromSite(
      sampleSite(worksUrl: 'https://example.com/list/?sample=$noise'),
    );

    expect(
      SiteRuleBundle.parse(bundle.encodeJson()).site.rules['works']!.pageUrl,
      contains(noise),
    );

    expect(() => bundle.encodeQr(), throwsFormatException);
  });

  test('反映前確認は通常HTMLを使い、元の取得方式を変更しない', () async {
    final bundle = SiteRuleBundle.fromSite(sampleSite());
    var called = 0;

    final result = await checkSiteBundleStatic(
      bundle,
      cancelToken: CancelToken(),
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        called++;

        expect(input, 'https://example.com/list/?page=1');
        expect(allowedOrigin, 'https://example.com');

        const source = '''
<div class="entry">
  <a href="/work/selected/">作品タイトル</a>
  <span class="date">2 hours ago</span>
  <span class="latest">12</span>
</div>
''';

        return HtmlProbePage(
          uri: Uri.parse(input),
          source: source,
          bytes: utf8.encode(source).length,
        );
      },
    );

    expect(called, 1);
    expect(result.items.single.title, '作品タイトル');

    expect(bundle.site.rules['works']!.acquisition, 'renderedDom');
    expect(bundle.site.images!.acquisition, 'renderedDom');
  });

  test('通常HTMLで一覧が取れない場合を成功扱いしない', () async {
    final bundle = SiteRuleBundle.fromSite(sampleSite());

    await expectLater(
      checkSiteBundleStatic(
        bundle,
        cancelToken: CancelToken(),
        fetcher:
            (input, {required cancelToken, required allowedOrigin}) async =>
                HtmlProbePage(
                  uri: Uri.parse(input),
                  source: '<html></html>',
                  bytes: 13,
                ),
      ),
      throwsFormatException,
    );
  });

  test('サイト一式を追加・更新し、更新では保存先IDを維持する', () async {
    final root = await Directory.systemTemp.createTemp('site-bundle-');
    addTearDown(() => root.delete(recursive: true));

    final store = SiteRuleStore(Directory('${root.path}/comics'));

    final incoming = SiteRuleBundle.fromSite(sampleSite()).site;

    final first = await store.importSiteBundle(incoming: incoming);

    final second = await store.importSiteBundle(incoming: incoming);

    expect(first.id, isNot(second.id));

    final updated = await store.importSiteBundle(
      incoming: incoming,
      targetId: first.id,
      expectedUpdatedAt: first.updatedAt,
    );

    expect(updated.id, first.id);
    expect(updated.images!.rule.attribute, 'data-src');
    expect(updated.rules['chapters']!.details.containsKey('tags'), isTrue);

    final loaded = await store.load();

    expect(loaded.length, 2);
    expect(loaded.any((site) => site.id == second.id), isTrue);
  });

  test('確認時点より古い更新条件では保存しない', () async {
    final root = await Directory.systemTemp.createTemp('site-bundle-stale-');
    addTearDown(() => root.delete(recursive: true));

    final store = SiteRuleStore(Directory('${root.path}/comics'));

    final incoming = SiteRuleBundle.fromSite(sampleSite()).site;

    final saved = await store.importSiteBundle(incoming: incoming);

    await expectLater(
      store.importSiteBundle(
        incoming: incoming,
        targetId: saved.id,
        expectedUpdatedAt: DateTime.utc(2000),
      ),
      throwsStateError,
    );

    expect((await store.load()).single.toJson(), saved.toJson());
  });
}
