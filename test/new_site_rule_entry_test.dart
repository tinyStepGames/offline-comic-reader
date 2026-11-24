import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/list_rule_lab_page.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

void main() {
  late Directory sandbox;
  late Directory comics;
  late DownloadStore store;

  setUp(() async {
    // SiteRuleStoreはcomics.parentにサイト設定を保存する。
    // 親も含めて、このテストだけの一時領域にする。
    sandbox = await Directory.systemTemp.createTemp('new-site-rule-isolated-');

    comics = Directory('${sandbox.path}${Platform.pathSeparator}comics');

    await comics.create(recursive: true);
    store = DownloadStore(comics);
  });

  tearDown(() async {
    store.close();

    // このテストが作った専用領域だけを削除する。
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  ListExtractionRule sampleRule({
    required String url,
    required String selector,
  }) => ListExtractionRule(
    pageUrl: url,
    groupSelector: selector,
    fields: defaultListFields(),
    kind: 'works',
    acquisition: 'staticHtml',
  );

  Future<void> openNew(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ListRuleLabPage(
          store: store,
          initialPage: null,
          initialUrl: 'https://',
          initialSelector: '',
          initialAcquisition: 'staticHtml',
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;

    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: scrollable,
      maxScrolls: 80,
    );

    await tester.pumpAndSettle();

    expect(target, findsOneWidget);

    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final target = field(label);
    await reveal(tester, target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  Future<List<SavedSiteRule>> readSites(WidgetTester tester) async {
    final result = await tester.runAsync(
      () =>
          SiteRuleStore(store.root).load().timeout(const Duration(seconds: 5)),
    );

    expect(tester.takeException(), isNull);
    expect(result, isNotNull);

    return result!;
  }

  Future<void> saveAndWait(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'サイトに保存');

    await reveal(tester, button);

    final completed = await tester.runAsync<bool>(() async {
      final repository = SiteRuleStore(store.root);

      final before = await repository.load().timeout(
        const Duration(seconds: 5),
      );

      final previousVersions = {
        for (final site in before)
          site.id: site.updatedAt.toUtc().toIso8601String(),
      };

      await tester.tap(button);

      final deadline = DateTime.now().add(const Duration(seconds: 10));

      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final after = await repository.load().timeout(
          const Duration(seconds: 3),
        );

        final changed = after.any(
          (site) =>
              previousVersions[site.id] !=
              site.updatedAt.toUtc().toIso8601String(),
        );

        if (changed) {
          await Future<void>.delayed(Duration.zero);
          return true;
        }
      }

      throw StateError('サイト保存の完了を10秒以内に確認できませんでした。');
    });

    expect(tester.takeException(), isNull);
    expect(completed, isTrue);

    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AppBar, '一覧ルール'),
      findsOneWidget,
      reason: '保存成功後は既存ルールの編集状態になること',
    );
  }

  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  test('テスト用サイト設定は専用の親フォルダー内に保存する', () async {
    expect(comics.parent.absolute.path, sandbox.absolute.path);

    final repository = SiteRuleStore(comics);
    expect(await repository.load(), isEmpty);

    await repository.save(
      name: '分離確認',
      rule: sampleRule(
        url: 'https://isolated.example.com/list/',
        selector: '.item',
      ),
    );

    final settingsFile = File(
      '${sandbox.path}${Platform.pathSeparator}'
      '_site_rules${Platform.pathSeparator}sites.json',
    );

    expect(await settingsFile.exists(), isTrue);
    expect(await repository.load(), hasLength(1));
  });

  test('別の専用領域とサイト設定を共有しない', () async {
    final otherSandbox = await Directory.systemTemp.createTemp(
      'new-site-rule-other-',
    );

    try {
      final otherComics = Directory(
        '${otherSandbox.path}${Platform.pathSeparator}comics',
      );

      await otherComics.create(recursive: true);

      final first = SiteRuleStore(comics);
      final second = SiteRuleStore(otherComics);

      expect(await first.load(), isEmpty);
      expect(await second.load(), isEmpty);

      await first.save(
        name: '領域A',
        rule: sampleRule(url: 'https://a.example.com/list/', selector: '.a'),
      );

      expect(await first.load(), hasLength(1));
      expect(await second.load(), isEmpty);

      await second.save(
        name: '領域B',
        rule: sampleRule(url: 'https://b.example.com/list/', selector: '.b'),
      );

      final firstSites = await first.load();
      final secondSites = await second.load();

      expect(firstSites, hasLength(1));
      expect(secondSites, hasLength(1));
      expect(firstSites.single.name, '領域A');
      expect(secondSites.single.name, '領域B');
    } finally {
      if (await otherSandbox.exists()) {
        await otherSandbox.delete(recursive: true);
      }
    }
  });

  testWidgets('新規作成画面は空の作品一覧ルールから開始する', (tester) async {
    expect(await readSites(tester), isEmpty);

    await openNew(tester);

    expect(find.widgetWithText(AppBar, '新規サイトルール作成'), findsOneWidget);

    final url = field('対象URL');
    await reveal(tester, url);

    expect(tester.widget<TextField>(url).controller!.text, 'https://');

    final group = field('1件分のまとまり');
    await reveal(tester, group);

    expect(tester.widget<TextField>(group).controller!.text, isEmpty);

    await closePage(tester);
  });

  testWidgets('新規保存は既存サイトを上書きせず再保存時も重複しない', (tester) async {
    // 共有保存先への退行があれば、最初の時点で検出する。
    expect(await readSites(tester), isEmpty);

    final existing = await tester.runAsync(
      () => SiteRuleStore(store.root)
          .save(
            name: '既存サイト',
            rule: sampleRule(
              url: 'https://old.example.com/list/',
              selector: '.old-item',
            ),
          )
          .timeout(const Duration(seconds: 5)),
    );

    expect(tester.takeException(), isNull);
    expect(existing, isNotNull);

    final existingId = existing!.id;

    expect(await readSites(tester), hasLength(1));

    await openNew(tester);

    await enter(tester, 'サイト保存名', '追加サイト');
    await enter(tester, '対象URL', 'https://new.example.com/list/');
    await enter(tester, '1件分のまとまり', '.new-item');

    await saveAndWait(tester);

    var sites = await readSites(tester);
    expect(sites, hasLength(2));

    final preserved = sites.singleWhere((site) => site.id == existingId);

    expect(preserved.name, '既存サイト');
    expect(preserved.rules['works']!.pageUrl, 'https://old.example.com/list/');
    expect(preserved.rules['works']!.groupSelector, '.old-item');

    final created = sites.singleWhere((site) => site.id != existingId);

    expect(created.name, '追加サイト');
    expect(created.rules['works']!.pageUrl, 'https://new.example.com/list/');
    expect(created.rules['works']!.groupSelector, '.new-item');
    expect(created.rules['works']!.acquisition, 'staticHtml');

    // 同じ画面で再保存しても、新たなサイトIDを増やさないこと。
    await saveAndWait(tester);

    sites = await readSites(tester);
    expect(sites, hasLength(2));

    final updated = sites.singleWhere((site) => site.id == created.id);

    expect(updated.name, '追加サイト');
    expect(updated.rules['works']!.groupSelector, '.new-item');

    expect(sites.singleWhere((site) => site.id == existingId).name, '既存サイト');

    await closePage(tester);
  });

  test('ホームから旧作成室ではなく一覧編集画面を直接開く', () {
    final source = File('lib/catalog_page.dart').readAsStringSync();

    final start = source.indexOf('Future<void> _openRuleLab() async');
    expect(start, greaterThanOrEqualTo(0));

    final end = source.indexOf('void _changeHomeSection', start);
    expect(end, greaterThan(start));

    final method = source.substring(start, end);

    expect(method, contains('ListRuleLabPage('));
    expect(method, contains("initialUrl: 'https://'"));
    expect(method, isNot(contains('HtmlRuleLabPage(')));
    expect(source, contains("tooltip: '新規サイトルール作成'"));
  });
}
