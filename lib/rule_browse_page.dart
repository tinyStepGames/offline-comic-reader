import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/rule_browse_client.dart';
import 'services/site_rule_store.dart';

class RuleBrowsePage extends StatefulWidget {
  const RuleBrowsePage({
    super.key,
    required this.site,
    this.kind = 'works',
    this.targetUrl,
    this.workTitle,
  });

  final SavedSiteRule site;
  final String kind;
  final String? targetUrl;
  final String? workTitle;

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

  bool get _isWorks => widget.kind == 'works';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _cancel?.cancel('再取得');
    final cancel = CancelToken();
    _cancel = cancel;

    setState(() {
      _busy = true;
      _result = null;
      _status = '通常HTMLから${_isWorks ? '作品' : 'チャプター'}一覧を取得中';
    });

    try {
      final result = await _client.load(
        site: widget.site,
        kind: widget.kind,
        targetUrl: widget.targetUrl,
        cancelToken: cancel,
      );

      if (!mounted || generation != _generation || cancel.isCancelled) return;

      final warningRows = result.items
          .where((item) => item.issues.isNotEmpty)
          .length;

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
                  if (item.issues.isNotEmpty) ...[
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

  Widget _header() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 3,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
        const SizedBox(height: 12),
        SelectableText(
          _status,
          style: const TextStyle(color: Colors.tealAccent),
        ),
        const SizedBox(height: 8),
        Text(
          _isWorks
              ? '作品を選ぶと、そのURLからチャプター一覧を取得します。'
              : 'チャプターを選ぶとリンクを確認できます。本文表示は未接続です。',
          style: const TextStyle(color: Colors.white60),
        ),
        if (_result != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            '取得URL：${_result!.pageUri}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ],
    ),
  );

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
        IconButton(
          tooltip: '再読み込み',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 1 + (_result?.items.length ?? 0),
        itemBuilder: (_, index) =>
            index == 0 ? _header() : _item(_result!.items[index - 1]),
      ),
    ),
  );
}
