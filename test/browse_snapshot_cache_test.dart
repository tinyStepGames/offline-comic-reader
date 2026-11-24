import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/browse_snapshot_cache.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_browse_client.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

RuleBrowseItem sampleItem(int index) => RuleBrowseItem(
  title: '作品$index',
  url: Uri.parse('https://example.com/work/$index/'),
  thumbnail: null,
  date: '',
  latestChapter: '',
  issues: const [],
);

BrowseSnapshot snapshotAt(DateTime time, {int count = 1, int pages = 1}) =>
    BrowseSnapshot(
      result: RuleBrowseResult(
        pageUri: Uri.parse('https://example.com/list/'),
        total: count,
        items: List.generate(count, sampleItem),
      ),
      fetchedAt: time,
      lastPage: pages,
      pagesLoaded: pages,
      hasMore: true,
      pagingEnd: '',
      scrollOffset: 120,
      collection: true,
    );

SavedSiteRule siteAt({
  String url = 'https://example.com/list/',
  String selector = '.card',
  DateTime? updatedAt,
}) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'キャッシュテスト',
  updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  rules: {
    'works': ListExtractionRule(
      pageUrl: url,
      groupSelector: selector,
      fields: defaultListFields(),
    ),
  },
);

String keyFor(SavedSiteRule site, {String kind = 'works', String? target}) =>
    browseSnapshotKey(site: site, kind: kind, targetUrl: target);

void main() {
  test('期限内は一覧・追加ページ数・表示位置を保持する', () {
    final now = DateTime.utc(2026, 1, 1);
    final cache = BrowseSnapshotCache(now: () => now);

    cache.put('a', snapshotAt(now, count: 3, pages: 2));

    final restored = cache.get('a')!;

    expect(restored.result.items.length, 3);
    expect(restored.pagesLoaded, 2);
    expect(restored.lastPage, 2);
    expect(restored.scrollOffset, 120);
    expect(restored.collection, isTrue);
  });

  test('60秒に達したキャッシュを返さない', () {
    var now = DateTime.utc(2026, 1, 1);
    final fetchedAt = now;
    final cache = BrowseSnapshotCache(now: () => now);

    cache.put('a', snapshotAt(fetchedAt));

    now = now.add(const Duration(seconds: 59));
    expect(cache.get('a'), isNotNull);

    now = now.add(const Duration(seconds: 1));
    expect(cache.get('a'), isNull);
  });

  test('保存し直しても取得日時からの期限を延長しない', () {
    var now = DateTime.utc(2026, 1, 1);
    final original = snapshotAt(now);
    final cache = BrowseSnapshotCache(now: () => now);

    cache.put('a', original);

    now = now.add(const Duration(seconds: 50));
    cache.put('a', original);

    now = now.add(const Duration(seconds: 10));
    expect(cache.get('a'), isNull);
  });

  test('検索語が違うURLを区別する', () {
    expect(
      keyFor(siteAt(url: 'https://example.com/?q=mahou')),
      isNot(keyFor(siteAt(url: 'https://example.com/?q=gakuen'))),
    );
  });

  test('同じURLでもセレクター変更を区別する', () {
    expect(
      keyFor(siteAt(selector: '.old')),
      isNot(keyFor(siteAt(selector: '.new'))),
    );
  });

  test('サイト設定の更新日時を区別する', () {
    expect(
      keyFor(siteAt(updatedAt: DateTime.utc(2026, 1, 1))),
      isNot(keyFor(siteAt(updatedAt: DateTime.utc(2026, 1, 2)))),
    );
  });

  test('作品一覧とチャプター一覧・選択作品URLを区別する', () {
    final site = siteAt();

    expect(
      keyFor(site),
      isNot(
        keyFor(site, kind: 'chapters', target: 'https://example.com/work/1/'),
      ),
    );

    expect(
      keyFor(site, kind: 'chapters', target: 'https://example.com/work/1/'),
      isNot(
        keyFor(site, kind: 'chapters', target: 'https://example.com/work/2/'),
      ),
    );
  });

  test('件数上限に達したら最近使っていないものを削除する', () {
    final now = DateTime.utc(2026, 1, 1);
    final cache = BrowseSnapshotCache(now: () => now, maxEntries: 2);

    cache.put('a', snapshotAt(now));
    cache.put('b', snapshotAt(now));

    expect(cache.get('a'), isNotNull);

    cache.put('c', snapshotAt(now));

    expect(cache.get('b'), isNull);
    expect(cache.get('a'), isNotNull);
    expect(cache.get('c'), isNotNull);
  });

  test('全体の項目数上限を超えたら古い一覧を削除する', () {
    final now = DateTime.utc(2026, 1, 1);
    final cache = BrowseSnapshotCache(now: () => now, maxItems: 3);

    cache.put('a', snapshotAt(now, count: 2));
    cache.put('b', snapshotAt(now, count: 2));

    expect(cache.get('a'), isNull);
    expect(cache.get('b'), isNotNull);
  });

  test('空の一覧はキャッシュしない', () {
    final now = DateTime.utc(2026, 1, 1);
    final cache = BrowseSnapshotCache(now: () => now);

    cache.put('empty', snapshotAt(now, count: 0));

    expect(cache.get('empty'), isNull);
  });

  test('更新操作で指定キャッシュを破棄できる', () {
    final now = DateTime.utc(2026, 1, 1);
    final cache = BrowseSnapshotCache(now: () => now);

    cache.put('a', snapshotAt(now));
    cache.remove('a');

    expect(cache.get('a'), isNull);
  });
}
