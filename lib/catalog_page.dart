import 'package:flutter/material.dart';

import 'chapter_reader_page.dart';
import 'services/download_store.dart';
import 'sources/source_adapter.dart';

class SourceHome extends StatefulWidget {
  const SourceHome({super.key, required this.adapter, required this.store});

  final SourceAdapter adapter;
  final DownloadStore store;

  @override
  State<SourceHome> createState() => _SourceHomeState();
}

class _SourceHomeState extends State<SourceHome> {
  late List<SourceTab> _tabs;
  List<SourceTab> _knownTabs = [];
  bool _loading = true;

  String get _settingsKey => '${widget.adapter.id}:tab-settings';

  @override
  void initState() {
    super.initState();
    _tabs = widget.adapter.defaultTabs;
    _knownTabs = List.of(_tabs);
    _restoreTabs();
  }

  Future<void> _restoreTabs() async {
    final cached = await widget.store.readCache(_settingsKey);

    try {
      if (cached is Map) {
        final selected = (cached['selected'] as List)
            .map(
              (item) =>
                  SourceTab.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();

        final known = (cached['known'] as List)
            .map(
              (item) =>
                  SourceTab.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();

        if (selected.isNotEmpty) {
          _tabs = selected;
          _knownTabs = known;
        }
      }
    } catch (_) {
      // 設定が不正ならアダプターの初期タブを使用する。
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addTab() async {
    setState(() => _loading = true);

    try {
      _knownTabs = await widget.adapter.discoverTabs();
    } catch (_) {
      // オフラインなら以前取得した候補を使う。
    }

    if (!mounted) return;
    setState(() => _loading = false);

    final candidates = _knownTabs
        .where((item) => !_tabs.any((tab) => tab.id == item.id))
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('追加候補がありません。必要に応じてネット接続を確認してください。')),
      );
      return;
    }

    final chosen = await showDialog<SourceTab>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('タブを追加'),
        children: [
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, candidate);
              },
              child: Text(candidate.title),
            ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    setState(() => _tabs = [..._tabs, chosen]);

    try {
      await widget.store.writeCache(_settingsKey, {
        'selected': _tabs.map((item) => item.toJson()).toList(),
        'known': _knownTabs.map((item) => item.toJson()).toList(),
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タブ設定を保存できませんでした')));
    }
  }

  @override
  void dispose() {
    widget.adapter.close();
    widget.store.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: ValueKey(_tabs.map((item) => item.id).join('|')),
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.adapter.name),
          actions: [
            IconButton(
              tooltip: 'タブを追加',
              onPressed: _loading ? null : _addTab,
              icon: const Icon(Icons.add),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final tab in _tabs) Tab(text: tab.title)],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  for (final tab in _tabs)
                    WorkListPage(
                      key: ValueKey(tab.id),
                      adapter: widget.adapter,
                      store: widget.store,
                      tab: tab,
                    ),
                ],
              ),
      ),
    );
  }
}

class WorkListPage extends StatefulWidget {
  const WorkListPage({
    super.key,
    required this.adapter,
    required this.store,
    required this.tab,
  });

  final SourceAdapter adapter;
  final DownloadStore store;
  final SourceTab tab;

  @override
  State<WorkListPage> createState() => _WorkListPageState();
}

class _WorkListPageState extends State<WorkListPage>
    with AutomaticKeepAliveClientMixin {
  List<ComicWork> _works = [];
  bool _busy = true;
  String? _error;

  String get _cacheKey =>
      '${widget.adapter.id}:works:${widget.tab.query.toJson()}';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final cached = await widget.store.readCache(_cacheKey);

    try {
      if (cached is List) {
        _works = cached
            .map(
              (item) =>
                  ComicWork.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
    } catch (_) {
      _works = [];
    }

    if (_works.isEmpty) {
      _works = widget.adapter.fallbackWorks(widget.tab.query);
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // 初回、または明示更新時に公式ページから画像などを取得。
    if (cached == null) await _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final works = await widget.adapter.fetchWorks(widget.tab.query);

      await widget.store.writeCache(
        _cacheKey,
        works.map((item) => item.toJson()).toList(),
      );

      if (!mounted) return;
      setState(() => _works = works);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '更新できませんでした：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _placeholder() => const ColoredBox(
    color: Color(0xFF252525),
    child: Center(
      child: Icon(Icons.collections_bookmark_outlined, color: Colors.white38),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('作品一覧を更新'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.white60)),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _works.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final work = _works[index];

              return Material(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChapterListPage(
                          adapter: widget.adapter,
                          store: widget.store,
                          tab: widget.tab,
                          work: work,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 128,
                            height: 96,
                            child: work.thumbnail == null
                                ? _placeholder()
                                : Image.network(
                                    work.thumbnail!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, error, stackTrace) =>
                                        _placeholder(),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            work.title,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ChapterListPage extends StatefulWidget {
  const ChapterListPage({
    super.key,
    required this.adapter,
    required this.store,
    required this.tab,
    required this.work,
  });

  final SourceAdapter adapter;
  final DownloadStore store;
  final SourceTab tab;
  final ComicWork work;

  @override
  State<ChapterListPage> createState() => _ChapterListPageState();
}

class _ChapterListPageState extends State<ChapterListPage> {
  List<ComicChapter> _chapters = [];
  Set<String> _saved = {};

  bool _busy = true;
  bool _batch = false;
  bool _stop = false;
  String _status = '';

  bool get _locked => _busy || _batch;

  String get _cacheKey =>
      '${widget.adapter.id}:chapters:${widget.tab.query.toJson()}:${widget.work.id}';

  bool _matches(ComicChapter chapter) =>
      chapter.sourceId == widget.adapter.id &&
      chapter.language == widget.tab.query.language &&
      chapter.workId == widget.work.id;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final entries = <String, ComicChapter>{};
    final cached = await widget.store.readCache(_cacheKey);

    if (cached is List) {
      for (final item in cached) {
        try {
          final chapter = ComicChapter.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          if (_matches(chapter)) entries[chapter.id] = chapter;
        } catch (_) {
          // 不正な項目だけを無視。
        }
      }
    }

    try {
      for (final chapter in await widget.store.localChapters(widget.adapter)) {
        if (_matches(chapter)) {
          entries.putIfAbsent(chapter.id, () => chapter);
        }
      }
    } catch (_) {
      // 読める一覧を優先して表示する。
    }

    if (!mounted) return;
    _chapters = entries.values.toList()..sort((a, b) => a.id.compareTo(b.id));

    await _checkSaved();
    if (!mounted) return;
    setState(() => _busy = false);

    if (cached == null) await _refresh();
  }

  Future<void> _checkSaved() async {
    final saved = <String>{};

    for (final chapter in _chapters) {
      try {
        if ((await widget.store.load(chapter)).isNotEmpty) {
          saved.add(chapter.id);
        }
      } catch (_) {
        // 不完全な話は保存済みにしない。
      }
    }

    if (!mounted) return;
    setState(() {
      _saved = saved;
      _status = '${_chapters.length}件・${saved.length}件保存済み';
    });
  }

  Future<void> _refresh() async {
    if (_locked) return;
    setState(() {
      _busy = true;
      _status = 'チャプター一覧を取得中…';
    });

    try {
      final chapters = await widget.adapter.fetchChapters(
        widget.work,
        widget.tab.query,
      );

      await widget.store.writeCache(
        _cacheKey,
        chapters.map((item) => item.toJson()).toList(),
      );

      if (!mounted) return;
      _chapters = chapters;
      await _checkSaved();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '一覧更新に失敗しました。\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(ComicChapter chapter) async {
    if (_locked) return;

    final index = _chapters.indexWhere((item) => item.id == chapter.id);

    if (index < 0) return;

    setState(() => _busy = true);

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChapterReaderPage(
            adapter: widget.adapter,
            store: widget.store,
            chapters: List<ComicChapter>.unmodifiable(_chapters),
            initialIndex: index,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ComicChapter chapter) async {
    try {
      if ((await widget.store.load(chapter)).isNotEmpty) {
        return;
      }
    } catch (_) {
      // 不完全な場合は再保存。
    }

    final content = await widget.adapter.fetchContent(chapter);

    await widget.store.download(chapter, content, (done, total) {
      if (!mounted) return;
      setState(() {
        _status = '${chapter.title}\n$done / $total ページ保存中';
      });
    });
  }

  Future<void> _download(ComicChapter chapter) async {
    if (_locked) return;
    setState(() => _busy = true);

    try {
      await _save(chapter);
      _message('保存しました');
    } catch (error) {
      _message('保存に失敗しました。\n$error');
    } finally {
      if (mounted) {
        await _checkSaved();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('実行'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _downloadAll() async {
    if (_locked) return;

    final targets = _chapters
        .where((chapter) => !_saved.contains(chapter.id))
        .toList();

    if (targets.isEmpty) {
      _message('表示中のチャプターはすべて保存済みです');
      return;
    }

    final confirmed = await _confirm(
      '一括ダウンロード',
      '${widget.tab.title}の「${widget.work.title}」から、'
          '未保存${targets.length}件を順番に保存します。\n\n'
          '通信量と空き容量にご注意ください。',
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _batch = true;
      _stop = false;
    });

    var completed = 0;
    final failed = <String>[];

    for (final chapter in targets) {
      if (!mounted || _stop) break;

      try {
        await _save(chapter);
        completed++;
      } catch (_) {
        failed.add(chapter.title);
      }

      if (mounted) {
        setState(() {
          _status =
              '今回保存$completed件・失敗${failed.length}件'
              '／対象${targets.length}件';
        });
      }

      if (!_stop) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    if (!mounted) return;
    await _checkSaved();
    if (!mounted) return;

    setState(() {
      _batch = false;
      _status =
          '${_stop ? "停止" : "完了"}：'
          '今回保存$completed件・失敗${failed.length}件';
    });

    if (failed.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('保存できなかったチャプター'),
          content: SingleChildScrollView(child: Text(failed.join('\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _delete(ComicChapter chapter) async {
    if (_locked) return;

    final confirmed = await _confirm(
      '保存データを削除',
      '${chapter.title}の保存画像を削除しますか？\n閲覧位置の記録は残ります。',
    );

    if (!confirmed || !mounted) return;
    setState(() => _busy = true);

    try {
      await widget.store.delete(chapter);
    } catch (error) {
      _message('削除できませんでした。\n$error');
    } finally {
      if (mounted) {
        await _checkSaved();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _credits(ComicChapter chapter) async {
    if (_locked) return;
    setState(() => _busy = true);

    String text;

    try {
      final saved = await widget.store.readCredits(chapter);
      if (saved != null) {
        text = saved;
      } else {
        final content = await widget.adapter.fetchContent(chapter);
        text = content.credits;
        await widget.store.rememberCredits(chapter, text);
      }
    } catch (_) {
      text = 'クレジットを取得できませんでした。\n出典: ${chapter.url}';
    }

    if (!mounted) return;
    setState(() => _busy = false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('作品のクレジット'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_locked,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.work.title}・${widget.tab.title}'),
          actions: [
            IconButton(
              tooltip: 'チャプター一覧を更新',
              onPressed: _locked ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status),
                  const SizedBox(height: 8),
                  if (_batch)
                    OutlinedButton.icon(
                      onPressed: _stop
                          ? null
                          : () => setState(() => _stop = true),
                      icon: const Icon(Icons.stop),
                      label: Text(_stop ? '現在の話の処理後に停止します' : '一括保存を停止'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _locked || _chapters.isEmpty
                          ? null
                          : _downloadAll,
                      icon: const Icon(Icons.download_for_offline),
                      label: const Text('未保存チャプターを一括ダウンロード'),
                    ),
                ],
              ),
            ),
            if (_locked) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final saved = _saved.contains(chapter.id);

                  return ListTile(
                    title: Text(chapter.title),
                    subtitle: Text(
                      saved ? '保存済み・オフライン閲覧可能' : 'オンラインで読む',
                      style: TextStyle(
                        color: saved ? Colors.tealAccent : Colors.white54,
                      ),
                    ),
                    onTap: _locked ? null : () => _open(chapter),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (saved)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(
                              Icons.offline_pin,
                              color: Colors.tealAccent,
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'ダウンロード',
                            onPressed: _locked
                                ? null
                                : () => _download(chapter),
                            icon: const Icon(Icons.download),
                          ),
                        PopupMenuButton<String>(
                          enabled: !_locked,
                          onSelected: (value) {
                            if (value == 'delete') {
                              _delete(chapter);
                            } else {
                              _credits(chapter);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'credits',
                              child: Text('クレジット'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('保存データを削除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
