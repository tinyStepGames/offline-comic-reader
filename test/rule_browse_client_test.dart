import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

void main() {
  ListExtractionRule makeRule({
    String kind = 'works',
    String acquisition = 'staticHtml',
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
      localizeRelativeTime: true,
    );
    fields['latestChapter'] = const ListFieldRule(
      selector: '.latest',
      pattern: r'(\d+)',
      replacement: r'最新第$1話',
    );

    return ListExtractionRule(
      pageUrl: kind == 'works'
          ? 'https://example.com/list/'
          : 'https://example.com/work/sample/',
      groupSelector: kind == 'works' ? '.work' : '.chapter',
      fields: fields,
      kind: kind,
      acquisition: acquisition,
    );
  }

  SavedSiteRule makeSite({
    bool chapters = true,
    String acquisition = 'staticHtml',
  }) => SavedSiteRule(
    id: 'test',
    name: 'テストサイト',
    rules: {
      'works': makeRule(acquisition: acquisition),
      if (chapters) 'chapters': makeRule(kind: 'chapters'),
    },
    updatedAt: DateTime.utc(2026),
  );

  const workHtml = '''
    <div class="work">
      <a href="/work/selected/">作品A</a>
      <span class="date">2 hours ago</span>
      <span class="latest">Chapter 123</span>
    </div>
  ''';

  RuleBrowseClient clientFor(
    String source, {
    void Function(String input)? onFetch,
    String? returnedUrl,
  }) => RuleBrowseClient(
    fetcher: (input, {required cancelToken, required allowedOrigin}) async {
      onFetch?.call(input);
      return HtmlProbePage(
        uri: Uri.parse(returnedUrl ?? input),
        source: source,
        bytes: source.length,
      );
    },
  );

  test('保存URLから作品一覧を取得する', () async {
    String? requested;
    final client = clientFor(workHtml, onFetch: (input) => requested = input);
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(requested, 'https://example.com/list/');
    expect(result.items.single.title, '作品A');
    expect(
      result.items.single.url.toString(),
      'https://example.com/work/selected/',
    );
    expect(result.items.single.date, '2時間前');
    expect(result.items.single.latestChapter, '最新第123話');
    expect(result.items.single.issues, isEmpty);
  });

  test('チャプターはサンプルではなく選択作品のURLから取得する', () async {
    String? requested;
    final client = clientFor(
      '<div class="chapter"><a href="/chapter/1/">第1話</a></div>',
      onFetch: (input) => requested = input,
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(),
      kind: 'chapters',
      targetUrl: 'https://example.com/work/selected/',
      cancelToken: CancelToken(),
    );

    expect(requested, 'https://example.com/work/selected/');
    expect(requested, isNot('https://example.com/work/sample/'));
    expect(result.items.single.title, '第1話');
    expect(
      result.items.single.url.toString(),
      'https://example.com/chapter/1/',
    );
  });

  test('作品URLがない場合にサンプルURLへ勝手に戻さない', () async {
    var fetched = false;
    final client = clientFor('', onFetch: (_) => fetched = true);
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        kind: 'chapters',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
    expect(fetched, isFalse);
  });

  test('未設定のチャプター一覧は取得しない', () async {
    final client = clientFor('');
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(chapters: false),
        kind: 'chapters',
        targetUrl: 'https://example.com/work/selected/',
        cancelToken: CancelToken(),
      ),
      throwsStateError,
    );
  });

  test('描画後DOM設定を通常HTMLとして黙って実行しない', () async {
    var fetched = false;
    final client = clientFor('', onFetch: (_) => fetched = true);
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(acquisition: 'renderedDom'),
        kind: 'works',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
    expect(fetched, isFalse);
  });

  test('別の取得元への作品URLは通信前に拒否する', () async {
    var fetched = false;
    final client = clientFor('', onFetch: (_) => fetched = true);
    addTearDown(client.close);

    await expectLater(
      client.load(
        site: makeSite(),
        kind: 'chapters',
        targetUrl: 'https://other.example/work/selected/',
        cancelToken: CancelToken(),
      ),
      throwsFormatException,
    );
    expect(fetched, isFalse);
  });

  test('取得結果が別の取得元になった場合は拒否する', () async {
    final client = clientFor(
      workHtml,
      returnedUrl: 'https://other.example/list/',
    );
    addTearDown(client.close);

    await expectLater(
      client.load(site: makeSite(), kind: 'works', cancelToken: CancelToken()),
      throwsFormatException,
    );
  });

  test('同じ取得元の転送後URLを相対リンク解決に使う', () async {
    final client = clientFor(
      '<div class="work"><a href="selected/">作品A</a></div>',
      returnedUrl: 'https://example.com/work/',
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(
      result.items.single.url.toString(),
      'https://example.com/work/selected/',
    );
  });

  test('100件を超える一覧を黙って切り捨てない', () async {
    final html = List.generate(
      130,
      (index) =>
          '<div class="chapter"><a href="/chapter/$index/">第$index話</a></div>',
    ).join();

    final client = clientFor(html);
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(),
      kind: 'chapters',
      targetUrl: 'https://example.com/work/selected/',
      cancelToken: CancelToken(),
    );

    expect(result.total, 130);
    expect(result.items.length, 130);
  });

  test('別サイトの作品リンクは開けない状態で表示する', () async {
    final client = clientFor(
      '<div class="work"><a href="https://other.example/">外部</a></div>',
    );
    addTearDown(client.close);

    final result = await client.load(
      site: makeSite(),
      kind: 'works',
      cancelToken: CancelToken(),
    );

    expect(result.items.single.url, isNull);
    expect(result.items.single.issues, isNotEmpty);
  });

  test('キャンセル済みなら通信しない', () async {
    var fetched = false;
    final client = clientFor('', onFetch: (_) => fetched = true);
    addTearDown(client.close);
    final token = CancelToken()..cancel();

    await expectLater(
      client.load(site: makeSite(), kind: 'works', cancelToken: token),
      throwsStateError,
    );
    expect(fetched, isFalse);
  });
}
