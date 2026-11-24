import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/library_widgets.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/rule_library.dart';
import 'package:offline_comic_reader/services/saved_download_repository.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/services/user_library_store.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

SavedSiteRule site([String id = 'AAAAAAAAAAAAAAAAAAAAAA']) => SavedSiteRule(
  id: id,
  name: 'Custom site',
  updatedAt: DateTime.utc(2026),
  rules: {
    'works': ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.work',
      fields: defaultListFields(),
    ),
  },
);

RuleLibraryWork record([String id = 'AAAAAAAAAAAAAAAAAAAAAA']) =>
    ruleLibraryWork(
      site: site(id),
      workUrl: 'https://example.com/work/#fragment',
      title: 'Custom work',
    );

RuleBrowseItem row(String id) => RuleBrowseItem(
  title: 'Chapter $id',
  url: Uri.parse('https://example.com/read/$id'),
  thumbnail: null,
  date: 'Date $id',
  latestChapter: '',
  issues: const [],
);

void main() {
  test('source identity is strict and isolated', () {
    expect(isRuleLibrarySource('custom-site:AAAAAAAAAAAAAAAAAAAAAA'), isTrue);
    expect(isRuleLibrarySource('sample-source'), isFalse);
    expect(isRuleLibrarySource('custom-site:../invalid'), isFalse);
    expect(
      () => ruleLibrarySiteId('custom-site:../invalid'),
      throwsFormatException,
    );
  });

  test('work URL is canonical and query remains part of identity', () {
    expect(record().work.id, 'https://example.com/work/');
    expect(
      ruleLibraryWork(
        site: site(),
        workUrl: 'https://example.com/work/?id=2#part',
        title: 'Work',
      ).work.id,
      'https://example.com/work/?id=2',
    );
  });

  test('cross-origin work rejected', () {
    expect(
      () => ruleLibraryWork(
        site: site(),
        workUrl: 'https://other.example/work/',
        title: 'Wrong',
      ),
      throwsFormatException,
    );
  });

  test('same URL on different site IDs has distinct storage identity', () {
    final a = ruleLibraryChapter(record: record(), chapter: row('1'));
    final b = ruleLibraryChapter(
      record: record('BBBBBBBBBBBBBBBBBBBBBB'),
      chapter: row('1'),
    );

    expect(a.storageId, isNot(b.storageId));
    expect(a.progressSourceId, isNot(b.progressSourceId));
    validateRuleLibraryChapter(a);
    validateRuleLibraryChapter(b);
  });

  test('saved groups separate sites even when work URL matches', () {
    final a = ruleLibraryChapter(record: record(), chapter: row('1'));
    final b = ruleLibraryChapter(
      record: record('BBBBBBBBBBBBBBBBBBBBBB'),
      chapter: row('1'),
    );

    final groups = groupRuleLibraryChapters([
      SavedChapter(chapter: a, files: const [], bytes: 10),
      SavedChapter(chapter: b, files: const [], bytes: 20),
    ]);

    expect(groups, hasLength(2));
  });

  test('offline adapter refuses network content fetching', () async {
    final adapter = RuleLibraryOfflineAdapter(
      'custom-site:AAAAAAAAAAAAAAAAAAAAAA',
    );

    await expectLater(
      adapter.fetchContent(
        ruleLibraryChapter(record: record(), chapter: row('1')),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'custom favorites coexist with built-in favorites and persist',
    () async {
      final root = await Directory.systemTemp.createTemp('rule-library-fav-');
      final library = UserLibraryStore(root);

      try {
        const tab = SourceTab('ja', 'Japanese', BrowseQuery(language: 'ja'));
        final builtin = ComicWork(
          id: 'builtin-work',
          title: 'Built-in work',
          url: Uri.parse('https://builtin.example/work/'),
        );

        await library.toggleFavorite('sample-source', tab, builtin);

        final custom = record();
        await library.toggleFavorite(custom.sourceId, custom.tab, custom.work);

        expect(library.favorites, hasLength(2));

        final restored = UserLibraryStore(root);
        try {
          await restored.load();
          expect(
            restored.isFavorite(custom.sourceId, custom.tab, custom.work),
            isTrue,
          );
          expect(restored.isFavorite('sample-source', tab, builtin), isTrue);
        } finally {
          restored.dispose();
        }
      } finally {
        library.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'custom history keeps latest chapter per work and restores position IDs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rule-library-history-',
      );
      final library = UserLibraryStore(root);

      try {
        final custom = record();

        for (final id in ['1', '2']) {
          await library.remember(
            custom.sourceId,
            custom.tab,
            custom.work,
            ruleLibraryChapter(record: custom, chapter: row(id)),
          );
        }

        expect(library.history, hasLength(1));
        expect(
          library.history.single.chapter!.url.toString(),
          'https://example.com/read/2',
        );
        expect(library.history.single.chapter!.workId, custom.work.id);
        expect(
          library.history.single.chapter!.progressSourceId,
          custom.sourceId,
        );

        final restored = UserLibraryStore(root);
        try {
          await restored.load();
          expect(
            restored.history.single.chapter!.id,
            'https://example.com/read/2',
          );
        } finally {
          restored.dispose();
        }
      } finally {
        library.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'missing navigation cache reopens selected chapter, never sample URL',
    () async {
      final root = await Directory.systemTemp.createTemp('rule-library-nav-');
      final store = DownloadStore(root);

      try {
        final custom = record();
        final selected = ruleLibraryChapter(
          record: custom,
          chapter: row('chosen'),
        );

        final chapters = await ruleLibraryNavigation(
          store: store,
          record: custom,
          selected: selected,
        );

        expect(chapters, hasLength(1));
        expect(chapters.single.url, selected.url);
      } finally {
        store.close();
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'common favorite shelf includes custom works when enabled',
    (tester) async {
      Directory? root;
      UserLibraryStore? library;

      try {
        await tester.runAsync(() async {
          final created = await Directory.systemTemp
              .createTemp('rule-library-shelf-')
              .timeout(const Duration(seconds: 10));
          root = created;

          final instance = UserLibraryStore(created);
          library = instance;

          const builtinTab = SourceTab(
            'ja',
            'Japanese',
            BrowseQuery(language: 'ja'),
          );

          await instance
              .toggleFavorite(
                'sample-source',
                builtinTab,
                ComicWork(
                  id: 'builtin-work',
                  title: 'Built-in work',
                  url: Uri.parse('https://builtin.example/work/'),
                ),
              )
              .timeout(const Duration(seconds: 10));

          final custom = record();

          await instance
              .toggleFavorite(custom.sourceId, custom.tab, custom.work)
              .timeout(const Duration(seconds: 10));

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LibraryShelf(
                  library: instance,
                  sourceId: 'sample-source',
                  sourceName: 'Built-in',
                  includeCustomSites: true,
                  history: false,
                  onOpen: (_) async {},
                ),
              ),
            ),
          );

          await instance.load().timeout(const Duration(seconds: 10));
        });

        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );

        expect(find.text('Built-in work'), findsOneWidget);
        expect(find.text('Custom work'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());

        await tester.runAsync(() async {
          library?.dispose();

          final directory = root;
          if (directory != null && await directory.exists()) {
            await directory
                .delete(recursive: true)
                .timeout(const Duration(seconds: 10));
          }
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
