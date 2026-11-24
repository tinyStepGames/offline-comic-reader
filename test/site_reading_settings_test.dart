import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapter_image_rule.dart';
import 'package:offline_comic_reader/services/chapter_image_settings.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_browse_tab.dart';
import 'package:offline_comic_reader/services/site_browse_tab_plan.dart';
import 'package:offline_comic_reader/services/site_import_comparison.dart';
import 'package:offline_comic_reader/services/site_reading_settings.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/site_search_plan.dart';
import 'package:offline_comic_reader/services/site_search_settings.dart';
import 'package:offline_comic_reader/services/tag_browse_plan.dart';
import 'package:offline_comic_reader/services/tag_navigation_settings.dart';
import 'package:offline_comic_reader/services/work_tag_link.dart';

ListExtractionRule worksRule() {
  final fields = defaultListFields();
  fields['title'] = const ListFieldRule(selector: '.title');
  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  return ListExtractionRule(
    pageUrl: 'https://example.com/list/',
    groupSelector: '.item',
    fields: fields,
  );
}

ListExtractionRule detailsRule() => ListExtractionRule(
  pageUrl: 'https://example.com/gallery/sample/',
  groupSelector: 'html',
  fields: defaultListFields(),
  acquisition: 'staticHtml',
  details: const {
    'title': ListFieldRule(selector: 'h1'),
    'description': ListFieldRule(selector: '.description'),
    'tags': ListFieldRule(selector: '.tags a'),
    'thumbnail': ListFieldRule(
      selector: '.cover',
      mode: ListValueMode.attribute,
      attribute: 'src',
    ),
  },
);

SiteReadingSettings detailsSettings() => SiteReadingSettings(
  mode: SiteReadingMode.details,
  detailsRule: detailsRule(),
  readLink: const ListFieldRule(
    selector: 'a.read',
    mode: ListValueMode.attribute,
    attribute: 'href',
  ),
);

SavedSiteRule makeSite({SiteReadingSettings? reading}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'Image gallery',
  updatedAt: DateTime.utc(2026, 11, 23),
  rules: {'works': worksRule()},
  readingSettings: reading,
  images: const ChapterImageSettings(
    pageUrl: 'https://example.com/gallery/sample/',
    acquisition: 'staticHtml',
    rule: ChapterImageRule(selector: '#images img'),
  ),
);

void main() {
  test('legacy site remains chapter based and omits the optional key', () {
    final site = makeSite();
    final restored = SavedSiteRule.fromJson(site.toJson());

    expect(restored.readingMode, SiteReadingMode.chapters);
    expect(restored.readingSettings, isNull);
    expect(restored.toJson().containsKey('readingSettings'), isFalse);

    final bundle = SiteRuleBundle.fromSite(site);
    expect(bundle.toJson()['version'], 1);
    expect(bundle.toJson().containsKey('readingSettings'), isFalse);
  });

  test('direct mode needs no chapter rule and survives site JSON', () {
    final site = makeSite(
      reading: const SiteReadingSettings(mode: SiteReadingMode.direct),
    );

    final restored = SavedSiteRule.fromJson(site.toJson());

    expect(restored.rules.containsKey('chapters'), isFalse);
    expect(restored.readingMode, SiteReadingMode.direct);
    expect(restored.readingSettings!.toJson(), site.readingSettings!.toJson());
  });

  test('details and read-link settings round trip without loss', () {
    final original = detailsSettings();
    final restored = SiteReadingSettings.fromJson(original.toJson());

    expect(restored.toJson(), original.toJson());
    expect(restored.detailsRule!.details.keys, contains('tags'));
    expect(restored.readLink!.attribute, 'href');
  });

  test('same-page details do not require a read-link rule', () {
    final settings = SiteReadingSettings(
      mode: SiteReadingMode.details,
      detailsRule: detailsRule(),
    );

    settings.validate();
    expect(SiteReadingSettings.fromJson(settings.toJson()).readLink, isNull);
  });

  test('unknown modes and unknown keys are rejected', () {
    expect(
      () => SiteReadingSettings.fromJson({'version': 1, 'mode': 'unknown'}),
      throwsFormatException,
    );

    expect(
      () => SiteReadingSettings.fromJson({
        'version': 1,
        'mode': 'direct',
        'cookies': [],
      }),
      throwsFormatException,
    );
  });

  test('details mode requires an independent details rule', () {
    expect(
      () => const SiteReadingSettings(mode: SiteReadingMode.details).validate(),
      throwsFormatException,
    );
  });

  test('different-origin details cannot be stored with the site', () {
    final changed = detailsRule().toJson();
    changed['pageUrl'] = 'https://other.example/gallery/';

    final settings = SiteReadingSettings(
      mode: SiteReadingMode.details,
      detailsRule: ListExtractionRule.parse(jsonEncode(changed)),
    );

    expect(() => settings.validateFor([worksRule()]), throwsFormatException);
  });

  test('v5 JSON and QR preserve reading settings', () {
    final original = SiteRuleBundle.fromSite(
      makeSite(reading: detailsSettings()),
    );

    expect(original.toJson()['version'], 5);

    final jsonResult = SiteRuleBundle.parse(original.encodeJson());
    final qrResult = SiteRuleBundle.parse(original.encodeQr());

    expect(jsonResult.toJson(), original.toJson());
    expect(qrResult.toJson(), original.toJson());
  });

  test('reading settings cannot be mislabeled as an older version', () {
    final data = SiteRuleBundle.fromSite(
      makeSite(
        reading: const SiteReadingSettings(mode: SiteReadingMode.direct),
      ),
    ).toJson();

    for (final version in [1, 2, 3, 4]) {
      expect(
        () => SiteRuleBundle.parse(jsonEncode({...data, 'version': version})),
        throwsFormatException,
      );
    }
  });

  test('v5 can contain search tags and tabs together', () {
    final original = makeSite(reading: detailsSettings());

    final data = original.toJson();
    data['tagNavigation'] = TagNavigationSettings(rule: worksRule()).toJson();
    data['searchSettings'] = const SiteSearchSettings(
      urlTemplate: 'https://example.com/list/?q={keyword}',
    ).toJson();
    data['browseTabs'] = const [
      SiteBrowseTab(
        id: 'latest',
        title: 'Latest',
        pageUrl: 'https://example.com/latest/',
      ),
    ].map((tab) => tab.toJson()).toList();

    final site = SavedSiteRule.fromJson(data);
    final bundle = SiteRuleBundle.fromSite(site);
    final restored = SiteRuleBundle.parse(bundle.encodeJson());

    expect(bundle.toJson()['version'], 5);
    expect(restored.site.browseTabs, hasLength(1));
    expect(restored.site.searchSettings, isNotNull);
    expect(restored.site.tagNavigation, isNotNull);
    expect(restored.site.readingMode, SiteReadingMode.details);
  });

  test('tag search and tab plans keep reading settings', () {
    final original = makeSite(reading: detailsSettings());
    final data = original.toJson();

    data['searchSettings'] = const SiteSearchSettings(
      urlTemplate: 'https://example.com/list/?q={keyword}',
    ).toJson();

    final site = SavedSiteRule.fromJson(data);

    final tagPlan = makeTagBrowsePlan(
      site,
      WorkTagLink(
        label: 'Gallery',
        url: Uri.parse('https://example.com/list/'),
      ),
    );

    final searchPlan = makeSiteSearchPlan(site, 'sample');

    final tabPlan = makeSiteBrowseTabPlan(
      site,
      const SiteBrowseTab(
        id: 'latest',
        title: 'Latest',
        pageUrl: 'https://example.com/latest/',
      ),
    );

    for (final effective in [tagPlan.site, searchPlan, tabPlan]) {
      expect(
        effective.readingSettings!.toJson(),
        original.readingSettings!.toJson(),
      );
    }
  });

  test('import comparison includes reading settings and removal', () {
    final withSettings = makeSite(reading: detailsSettings());
    final withoutSettings = makeSite();

    final identical = SiteImportComparison.compare(
      incoming: withSettings,
      target: withSettings,
    );

    expect(identical.hasChanges, isFalse);

    final removed = SiteImportComparison.compare(
      incoming: withoutSettings,
      target: withSettings,
    );

    expect(
      removed.changes.singleWhere((change) => change.key == 'reading').kind,
      SiteImportChangeKind.removed,
    );
    expect(removed.removedLabels, contains('開き方・チャプターなし作品詳細'));
  });

  test('store mutations preserve settings and reject stale edits', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'reading-settings-isolated-',
    );
    addTearDown(() => sandbox.delete(recursive: true));

    final store = SiteRuleStore(Directory('${sandbox.path}/comics'));
    var saved = await store.importSiteBundle(
      incoming: makeSite(reading: detailsSettings()),
    );

    final expected = saved.readingSettings!.toJson();

    saved = await store.save(id: saved.id, name: saved.name, rule: worksRule());
    expect(saved.readingSettings!.toJson(), expected);

    saved = await store.saveImages(id: saved.id, settings: saved.images!);
    expect(saved.readingSettings!.toJson(), expected);

    await store.rename(saved.id, 'Renamed gallery');
    saved = (await store.load()).single;
    expect(saved.readingSettings!.toJson(), expected);

    saved = await store.saveTagNavigation(
      id: saved.id,
      settings: null,
      expectedUpdatedAt: saved.updatedAt,
    );
    expect(saved.readingSettings!.toJson(), expected);

    saved = await store.saveSearchSettings(
      id: saved.id,
      settings: null,
      expectedUpdatedAt: saved.updatedAt,
    );
    expect(saved.readingSettings!.toJson(), expected);

    saved = await store.saveBrowseTabs(
      id: saved.id,
      tabs: const [],
      expectedUpdatedAt: saved.updatedAt,
    );
    expect(saved.readingSettings!.toJson(), expected);

    final duplicate = await store.duplicate(saved.id);
    expect(duplicate.id, isNot(saved.id));
    expect(duplicate.readingSettings!.toJson(), expected);

    await expectLater(
      store.saveReadingSettings(
        id: saved.id,
        settings: const SiteReadingSettings(mode: SiteReadingMode.direct),
        expectedUpdatedAt: DateTime.utc(2000),
      ),
      throwsStateError,
    );

    saved = await store.saveReadingSettings(
      id: saved.id,
      settings: const SiteReadingSettings(mode: SiteReadingMode.direct),
      expectedUpdatedAt: saved.updatedAt,
    );
    expect(saved.readingMode, SiteReadingMode.direct);

    saved = await store.saveReadingSettings(
      id: saved.id,
      settings: null,
      expectedUpdatedAt: saved.updatedAt,
    );

    expect(saved.readingSettings, isNull);
    expect(saved.readingMode, SiteReadingMode.chapters);
    expect(saved.images, isNotNull);
    expect(saved.rules.containsKey('works'), isTrue);
  });

  test(
    'importing old settings removes reading settings only after explicit update',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'reading-import-isolated-',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final store = SiteRuleStore(Directory('${sandbox.path}/comics'));
      final saved = await store.importSiteBundle(
        incoming: makeSite(reading: detailsSettings()),
      );

      final updated = await store.importSiteBundle(
        incoming: makeSite(),
        targetId: saved.id,
        expectedUpdatedAt: saved.updatedAt,
      );

      expect(updated.id, saved.id);
      expect(updated.readingSettings, isNull);
      expect(updated.readingMode, SiteReadingMode.chapters);
      expect(updated.images, isNotNull);
    },
  );
}
