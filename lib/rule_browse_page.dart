import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rendered_rule_page.dart';
import 'services/html_probe.dart';
import 'rule_collection_grid.dart';
import 'services/rule_browse_client.dart';
import 'services/site_rule_store.dart';
import 'services/rule_layout_store.dart';
import 'services/page_url_template.dart';
import 'services/work_page_details.dart';
import 'services/chapter_reading_order.dart';
import 'work_details_panel.dart';
import 'rule_online_reader_page.dart';
import 'rule_download_button.dart';
import 'rule_saved_downloads_page.dart';
import 'services/rule_downloads.dart';

class RuleBrowsePage extends StatefulWidget {
  const RuleBrowsePage({
    super.key,
    required this.site,
    this.kind = 'works',
    this.targetUrl,
    this.workTitle,
    this.workThumbnail,
  });

  final SavedSiteRule site;
  final String kind;
  final String? targetUrl;
  final String? workTitle;
  final Uri? workThumbnail;

  @override
  State<RuleBrowsePage> createState() => _RuleBrowsePageState();
}

class _RuleBrowsePageState extends State<RuleBrowsePage> {
  final _client = RuleBrowseClient();
  CancelToken? _cancel;
  RuleBrowseResult? _result;
  bool _busy = true;
  String _status = '取得準備中';
  int _generation = 0;
  final _scrollController = ScrollController();
  bool _moreBusy = false;
  bool _hasMore = false;
  int _lastPage = 0;
  int _pagesLoaded = 0;
  String _moreError = '';
  String _pagingEnd = '';

  PageUrlTemplate? get _pagination {
    if (!_isWorks) return null;
    final value = widget.site.rules['works']?.paginationUrl ?? '';
    return value.isEmpty ? null : PageUrlTemplate(value);
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_scrollController.position.isScrollingNotifier.value ||
        ModalRoute.of(context)?.isCurrent != true ||
        widget.site.rules['works']?.acquisition != 'staticHtml' ||
        _moreError.isNotEmpty) {
      return;
    }

    final position = _scrollController.position;
    if (position.maxScrollExtent > 0 && position.extentAfter < 350) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final pagination = _pagination;
    final current = _result;
    final cancel = _cancel;

    if (pagination == null ||
        current == null ||
        cancel == null ||
        cancel.isCancelled ||
        _busy ||
        _moreBusy ||
        !_hasMore ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final generation = _generation;
    final nextPage = _lastPage + 1;

    setState(() {
      _moreBusy = true;
      _moreError = '';
    });

    try {
      final next = await _client.load(
        site: widget.site,
        kind: 'works',
        pageNumber: nextPage,
        cancelToken: cancel,
        renderedFetcher: _fetchRendered,
      );

      if (!mounted || generation != _generation || cancel.isCancelled) {
        return;
      }

      // ページ間で重複する作品URLは追加しない。
      // 追加ページのリンク不正項目は採用しない。
      final seen = current.items
          .where((item) => item.url != null)
          .map((item) => item.url!.removeFragment().toString())
          .toSet();

      final added = <RuleBrowseItem>[];
      for (final item in next.items) {
        final url = item.url;
        if (url == null) continue;
        if (seen.add(url.removeFragment().toString())) {
          added.add(item);
        }
      }

      final available = 10000 - current.items.length;
      final accepted = available > 0
          ? added.take(available).toList()
          : <RuleBrowseItem>[];
      final merged = [...current.items, ...accepted];

      setState(() {
        _lastPage = nextPage;
        _pagesLoaded++;
        _result = RuleBrowseResult(
          pageUri: current.pageUri,
          total: merged.length,
          items: List.unmodifiable(merged),
          workDetails: current.workDetails,
        );

        _hasMore =
            accepted.isNotEmpty &&
            _pagesLoaded < 100 &&
            merged.length < 10000 &&
            nextPage < PageUrlTemplate.maxPage;

        if (next.total == 0) {
          _pagingEnd = '次のページに作品が見つかりませんでした。';
        } else if (accepted.isEmpty) {
          _pagingEnd = '新しい作品がなかったため、追加取得を停止しました。';
        } else if (!_hasMore) {
          _pagingEnd = '今回の閲覧での取得上限に達しました。';
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation || cancel.isCancelled) {
        return;
      }
      setState(() {
        _moreError = '次のページを取得できませんでした：$error';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _moreBusy = false);
      }
    }
  }

  Widget _pagingFooter() {
    if (!_isWorks || _pagination == null || _busy || _result == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        children: [
          if (_moreBusy)
            const SizedBox(
              height: 56,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_hasMore) ...[
            if (_moreError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _moreError,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _loadMore,
              icon: Icon(
                _moreError.isEmpty ? Icons.expand_more : Icons.refresh,
              ),
              label: Text(_moreError.isEmpty ? '続きを読む' : '再試行'),
            ),
          ] else if (_pagingEnd.isNotEmpty)
            Text(_pagingEnd, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  bool _collection = false;
  bool _openingItem = false;
  bool _layoutReady = false;
  final _layoutStore = RuleLayoutStore();

  Future<void> _restoreLayout() async {
    if (_layoutReady) return;

    final collection = _isWorks
        ? await _layoutStore.read(widget.site.id)
        : false;

    if (!mounted) return;
    setState(() {
      _collection = collection;
      _layoutReady = true;
    });
  }

  Future<void> _toggleLayout() async {
    if (!_layoutReady) return;

    final collection = !_collection;
    setState(() => _collection = collection);

    try {
      await _layoutStore.write(widget.site.id, collection);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('表示形式を保存できませんでした。次回は元の表示に戻る場合があります。')),
      );
    }
  }

  ChapterListOrder _chapterOrder = ChapterListOrder.source;

  List<RuleBrowseItem> get _visibleItems => _isWorks
      ? (_result?.items ?? const <RuleBrowseItem>[])
      : sortChapterItems<RuleBrowseItem>(
          _result?.items ?? const <RuleBrowseItem>[],
          (item) => item.chapterNumber,
          _chapterOrder,
        );

  Widget _workSection() {
    final details = _result!.workDetails;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkDetailsPanel(
            details: details,
            fallbackTitle: widget.workTitle ?? '',
            fallbackThumbnail: widget.workThumbnail,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'チャプターの並び順',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _chapterOrder == ChapterListOrder.reverse ? '降順' : '昇順',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: _chapterOrder == ChapterListOrder.reverse
                    ? '昇順に切り替え'
                    : '降順に切り替え',
                onPressed: () {
                  setState(() {
                    _chapterOrder = _chapterOrder == ChapterListOrder.reverse
                        ? ChapterListOrder.source
                        : ChapterListOrder.reverse;
                  });
                },
                icon: const Icon(Icons.swap_vert),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _isWorks => widget.kind == 'works';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _load();
    });
  }

  Future<HtmlProbePage> _fetchRendered(
    String input, {
    required CancelToken cancelToken,
    required String allowedOrigin,
    required String groupSelector,
  }) async {
    if (!mounted || cancelToken.isCancelled) {
      throw StateError('取得を中止しました');
    }

    // 呼び出し元の描画処理が終わってから取得画面を開く。
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted || cancelToken.isCancelled) {
      throw StateError('取得を中止しました');
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      throw StateError('一覧画面を離れたため取得を中止しました');
    }

    final page = await Navigator.of(context).push<HtmlProbePage>(
      MaterialPageRoute<HtmlProbePage>(
        builder: (_) => RenderedRulePage(
          backgroundMode: true,
          previewTitle: widget.workTitle ?? widget.site.name,
          previewThumbnail: widget.workThumbnail,
          url: input,
          allowedOrigin: allowedOrigin,
          groupSelector: groupSelector,
          cancelToken: cancelToken,
        ),
      ),
    );

    if (page == null || cancelToken.isCancelled) {
      throw StateError('表示後HTMLの取得を中止しました');
    }
    return page;
  }

  Future<void> _load() async {
    await _restoreLayout();
    if (!mounted) return;

    final generation = ++_generation;
    _cancel?.cancel('再取得');
    final cancel = CancelToken();
    _cancel = cancel;

    setState(() {
      _busy = true;
      _moreBusy = false;
      _hasMore = false;
      _moreError = '';
      _pagingEnd = '';
      _pagesLoaded = 0;
      _result = null;
      _status = '${_isWorks ? '作品' : 'チャプター'}一覧を取得中';
    });

    try {
      final pagination = _pagination;
      final result = await _client.load(
        site: widget.site,
        kind: widget.kind,
        targetUrl: widget.targetUrl,
        cancelToken: cancel,
        renderedFetcher: _fetchRendered,
      );

      if (!mounted || generation != _generation || cancel.isCancelled) {
        return;
      }

      // 最初のページ内の重複URLも除く。
      // リンク不正の項目は設定確認用として残す。
      final seen = <String>{};
      final items = result.items.where((item) {
        if (!_isWorks || item.url == null) return true;
        return seen.add(item.url!.removeFragment().toString());
      }).toList();

      setState(() {
        _result = RuleBrowseResult(
          pageUri: result.pageUri,
          total: items.length,
          items: List.unmodifiable(items),
          workDetails: result.workDetails,
        );
        _lastPage = pagination?.start ?? 0;
        _pagesLoaded = 1;
        _hasMore =
            pagination != null &&
            items.any((item) => item.url != null) &&
            _lastPage < PageUrlTemplate.maxPage;

        _status = items.isEmpty
            ? '一覧が見つかりませんでした。URLとまとまりの設定を確認してください。'
            : '${items.length}件を取得しました';
      });
    } catch (error) {
      if (!mounted || generation != _generation || cancel.isCancelled) {
        return;
      }
      setState(() => _status = '取得できませんでした：$error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(RuleBrowseItem item) async {
    if (_busy || _openingItem) return;

    final url = item.url;
    if (url == null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('リンクを開けません'),
          content: SingleChildScrollView(
            child: Text(
              item.issues.isEmpty
                  ? 'URLが取得できていません。リンクの設定を確認してください。'
                  : item.issues.join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }

    final missing = _isWorks
        ? !widget.site.rules.containsKey('chapters')
        : widget.site.images == null;

    if (missing) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_isWorks ? 'チャプター一覧が未設定です' : '本文画像が未設定です'),
          content: const Text(
            'サイトルール管理から対象サイトの設定を追加してください。'
            'URLは下のボタンからコピーできます。',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url.toString()));
              },
              child: const Text('URLをコピー'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }

    _openingItem = true;

    try {
      if (_isWorks) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => RuleBrowsePage(
              site: widget.site,
              kind: 'chapters',
              targetUrl: url.toString(),
              workTitle: item.title,
              workThumbnail: item.thumbnail,
            ),
          ),
        );
      } else {
        // 一覧の表示順に依存しない、話数順のスナップショットを渡す。
        // リンク不正・同じURLの重複項目は前後移動から除外する。
        final seen = <String>{};
        final chapters =
            chapterReadingOrder<RuleBrowseItem>(
              _result?.items ?? const <RuleBrowseItem>[],
              titleOf: (chapter) => chapter.title,
              explicitNumberOf: (chapter) => chapter.chapterNumber,
            ).where((chapter) {
              final chapterUrl = chapter.url;
              if (chapterUrl == null) return false;
              return seen.add(chapterUrl.removeFragment().toString());
            }).toList();

        final selectedUrl = url.removeFragment().toString();
        final selectedIndex = chapters.indexWhere(
          (chapter) => chapter.url!.removeFragment().toString() == selectedUrl,
        );

        if (selectedIndex < 0) {
          throw StateError('選択したチャプターが一覧に見つかりません');
        }

        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => RuleOnlineReaderPage(
              site: widget.site,
              chapters: List.unmodifiable(chapters),
              initialIndex: selectedIndex,
              workThumbnail: widget.workThumbnail,
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('画面を開けませんでした：$error')));
      }
    } finally {
      _openingItem = false;
    }
  }

  Widget _cover(RuleBrowseItem item) => SizedBox(
    width: 64,
    height: 88,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: item.thumbnail == null
          ? const ColoredBox(
              color: Colors.white10,
              child: Icon(Icons.image_outlined),
            )
          : Image.network(
              item.thumbnail.toString(),
              fit: BoxFit.cover,
              cacheWidth: 192,
              errorBuilder: (_, error, stack) => const ColoredBox(
                color: Colors.white10,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
    ),
  );

  Widget _item(RuleBrowseItem item) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: item.url == null ? null : () => _open(item),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isWorks) ...[_cover(item), const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (item.latestChapter.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.latestChapter),
                  ],
                  if (item.date.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.date,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                  if (item.url == null && item.issues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.issues.join('\n'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!_isWorks && item.url != null && widget.targetUrl != null)
              RuleDownloadButton(
                site: widget.site,
                chapter: ruleSavedChapter(
                  siteId: widget.site.id,
                  workUrl: widget.targetUrl!,
                  chapterUrl: item.url!.toString(),
                  title: item.title,
                  publishedDateText: item.date,
                ),
                workTitle: widget.workTitle ?? '',
                renderedFetcher: _fetchRendered,
              )
            else
              Icon(
                item.url == null
                    ? Icons.warning_amber_outlined
                    : _isWorks
                    ? Icons.chevron_right
                    : Icons.link,
              ),
          ],
        ),
      ),
    ),
  );

  Widget _header() {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: SizedBox(height: 3, child: LinearProgressIndicator()),
      );
    }

    // 正常に一覧を表示できた場合、件数・取得URL・説明は表示しない。
    // 一覧を表示できない場合や、後から操作エラーになった場合は案内を残す。
    final hasItems = _result?.items.isNotEmpty ?? false;
    final normalResult = _status.contains('件を取得しました');

    if (hasItems && normalResult) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SelectableText(
        _status,
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _cancel?.cancel('画面終了');
    _scrollController.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(_isWorks ? widget.site.name : widget.workTitle ?? 'チャプター一覧'),
      actions: [
        IconButton(
          tooltip: '保存済みを開く',
          onPressed: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => RuleSavedDownloadsPage(site: widget.site),
              ),
            );
          },
          icon: const Icon(Icons.folder_outlined),
        ),
        if (_isWorks)
          IconButton(
            tooltip: _collection ? 'Table表示に切り替え' : 'Collection表示に切り替え',
            onPressed: _layoutReady ? _toggleLayout : null,
            icon: Icon(
              _collection ? Icons.view_list_outlined : Icons.grid_view_outlined,
            ),
          ),
        IconButton(
          tooltip: '再読み込み',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: CustomScrollView(
        controller: _scrollController,
        key: PageStorageKey<String>(
          '${widget.site.id}:${widget.kind}:'
          '${widget.targetUrl ?? ''}:'
          '${_isWorks && _collection ? 'collection' : 'table'}',
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(child: _header()),
          ),
          if (!_isWorks && !_busy && _result != null)
            SliverToBoxAdapter(child: _workSection()),
          if (_isWorks && _collection)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: RuleCollectionSliver(
                items: _result?.items ?? const <RuleBrowseItem>[],
                onOpen: _open,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, index) => _item(_visibleItems[index]),
                  childCount: _result?.items.length ?? 0,
                ),
              ),
            ),
          SliverToBoxAdapter(child: _pagingFooter()),
        ],
      ),
    ),
  );
}
