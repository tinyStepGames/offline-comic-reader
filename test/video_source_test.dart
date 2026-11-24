import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/html_probe.dart';
import '../lib/services/list_extraction_rule.dart';
import '../lib/services/site_reading_settings.dart';
import '../lib/services/site_rule_store.dart';
import '../lib/services/video_source.dart';

VideoSourceSettings settings({VideoUrlSource source = VideoUrlSource.jsonLd}) =>
    VideoSourceSettings(
      pageUrl: 'https://example.com/episode/1',
      source: source,
      allowedOrigins: const ['https://media.example.com'],
    );

HtmlProbePage page(String source) => HtmlProbePage(
  uri: Uri.parse('https://example.com/episode/2'),
  source: source,
  bytes: source.length,
);

void main() {
  test('extracts contentUrl from nested VideoObject', () {
    final result = extractVideoUrls(
      page: page('''
<script type="application/ld+json">
{"@graph":[{"@type":"WebPage"},{"@type":"VideoObject",
"contentUrl":"https://media.example.com/a.m3u8?token=abc",
"thumbnailUrl":"https://media.example.com/cover.jpg"}]}
</script>
'''),
      settings: settings(),
    );

    expect(
      result.urls.single.toString(),
      'https://media.example.com/a.m3u8?token=abc',
    );
  });

  test('does not use poster embedUrl or blob as video content', () {
    final result = extractVideoUrls(
      page: page('''
<video poster="https://media.example.com/a.jpg" src="blob:https://example.com/a"></video>
<script type="application/ld+json">
{"@type":"VideoObject","embedUrl":"https://media.example.com/player"}
</script>
'''),
      settings: settings(),
    );

    expect(result.urls, isEmpty);

    final attributeResult = extractVideoUrls(
      page: page('<video src="blob:https://example.com/a"></video>'),
      settings: settings(source: VideoUrlSource.attribute),
    );
    expect(attributeResult.urls, isEmpty);
  });

  test('attribute mode does not silently fall back to structured data', () {
    final result = extractVideoUrls(
      page: page('''
<script type="application/ld+json">
{"@type":"VideoObject","contentUrl":"https://media.example.com/a.mp4"}
</script>
'''),
      settings: settings(source: VideoUrlSource.attribute),
    );
    expect(result.urls, isEmpty);
  });

  test('deduplicates URLs without dropping their query', () {
    final result = extractVideoUrls(
      page: page('''
<video src="https://media.example.com/a.mp4?q=1"></video>
<source src="https://media.example.com/a.mp4?q=1">
<source src="https://media.example.com/a.mp4?q=2">
'''),
      settings: settings(source: VideoUrlSource.attribute),
    );

    expect(result.urls, hasLength(2));
    expect(result.hasSingleUrl, isFalse);
    expect(result.issues.join(), contains('先頭を自動採用しません'));
  });

  test('rejects unapproved origins and insecure or credential URLs', () {
    final result = extractVideoUrls(
      page: page('''
<source src="https://other.example.com/a.mp4">
<source src="http://media.example.com/a.mp4">
<source src="https://user:pass@media.example.com/a.mp4">
<source src="file:///a.mp4">
'''),
      settings: settings(source: VideoUrlSource.attribute),
    );

    expect(result.urls, isEmpty);
  });

  test('rejects foreign HTML origin', () {
    expect(
      () => extractVideoUrls(
        page: HtmlProbePage(
          uri: Uri.parse('https://other.example.com/episode'),
          source: '',
          bytes: 0,
        ),
        settings: settings(),
      ),
      throwsFormatException,
    );
  });

  test('validates strict origin entries and site origin', () {
    expect(
      () => VideoSourceSettings(
        pageUrl: 'https://example.com/episode',
        allowedOrigins: const ['https://media.example.com/path'],
      ).validate(),
      throwsFormatException,
    );

    expect(
      () => settings().validateFor(['https://other.example.com/list']),
      throwsFormatException,
    );
  });

  test('old reading settings keep version 1 and default video null', () {
    const original = SiteReadingSettings(mode: SiteReadingMode.direct);
    final restored = SiteReadingSettings.fromJson(original.toJson());

    expect(original.toJson()['version'], 1);
    expect(restored.mode, SiteReadingMode.direct);
    expect(restored.video, isNull);
  });

  test('video settings round trip without changing opening mode', () {
    const original = SiteReadingSettings(mode: SiteReadingMode.direct);
    final changed = original.withVideo(settings());
    final restored = SiteReadingSettings.fromJson(changed.toJson());

    expect(changed.toJson()['version'], 2);
    expect(restored.mode, SiteReadingMode.direct);
    expect(restored.video!.toJson(), settings().toJson());
    expect(restored.withVideo(null).toJson(), original.toJson());
  });

  test('video cannot masquerade as old reading settings version', () {
    final data = const SiteReadingSettings().withVideo(settings()).toJson();
    data['version'] = 1;

    expect(() => SiteReadingSettings.fromJson(data), throwsFormatException);
  });

  test('saved site preserves nested video settings', () {
    final fields = defaultListFields();
    fields['title'] = const ListFieldRule(selector: '.title');
    fields['url'] = const ListFieldRule(
      selector: 'a',
      mode: ListValueMode.attribute,
      attribute: 'href',
    );

    final site = SavedSiteRule(
      id: 'AAAAAAAAAAAAAAAAAAAAAA',
      name: 'Video example',
      updatedAt: DateTime.utc(2026, 11, 24),
      rules: {
        'works': ListExtractionRule(
          pageUrl: 'https://example.com/list',
          groupSelector: '.item',
          fields: fields,
        ),
      },
      readingSettings: const SiteReadingSettings().withVideo(settings()),
    );

    final restored = SavedSiteRule.fromJson(site.toJson());

    expect(restored.id, site.id);
    expect(restored.readingSettings!.video!.toJson(), settings().toJson());
  });

  test('loads selected page, not configured sample', () async {
    String? requested;
    final client = VideoSourceClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        requested = input;
        expect(allowedOrigin, 'https://example.com');
        return page('''
<script type="application/ld+json">
{"@type":"VideoObject","contentUrl":"https://media.example.com/selected.m3u8"}
</script>
''');
      },
    );
    addTearDown(client.close);

    final result = await client.load(
      settings: settings(),
      targetUrl: 'https://example.com/episode/2',
      cancelToken: CancelToken(),
    );

    expect(requested, 'https://example.com/episode/2');
    expect(result.urls.single.path, '/selected.m3u8');
  });

  test('rejects foreign selected page before communication', () async {
    var calls = 0;
    final client = VideoSourceClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return page('');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        settings: settings(),
        targetUrl: 'https://other.example.com/episode',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });

  test('cancelled load does not communicate', () async {
    var calls = 0;
    final client = VideoSourceClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return page('');
      },
    );
    addTearDown(client.close);

    final token = CancelToken()..cancel('test');
    await expectLater(
      client.load(
        settings: settings(),
        targetUrl: 'https://example.com/episode/2',
        cancelToken: token,
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });
}
