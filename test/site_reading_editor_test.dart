import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_reading_settings.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/site_reading_editor_page.dart';

SavedSiteRule makeSite(SiteReadingMode mode) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'Test gallery',
  updatedAt: DateTime.utc(2026),
  rules: {
    'works': ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.item',
      fields: defaultListFields(),
    ),
  },
  readingSettings: mode == SiteReadingMode.chapters
      ? null
      : SiteReadingSettings(
          mode: mode,
          detailsRule: mode == SiteReadingMode.details
              ? ListExtractionRule(
                  pageUrl: 'https://example.com/detail/',
                  groupSelector: 'html',
                  fields: defaultListFields(),
                )
              : null,
        ),
);

class MemoryReadingStore extends SiteRuleStore {
  MemoryReadingStore() : super(Directory('unused-reading-editor/comics'));

  int writes = 0;
  bool fail = false;
  SiteReadingSettings? last;

  @override
  Future<SavedSiteRule> saveReadingSettings({
    required String id,
    required SiteReadingSettings? settings,
    required DateTime expectedUpdatedAt,
  }) async {
    if (fail) throw StateError('simulated save failure');

    writes++;
    last = settings;

    return SavedSiteRule.fromJson({
      ...makeSite(SiteReadingMode.chapters).toJson(),
      if (settings != null) 'readingSettings': settings.toJson(),
    });
  }
}

Future<void> showEditor(
  WidgetTester tester,
  MemoryReadingStore repository,
  SiteReadingMode mode,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SiteReadingEditorPage(
                  repository: repository,
                  site: makeSite(mode),
                ),
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('legacy site starts in chapter mode without saving', (
    tester,
  ) async {
    final repository = MemoryReadingStore();
    await showEditor(tester, repository, SiteReadingMode.chapters);

    expect(find.byKey(const ValueKey('reading-mode-chapters')), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-sample')), findsNothing);
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct mode hides detail-only controls', (tester) async {
    final repository = MemoryReadingStore();
    await showEditor(tester, repository, SiteReadingMode.direct);

    expect(find.byKey(const ValueKey('reading-mode-direct')), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-sample')), findsNothing);
    expect(find.byKey(const ValueKey('reading-link-selector')), findsNothing);
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details mode exposes separate read-link settings', (
    tester,
  ) async {
    final repository = MemoryReadingStore();
    await showEditor(tester, repository, SiteReadingMode.details);

    final toggle = find.byType(SwitchListTile);
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('reading-link-selector'));
    await reveal(tester, selector);

    expect(selector, findsOneWidget);
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct save does not need chapter rule', (tester) async {
    final repository = MemoryReadingStore();
    await showEditor(tester, repository, SiteReadingMode.direct);

    final save = find.byKey(const ValueKey('reading-settings-save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.writes, 1);
    expect(repository.last!.mode, SiteReadingMode.direct);
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure keeps editor open', (tester) async {
    final repository = MemoryReadingStore()..fail = true;
    await showEditor(tester, repository, SiteReadingMode.direct);

    final save = find.byKey(const ValueKey('reading-settings-save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.writes, 0);

    final message = find.textContaining('保存できませんでした');
    await reveal(tester, message);

    expect(message, findsOneWidget);
    expect(find.byType(SiteReadingEditorPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow details editor has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MemoryReadingStore();
    await showEditor(tester, repository, SiteReadingMode.details);

    final save = find.byKey(const ValueKey('reading-settings-save'));
    await reveal(tester, save);

    expect(tester.takeException(), isNull);
    expect(repository.writes, 0);
  });
}
