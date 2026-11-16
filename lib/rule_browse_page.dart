import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rendered_rule_page.dart';
import 'services/html_probe.dart';
import 'rule_collection_grid.dart';
import 'services/rule_browse_client.dart';
import 'services/site_rule_store.dart';
import 'services/work_page_details.dart';
import 'work_details_panel.dart';

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

  bool _collection = false;
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
    final hasNumbers = _result!.items.any(
      (item) => parseChapterNumber(item.chapterNumber) != null,
    );

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
          DropdownButtonFormField<ChapterListOrder>(
            initialValue: _chapterOrder,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'チャプターの並び順',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: ChapterListOrder.source,
                child: Text('サイト順'),
              ),
              const DropdownMenuItem(
                value: ChapterListOrder.reverse,
                child: Text('サイト順の逆順'),
              ),
              DropdownMenuItem(
                value: ChapterListOrder.ascending,
                enabled: hasNumbers,
                child: const Text('話数の昇順'),
              ),
              DropdownMenuItem(
                value: ChapterListOrder.descending,
                enabled: hasNumbers,
                child: const Text('話数の降順'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _chapterOrder = value);
              }
            },
          ),
          if (!hasNumbers)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '数値順を使う場合は、サイトルールの'
                '「作品詳細・並び替え」で話数を設定してください。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  bool get _isWorks => widget.kind == 'works';

  @override
  void initState() {
    super.initState();

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
    final generation = ++_generation;
    _cancel?.cancel('再取得');
    final cancel = CancelToken();
    _cancel = cancel;

    setState(() {
      _busy = true;
      _result = null;
      _status = '${_isWorks ? '作品' : 'チャプター'}一覧を取得中';
    });

    try {
      final result = await _client.load(
        site: widget.site,
        kind: widget.kind,
        targetUrl: widget.targetUrl,
        cancelToken: cancel,
        renderedFetcher: _fetchRendered,
      );

      if (!mounted || generation != _generation || cancel.isCancelled) return;

      final warningRows = result.items.where((item) => item.url == null).length;

      setState(() {
        _result = result;
        _status = result.total == 0
            ? '一覧が見つかりませんでした。URLとまとまりの設定を確認してください。'
            : '${result.total}件を取得しました'
                  '${warningRows == 0 ? '' : '／要確認：$warningRows件'}';
      });
    } catch (error) {
      if (!mounted || generation != _generation || cancel.isCancelled) return;
      setState(() => _status = '取得できませんでした：$error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(RuleBrowseItem item) async {
    final url = item.url;
    if (_busy || url == null) return;

    if (_isWorks) {
      if (!widget.site.rules.containsKey('chapters')) {
        setState(() {
          _status = 'チャプター一覧が未設定です。サイトルール管理で設定してください';
        });
        return;
      }

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
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text(
                  '本文画像ルール・読書画面はまだ未接続です。'
                  '今回はチャプターのリンク確認まで行えます。',
                ),
                const SizedBox(height: 12),
                SelectableText(url.toString()),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: url.toString()),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('リンクをコピー'),
                ),
              ],
            ),
          ),
        ),
      );
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
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(_isWorks ? widget.site.name : widget.workTitle ?? 'チャプター一覧'),
      actions: [
        if (_isWorks)
          IconButton(
            tooltip: _collection ? 'Table表示に切り替え' : 'Collection表示に切り替え',
            onPressed: () => setState(() {
              _collection = !_collection;
            }),
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
        ],
      ),
    ),
  );
}
