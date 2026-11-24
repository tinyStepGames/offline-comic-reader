import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/chapterless_work.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_reading_settings.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

SavedSiteRule makeSite({
  ListFieldRule? link,
  String acquisition = 'staticHtml',
}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'Gallery',
  updatedAt: DateTime.utc(2026),
  rules: {
    'works': ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.item',
      fields: defaultListFields(),
    ),
  },
  readingSettings: SiteReadingSettings(
    mode: SiteReadingMode.details,
    detailsRule: ListExtractionRule(
      pageUrl: 'https://example.com/sample/',
      groupSelector: 'html',
      fields: defaultListFields(),
      acquisition: acquisition,
      details: const {
        'title': ListFieldRule(selector: 'h1'),
        'description': ListFieldRule(selector: '.description'),
        'tags': ListFieldRule(selector: '.tags a'),
      },
    ),
    readLink: link,
  ),
);

HtmlProbePage makePage(String source, {String? url}) => HtmlProbePage(
  uri: Uri.parse(url ?? 'https://example.com/selected/'),
  source: source,
  bytes: utf8.encode(source).length,
);

const linkRule = ListFieldRule(
  selector: 'a.read',
  mode: ListValueMode.attribute,
  attribute: 'href',
);

void main() {
  test('fetch selected URL once, not sample URL', () async {
    var calls = 0;
    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        expect(input, 'https://example.com/selected/');
        expect(allowedOrigin, 'https://example.com');
        return makePage(
          '<h1>Selected</h1><div class="description">Description</div>'
          '<div class="tags"><a href="/tag/a">Tag A</a></div>',
        );
      },
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(),
      targetUrl: 'https://example.com/selected/',
      cancelToken: CancelToken(),
    );

    expect(calls, 1);
    expect(result.details.title, 'Selected');
    expect(result.details.description, 'Description');
    expect(result.details.tags, ['Tag A']);
    expect(result.details.tagLinks, hasLength(1));
    expect(result.readUrl.toString(), 'https://example.com/selected/');
  });

  test('relative read URL honors page base URL', () async {
    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makePage(
            '<base href="/viewer/"><h1>Title</h1>'
            '<a class="read" href="one/">Read</a>',
          ),
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(link: linkRule),
      targetUrl: 'https://example.com/selected/',
      cancelToken: CancelToken(),
    );

    expect(result.readUrl.toString(), 'https://example.com/viewer/one/');
    expect(result.readIssue, isNull);
  });

  for (final entry in <String, String>{
    'missing': '<h1>Title</h1>',
    'empty': '<h1>Title</h1><a class="read" href="">Read</a>',
    'multiple':
        '<h1>Title</h1><a class="read" href="/a">A</a>'
        '<a class="read" href="/b">B</a>',
    'other origin':
        '<h1>Title</h1><a class="read" href="https://other.example/a">Read</a>',
    'HTTP':
        '<h1>Title</h1><a class="read" href="http://example.com/a">Read</a>',
  }.entries) {
    test(
      'invalid read link keeps details but disables reading: ${entry.key}',
      () async {
        final client = ChapterlessWorkClient(
          fetcher:
              (input, {required cancelToken, required allowedOrigin}) async =>
                  makePage(entry.value),
        );
        addTearDown(client.close);

        final result = await client.load(
          site: makeSite(link: linkRule),
          targetUrl: 'https://example.com/selected/',
          cancelToken: CancelToken(),
        );

        expect(result.details.title, 'Title');
        expect(result.readUrl, isNull);
        expect(result.readIssue, isNotEmpty);
      },
    );
  }

  test('rendered mode uses rendered fetcher only', () async {
    var staticCalls = 0;
    var renderedCalls = 0;

    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        staticCalls++;
        throw StateError('must not fetch static HTML');
      },
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(acquisition: 'renderedDom'),
      targetUrl: 'https://example.com/selected/',
      cancelToken: CancelToken(),
      renderedFetcher:
          (
            input, {
            required cancelToken,
            required allowedOrigin,
            required groupSelector,
          }) async {
            renderedCalls++;
            expect(groupSelector, contains('h1'));
            return makePage('<h1>Rendered</h1>');
          },
    );

    expect(staticCalls, 0);
    expect(renderedCalls, 1);
    expect(result.details.title, 'Rendered');
  });

  test('rendered error has no automatic static fallback', () async {
    var calls = 0;
    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makePage('<h1>Unexpected</h1>');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(acquisition: 'renderedDom'),
        targetUrl: 'https://example.com/selected/',
        cancelToken: CancelToken(),
        renderedFetcher:
            (
              input, {
              required cancelToken,
              required allowedOrigin,
              required groupSelector,
            }) async => throw StateError('render failure'),
      ),
      throwsStateError,
    );

    expect(calls, 0);
  });

  test('cross-origin target rejected before fetching', () async {
    var calls = 0;
    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        calls++;
        return makePage('<h1>Unexpected</h1>');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        targetUrl: 'https://other.example/work/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );

    expect(calls, 0);
  });

  test('cross-origin redirected HTML rejected', () async {
    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
          makePage('<h1>Wrong</h1>', url: 'https://other.example/work/'),
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        targetUrl: 'https://example.com/selected/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
  });

  test('cancelled result rejected', () async {
    final token = CancelToken();

    final client = ChapterlessWorkClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        cancelToken.cancel();
        return makePage('<h1>Cancelled</h1>');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        targetUrl: 'https://example.com/selected/',
        cancelToken: token,
      ),
      throwsStateError,
    );
  });

  test('reader contains one work, not adjacent works', () {
    final item = RuleBrowseItem(
      title: 'Gallery',
      url: Uri.parse('https://example.com/detail/'),
      thumbnail: null,
      date: '',
      latestChapter: '',
      issues: const [],
    );

    final items = singleWorkReaderItems(
      item: item,
      readUrl: Uri.parse('https://example.com/viewer/'),
    );

    expect(items, hasLength(1));
    expect(items.single.title, 'Gallery');
    expect(items.single.url.toString(), 'https://example.com/viewer/');
    expect(() => items.clear(), throwsUnsupportedError);
  });

  test('reader rejects missing URL', () {
    const item = RuleBrowseItem(
      title: 'Gallery',
      url: null,
      thumbnail: null,
      date: '',
      latestChapter: '',
      issues: [],
    );

    expect(() => singleWorkReaderItems(item: item), throwsFormatException);
  });
}
