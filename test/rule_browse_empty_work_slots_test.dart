import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

ListExtractionRule makeRule({
  String kind = 'works',
  String acquisition = 'staticHtml',
  bool thumbnails = false,
  bool badTitleTransform = false,
  bool badBothTransforms = false,
  bool pagination = false,
}) {
  final fields = defaultListFields();

  fields['title'] = ListFieldRule(
    selector: '.title',
    pattern: badTitleTransform || badBothTransforms ? r'^REQUIRED:(.*)$' : '',
    replacement: badTitleTransform || badBothTransforms ? r'$1' : '',
  );

  fields['url'] = ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
    pattern: badBothTransforms ? r'^REQUIRED:(.*)$' : '',
    replacement: badBothTransforms ? r'$1' : '',
  );

  if (thumbnails) {
    fields['thumbnail'] = const ListFieldRule(
      selector: 'img',
      mode: ListValueMode.attribute,
      attribute: 'src',
    );
  }

  return ListExtractionRule(
    pageUrl: kind == 'works'
        ? 'https://example.com/list/'
        : 'https://example.com/work/sample/',
    groupSelector: '.slot',
    fields: fields,
    kind: kind,
    acquisition: acquisition,
    paginationUrl: pagination ? 'https://example.com/list/?page={page;1}' : '',
  );
}

SavedSiteRule makeSite(ListExtractionRule rule) => SavedSiteRule(
  id: 'empty-slot-test',
  name: 'Empty slot test',
  rules: {rule.kind: rule},
  updatedAt: DateTime.utc(2026, 11, 22),
);

HtmlProbePage pageFor(String input, String source) =>
    HtmlProbePage(uri: Uri.parse(input), source: source, bytes: source.length);

RuleBrowseClient clientFor(String source) => RuleBrowseClient(
  fetcher: (input, {required cancelToken, required allowedOrigin}) async =>
      pageFor(input, source),
);

String work(int number) =>
    '<div class="slot">'
    '<a href="/work/$number/">'
    '<span class="title">Work $number</span>'
    '</a>'
    '</div>';

const emptySlot = '<div class="slot"></div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removes two empty layout slots but keeps all real works', () async {
    final source = '${work(1)}${work(2)}$emptySlot$emptySlot';
    final client = clientFor(source);
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule()),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.total, 4);
    expect(result.items.map((item) => item.title), ['Work 1', 'Work 2']);
    expect(result.items.every((item) => item.url != null), isTrue);
  });

  test('does not remove the last two valid works on page two', () async {
    var fetchCount = 0;
    final requests = <String>[];

    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        fetchCount++;
        requests.add(input);
        final pageNumber = Uri.parse(input).queryParameters['page'];
        final source = pageNumber == '2'
            ? '${work(3)}${work(4)}${work(5)}${work(6)}'
            : '${work(1)}${work(2)}$emptySlot$emptySlot';
        return pageFor(input, source);
      },
    );
    addTearDown(client.close);

    final site = makeSite(makeRule(pagination: true));

    final first = await client.load(
      site: site,
      kind: 'works',
      cancelToken: CancelToken(),
    );

    final second = await client.load(
      site: site,
      kind: 'works',
      pageNumber: 2,
      cancelToken: CancelToken(),
    );

    expect(first.total, 4);
    expect(first.items.length, 2);
    expect(second.total, 4);
    expect(second.items.map((item) => item.title), [
      'Work 3',
      'Work 4',
      'Work 5',
      'Work 6',
    ]);
    expect(fetchCount, 2);
    expect(Uri.parse(requests.last).queryParameters['page'], '2');
  });

  test('keeps a real work when only its thumbnail is missing', () async {
    final client = clientFor(work(1));
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule(thumbnails: true)),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.title, 'Work 1');
    expect(result.items.single.url, isNotNull);
    expect(result.items.single.thumbnail, isNull);
  });

  test('keeps title-only items for diagnosis', () async {
    final client = clientFor(
      '<div class="slot"><span class="title">Title only</span></div>',
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule()),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.title, 'Title only');
    expect(result.items.single.url, isNull);
    expect(result.items.single.issues, isNotEmpty);
  });

  test('keeps link-only items for diagnosis', () async {
    final client = clientFor('<div class="slot"><a href="/work/1/"></a></div>');
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule()),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.url, isNull);
    expect(result.items.single.issues, isNotEmpty);
  });

  test(
    'keeps thumbnail-only items rather than hiding incomplete works',
    () async {
      final client = clientFor(
        '<div class="slot"><img src="/cover.jpg"></div>',
      );
      addTearDown(client.close);

      final result = await client.load(
        site: makeSite(makeRule(thumbnails: true)),
        kind: 'works',
        cancelToken: CancelToken(),
      );

      expect(result.items, hasLength(1));
      expect(
        result.items.single.thumbnail,
        Uri.parse('https://example.com/cover.jpg'),
      );
      expect(result.items.single.issues, isNotEmpty);
    },
  );

  test('keeps invalid external work links for diagnosis', () async {
    final client = clientFor(
      '<div class="slot">'
      '<a href="https://other.example/work/">'
      '<span class="title">External work</span>'
      '</a></div>',
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule()),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.url, isNull);
    expect(result.items.single.issues, isNotEmpty);
  });

  test(
    'does not hide an empty result caused by transformation errors',
    () async {
      final rule = makeRule(badBothTransforms: true);
      final source = work(1);

      // Both transformed fields are empty, but processing errors must remain.
      final report = extractListRows(pageFor(rule.pageUrl, source), rule);
      expect(report.rows.single.values['title'], isEmpty);
      expect(report.rows.single.values['url'], isEmpty);
      expect(
        report.rows.single.issues.any(
          (issue) => issue != 'タイトル：取得できません' && issue != 'リンク：取得できません',
        ),
        isTrue,
      );

      final client = clientFor(source);
      addTearDown(client.close);

      final result = await client.load(
        site: makeSite(rule),
        kind: 'works',
        cancelToken: CancelToken(),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.issues, isNotEmpty);
    },
  );

  test('leaves raw extraction diagnostics available to the rule editor', () {
    final rule = makeRule();
    final report = extractListRows(
      pageFor(rule.pageUrl, '${work(1)}$emptySlot$emptySlot'),
      rule,
      collectCandidates: true,
    );

    expect(report.total, 3);
    expect(report.rows, hasLength(3));
    expect(report.rows[1].values['title'], isEmpty);
    expect(report.rows[1].values['url'], isEmpty);
    expect(report.rows[1].issues, isNotEmpty);
    expect(report.rows[1].matchCounts['title'], 0);
  });

  test('does not filter empty chapter rows', () async {
    final client = clientFor('${work(1)}$emptySlot');
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule(kind: 'chapters')),
      kind: 'chapters',
      targetUrl: 'https://example.com/work/selected/',
      cancelToken: CancelToken(),
    );

    expect(result.total, 2);
    expect(result.items, hasLength(2));
    expect(result.items.last.url, isNull);
    expect(result.items.last.issues, isNotEmpty);
  });

  test(
    'applies the same filter to rendered HTML without extra fetches',
    () async {
      var staticFetches = 0;
      var renderedFetches = 0;

      final client = RuleBrowseClient(
        fetcher: (input, {required cancelToken, required allowedOrigin}) async {
          staticFetches++;
          throw StateError('Static fetch must not run');
        },
      );
      addTearDown(client.close);

      final result = await client.load(
        site: makeSite(makeRule(acquisition: 'renderedDom')),
        kind: 'works',
        cancelToken: CancelToken(),
        renderedFetcher:
            (
              input, {
              required cancelToken,
              required allowedOrigin,
              required groupSelector,
            }) async {
              renderedFetches++;
              expect(groupSelector, '.slot');
              return pageFor(input, '${work(1)}$emptySlot$emptySlot');
            },
      );

      expect(staticFetches, 0);
      expect(renderedFetches, 1);
      expect(result.total, 3);
      expect(result.items, hasLength(1));
    },
  );

  test(
    'all-empty groups return no display items but preserve raw total',
    () async {
      final client = clientFor('$emptySlot$emptySlot');
      addTearDown(client.close);

      final result = await client.load(
        site: makeSite(makeRule()),
        kind: 'works',
        cancelToken: CancelToken(),
      );

      expect(result.total, 2);
      expect(result.items, isEmpty);
    },
  );

  test('a page without matching groups still returns zero', () async {
    final client = clientFor('<main>No results</main>');
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(makeRule()),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.total, 0);
    expect(result.items, isEmpty);
  });

  test('network failures are not converted into empty success', () async {
    final client = RuleBrowseClient(
      fetcher: (input, {required cancelToken, required allowedOrigin}) async {
        throw StateError('Network failed');
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(makeRule()),
        kind: 'works',
        cancelToken: CancelToken(),
      ),
      throwsStateError,
    );
  });
}
