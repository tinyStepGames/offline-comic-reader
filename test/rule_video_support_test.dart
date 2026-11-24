import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/rule_batch_download_panel.dart';
import '../lib/rule_download_button.dart';
import '../lib/services/chapter_image_rule.dart';
import '../lib/services/chapter_image_settings.dart';
import '../lib/services/download_store.dart';
import '../lib/services/list_extraction_rule.dart';
import '../lib/services/rule_downloads.dart';
import '../lib/services/rule_video_support.dart';
import '../lib/services/site_reading_settings.dart';
import '../lib/services/site_rule_store.dart';
import '../lib/services/video_progress.dart';
import '../lib/services/video_source.dart';

const siteA = 'AAAAAAAAAAAAAAAAAAAAAA';
const siteB = 'BBBBBBBBBBBBBBBBBBBBBB';

SavedSiteRule site({bool video = false, bool images = false}) {
  final fields = defaultListFields();
  fields['title'] = const ListFieldRule(selector: '.title');
  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  return SavedSiteRule(
    id: siteA,
    name: 'Example',
    updatedAt: DateTime.utc(2026, 11, 24),
    rules: {
      'works': ListExtractionRule(
        pageUrl: 'https://example.com/list',
        groupSelector: '.item',
        fields: fields,
      ),
    },
    images: images
        ? const ChapterImageSettings(
            pageUrl: 'https://example.com/episode/1',
            acquisition: 'staticHtml',
            rule: ChapterImageRule(selector: '.reader img', attribute: 'src'),
          )
        : null,
    readingSettings: video
        ? const SiteReadingSettings().withVideo(
            const VideoSourceSettings(
              pageUrl: 'https://example.com/episode/1',
              allowedOrigins: ['https://media.example.com'],
            ),
          )
        : null,
  );
}

void main() {
  test('content availability preserves image sites', () {
    expect(canOpenRuleContent(site()), isFalse);
    expect(canOpenRuleContent(site(images: true)), isTrue);
    expect(usesRuleVideo(site(images: true)), isFalse);
    expect(canOpenRuleContent(site(video: true)), isTrue);
  });

  test('video takes precedence even if old image rule remains', () {
    final mixed = site(video: true, images: true);
    expect(usesRuleVideo(mixed), isTrue);
    expect(
      () => requireRuleImageDownload(mixed),
      throwsA(isA<UnsupportedError>()),
    );
    expect(() => requireRuleImageDownload(site(images: true)), returnsNormally);
  });

  test('video progress identity keeps site query and chapter isolation', () {
    String key(String id, String url) =>
        ruleVideoProgressKey(siteId: id, chapterUrl: url);

    final first = key(siteA, 'https://example.com/e/1?q=1');
    expect(key(siteA, 'https://example.com/e/1?q=1#fragment'), first);
    expect(key(siteB, 'https://example.com/e/1?q=1'), isNot(first));
    expect(key(siteA, 'https://example.com/e/1?q=2'), isNot(first));
    expect(key(siteA, 'https://example.com/e/2?q=1'), isNot(first));
  });

  test('video position round trips and clamps to current duration', () {
    const position = VideoPosition(
      position: Duration(seconds: 125),
      duration: Duration(seconds: 600),
    );

    final restored = VideoPosition.decode(position.toJson())!;
    expect(restored.position, const Duration(seconds: 125));
    expect(
      restored.resumeFor(const Duration(seconds: 100)),
      const Duration(seconds: 100),
    );
    expect(restored.resumeFor(Duration.zero), Duration.zero);
  });

  test('broken or unsupported position data is ignored', () {
    expect(VideoPosition.decode(null), isNull);
    expect(VideoPosition.decode({'version': 2}), isNull);
    expect(
      VideoPosition.decode({
        'version': 1,
        'positionMs': -1,
        'durationMs': 1000,
      }),
      isNull,
    );
    expect(
      VideoPosition.decode({
        'version': 1,
        'positionMs': '100',
        'durationMs': 1000,
      }),
      isNull,
    );
  });

  test('position writes preserve order and can be reopened', () async {
    final root = await Directory.systemTemp.createTemp('video-position-test-');
    final store = DownloadStore(root, maxConcurrentImages: 1);

    try {
      final progress = VideoProgressStore(store);
      final key = ruleVideoProgressKey(
        siteId: siteA,
        chapterUrl: 'https://example.com/episode/1',
      );

      await Future.wait([
        progress.save(
          key,
          const VideoPosition(
            position: Duration(seconds: 10),
            duration: Duration(minutes: 20),
          ),
        ),
        progress.save(
          key,
          const VideoPosition(
            position: Duration(seconds: 30),
            duration: Duration(minutes: 20),
          ),
        ),
      ]);

      final restored = await VideoProgressStore(store).read(key);
      expect(restored!.position, const Duration(seconds: 30));

      final other = ruleVideoProgressKey(
        siteId: siteB,
        chapterUrl: 'https://example.com/episode/1',
      );
      expect(await progress.read(other), isNull);
    } finally {
      store.close();
      await root.delete(recursive: true);
    }
  });

  test('video site rejects both single and batch image downloads', () async {
    final root = await Directory.systemTemp.createTemp('video-download-guard-');
    final store = DownloadStore(root, maxConcurrentImages: 1);

    try {
      final downloads = RuleDownloads(store);
      final chapter = ruleSavedChapter(
        siteId: siteA,
        workUrl: 'https://example.com/work',
        chapterUrl: 'https://example.com/episode/1',
        title: 'Episode 1',
      );

      await expectLater(
        downloads.save(
          site: site(video: true, images: true),
          chapter: chapter,
          workTitle: 'Example',
        ),
        throwsA(isA<UnsupportedError>()),
      );

      await expectLater(
        downloads.saveBatch(
          site: site(video: true, images: true),
          workUrl: 'https://example.com/work',
          workTitle: 'Example',
          chapters: [chapter],
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(downloads.isBusy, isFalse);
    } finally {
      store.close();
      await root.delete(recursive: true);
    }
  });

  testWidgets('video hides image save controls without storage IO', (
    tester,
  ) async {
    final videoSite = site(video: true, images: true);
    final chapter = ruleSavedChapter(
      siteId: siteA,
      workUrl: 'https://example.com/work',
      chapterUrl: 'https://example.com/episode/1',
      title: 'Episode 1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RuleDownloadButton(
                site: videoSite,
                chapter: chapter,
                workTitle: 'Example',
                renderedFetcher:
                    (
                      input, {
                      required cancelToken,
                      required allowedOrigin,
                      required groupSelector,
                    }) async => throw StateError('must not fetch'),
              ),
              RuleBatchDownloadPanel(
                site: videoSite,
                workUrl: 'https://example.com/work',
                workTitle: 'Example',
                items: const [],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('作品のオフライン保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
