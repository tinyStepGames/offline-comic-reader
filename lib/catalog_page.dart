part of 'main.dart';

class ComicSeries {
  const ComicSeries(this.id, this.title, this.indexFile, this.section);

  final String id;
  final String title;
  final String indexFile;
  final String section;

  Uri get url =>
      Uri.parse('https://www.peppercarrot.com/en/webcomics/$indexFile.html');
}

const comicSeries = [
  ComicSeries('peppercarrot', 'ペッパー＆キャロット', 'peppercarrot', 'webcomic'),
  ComicSeries(
    'mini',
    'ミニファンタジーシアター',
    'miniFantasyTheater',
    'miniFantasyTheater',
  ),
  ComicSeries('misc', 'その他', 'misc', 'webcomic-misc'),
];

class ComicEpisode {
  const ComicEpisode(this.series, this.title, this.url);

  final ComicSeries series;
  final String title;
  final Uri url;

  String get slug => url.pathSegments.last.replaceFirst(RegExp(r'\.html$'), '');

  String get id {
    if (series.id == 'peppercarrot') {
      final match = RegExp(r'^ep(\d+)_').firstMatch(slug)!;
      final number = int.parse(match.group(1)!);
      return 'peppercarrot-en-ep${number.toString().padLeft(2, '0')}';
    }
    return '${series.id}-en-$slug';
  }

  Map<String, dynamic> toJson() => {'title': title, 'url': url.toString()};

  static ComicEpisode parse(String address, String title) {
    final url = Uri.parse(address);

    if (url.scheme != 'https' ||
        url.host != 'www.peppercarrot.com' ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('未対応のURLです');
    }

    final match = RegExp(
      r'^/en/(webcomic|miniFantasyTheater|webcomic-misc)/'
      r'([A-Za-z0-9_-]+)\.html$',
    ).firstMatch(url.path);

    if (match == null) {
      throw const FormatException('チャプターURLではありません');
    }

    final series = comicSeries.firstWhere(
      (item) => item.section == match.group(1),
    );

    if (series.id == 'peppercarrot' &&
        !RegExp(r'^ep\d+_').hasMatch(match.group(2)!)) {
      throw const FormatException('話数形式が不正です');
    }

    return ComicEpisode(
      series,
      title.trim().isEmpty ? match.group(2)! : title.trim(),
      url,
    );
  }
}

class _ComicPageData {
  const _ComicPageData(this.images, this.credits);

  final List<Uri> images;
  final String credits;
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.root, this.series});

  final Directory root;
  final ComicSeries? series;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final Map<String, String> _seriesThumbnails = {};
  bool _thumbnailLoading = false;

  Widget _thumbnailPlaceholder() {
    return const ColoredBox(
      color: Color(0xFF252525),
      child: Center(
        child: Icon(
          Icons.collections_bookmark_outlined,
          size: 36,
          color: Colors.white38,
        ),
      ),
    );
  }

  bool _validThumbnail(String address) {
    final url = Uri.tryParse(address);

    return url != null &&
        url.scheme == 'https' &&
        url.host == 'www.peppercarrot.com';
  }

  Future<void> _loadSeriesThumbnails() async {
    if (_thumbnailLoading) return;

    setState(() => _thumbnailLoading = true);

    final cache = File(p.join(widget.root.path, 'series-thumbnails.json'));

    try {
      // 保存済みURLを先に表示する。
      try {
        if (await cache.exists()) {
          final data =
              jsonDecode(await cache.readAsString()) as Map<String, dynamic>;

          final cached = <String, String>{};

          for (final series in comicSeries) {
            final address = data[series.id];

            if (address is String && _validThumbnail(address)) {
              cached[series.id] = address;
            }
          }

          if (!mounted) return;

          setState(() {
            _seriesThumbnails.addAll(cached);
          });
        }
      } catch (_) {
        // キャッシュが不正でも公式サイトから取得を試す。
      }

      final indexUrl = Uri.parse(
        'https://www.peppercarrot.com/ja/webcomics/'
        'peppercarrot.html',
      );

      final response = await _dio.get<String>(
        indexUrl.toString(),
        options: Options(responseType: ResponseType.plain),
      );

      final document = html.parse(response.data ?? '');

      const idMap = {
        'peppercarrot': 'peppercarrot',
        'miniFantasyTheater': 'mini',
        'misc': 'misc',
      };

      final result = <String, String>{};

      // background: url('...') のURL部分を取得。
      final cssUrl = RegExp(
        r'''url\(\s*(['"]?)(.*?)\1\s*\)''',
        caseSensitive: false,
      );

      for (final link in document.querySelectorAll('a.sidebar-img-btn[id]')) {
        final seriesId = idMap[link.id];
        if (seriesId == null) continue;

        final style = link.attributes['style'] ?? '';
        final match = cssUrl.firstMatch(style);
        final address = match?.group(2)?.trim();

        if (address == null || address.isEmpty) continue;

        final resolved = indexUrl.resolve(address).toString();

        if (_validThumbnail(resolved)) {
          result[seriesId] = resolved;
        }
      }

      if (result.isEmpty) {
        throw StateError('作品画像のURLが見つかりません');
      }

      if (!mounted) return;

      setState(() {
        _seriesThumbnails.addAll(result);
      });

      await widget.root.create(recursive: true);
      await cache.writeAsString(jsonEncode(_seriesThumbnails), flush: true);
    } catch (_) {
      // オフライン時などは既存URLまたは代替アイコンを使用。
    } finally {
      if (mounted) {
        setState(() => _thumbnailLoading = false);
      }
    }
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  List<ComicEpisode> _episodes = [];
  final Set<String> _saved = {};

  bool _busy = false;
  bool _batch = false;
  bool _stop = false;
  String? _workingId;
  String _status = '';

  bool get _locked => _busy || _batch || _workingId != null;

  ComicSeries get _series => widget.series!;

  File get _cache => File(
    p.join(
      widget.root.path,
      _series.id == 'peppercarrot'
          ? 'catalog.json'
          : 'catalog-${_series.id}.json',
    ),
  );

  EpisodeStore _store(ComicEpisode episode) => EpisodeStore(
    Directory(p.join(widget.root.path, episode.id)),
    id: episode.id,
    url: episode.url,
    title: episode.title,
  );

  File _creditsFile(ComicEpisode episode) =>
      File(p.join(widget.root.path, episode.id, 'credits.txt'));

  @override
  void initState() {
    super.initState();
    if (widget.series != null) {
      _initialize();
    } else {
      _loadSeriesThumbnails();
    }
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _busy = true);
    await _loadLocal();

    if (!mounted) return;
    setState(() => _busy = false);

    // 一覧がまだない作品だけ初回取得する。
    if (_episodes.isEmpty) {
      await _refresh();
    }
  }

  Future<void> _loadLocal() async {
    final entries = <String, ComicEpisode>{};

    void add(dynamic item) {
      try {
        final map = item as Map<String, dynamic>;
        final episode = ComicEpisode.parse(
          (map['url'] ?? map['sourceUrl']) as String,
          map['title'] as String,
        );
        if (episode.series.id == _series.id) {
          entries[episode.id] = episode;
        }
      } catch (_) {
        // 不正な項目だけを無視する。
      }
    }

    for (final episode in _episodes) {
      entries[episode.id] = episode;
    }

    try {
      if (await _cache.exists()) {
        final data = jsonDecode(await _cache.readAsString()) as List<dynamic>;
        for (final item in data) {
          add(item);
        }
      }
    } catch (_) {
      // 保存フォルダからの復元も試す。
    }

    try {
      await widget.root.create(recursive: true);

      await for (final entity in widget.root.list(followLinks: false)) {
        if (entity is! Directory) continue;

        try {
          final manifest = File(p.join(entity.path, 'manifest.json'));
          if (!await manifest.exists()) continue;

          final data =
              jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;

          final episode = ComicEpisode.parse(
            data['sourceUrl'] as String,
            data['title'] as String,
          );

          if (p.basename(entity.path) == episode.id) {
            add(data);
          }
        } catch (_) {
          // 未完了・破損データは復元に使わない。
        }
      }
    } catch (_) {
      // 画面自体は表示する。
    }

    final saved = <String>{};

    for (final episode in entries.values) {
      try {
        if ((await _store(episode).load()).isNotEmpty) {
          saved.add(episode.id);
        }
      } catch (_) {
        // 未完了の話は保存済みにしない。
      }
    }

    final episodes = entries.values.toList()
      ..sort((a, b) => a.slug.compareTo(b.slug));

    if (!mounted) return;

    setState(() {
      _episodes = episodes;
      _saved
        ..clear()
        ..addAll(saved);
      _status = '${episodes.length}件・${saved.length}件保存済み';
    });
  }

  Future<void> _refresh() async {
    if (_locked) return;

    setState(() {
      _busy = true;
      _status = 'チャプター一覧を取得中…';
    });

    try {
      final response = await _dio.get<String>(
        _series.url.toString(),
        options: Options(responseType: ResponseType.plain),
      );

      final document = html.parse(response.data ?? '');
      final entries = <String, ComicEpisode>{};

      for (final link in document.querySelectorAll(
        'figure.thumbnail figcaption a[href]',
      )) {
        try {
          final episode = ComicEpisode.parse(
            _series.url.resolve(link.attributes['href']!).toString(),
            link.text,
          );

          if (episode.series.id == _series.id) {
            entries[episode.id] = episode;
          }
        } catch (_) {
          // 別カテゴリや特殊リンクは無視する。
        }
      }

      if (entries.isEmpty) {
        throw StateError('チャプターが見つかりません');
      }

      await widget.root.create(recursive: true);
      await _cache.writeAsString(
        jsonEncode(entries.values.map((item) => item.toJson()).toList()),
        flush: true,
      );

      if (!mounted) return;
      _episodes = entries.values.toList();
      await _loadLocal();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = '一覧を更新できませんでした。\n$error';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<_ComicPageData> _fetchPage(ComicEpisode episode) async {
    final response = await _dio.get<String>(
      episode.url.toString(),
      options: Options(responseType: ResponseType.plain),
    );

    final document = html.parse(response.data ?? '');
    final images = <Uri>[];
    final seen = <String>{};

    for (final image in document.querySelectorAll(
      '.webcomic-page img, #panel-all img.mft-cv-image',
    )) {
      final src = image.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final url = episode.url.resolve(src);

      if (url.scheme != 'https' ||
          url.host != 'www.peppercarrot.com' ||
          !RegExp(
            r'\.(?:jpe?g|png|webp|gif)$',
            caseSensitive: false,
          ).hasMatch(url.path)) {
        throw const FormatException('未対応の画像URLです');
      }

      if (seen.add(url.toString())) {
        images.add(url);
      }
    }

    if (images.isEmpty) {
      throw StateError('本文画像が見つかりません');
    }

    // 作品ごとのクレジット・ライセンス表示とリンクを保持する。
    final sections = document.querySelectorAll(
      '.webcomic-footer-box, .mft-cv-credits',
    );

    final notes = <String>[
      episode.title,
      '出典: ${episode.url}',
      '本アプリは非公式リーダーです。画像データは変更していません。',
    ];

    for (final section in sections) {
      notes.add(section.text.trim());
      for (final link in section.querySelectorAll('a[href]')) {
        final href = link.attributes['href'];
        if (href != null && href.isNotEmpty) {
          notes.add(episode.url.resolve(href).toString());
        }
      }
    }

    final credits = notes.toSet().join('\n\n');
    final store = _store(episode);
    await store.directory.create(recursive: true);
    await _creditsFile(episode).writeAsString(credits, flush: true);

    return _ComicPageData(images, credits);
  }

  Future<void> _open(ComicEpisode episode) async {
    if (_locked) return;

    setState(() {
      _workingId = episode.id;
      _status = '開いています…';
    });

    try {
      List<File> files = [];
      try {
        files = await _store(episode).load();
      } catch (_) {
        // 不完全ならオンライン閲覧を試す。
      }

      final urls = files.isEmpty ? (await _fetchPage(episode)).images : <Uri>[];

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            progressKey: ReadingKey(
              sourceId: episode.url.host,
              chapterId: episode.url.path,
            ),
            files: files,
            imageUrls: urls,
            title: episode.title,
          ),
        ),
      );
    } catch (error) {
      _message('開けませんでした。未保存の話にはネット接続が必要です。\n$error');
    } finally {
      if (mounted) {
        await _loadLocal();
        if (mounted) {
          setState(() => _workingId = null);
        }
      }
    }
  }

  Future<void> _save(ComicEpisode episode) async {
    final store = _store(episode);

    try {
      if ((await store.load()).isNotEmpty) {
        if (mounted) {
          setState(() => _saved.add(episode.id));
        }
        return;
      }
    } catch (_) {
      // 破損・未完了なら再取得。
    }

    // クレジットを先に保存する。
    await _fetchPage(episode);
    await store.directory.create(recursive: true);

    await store.download((done, total) {
      if (!mounted) return;
      setState(() {
        _status = '${episode.title}\n$done / $total ページ保存中';
      });
    });

    if (mounted) {
      setState(() => _saved.add(episode.id));
    }
  }

  Future<void> _download(ComicEpisode episode) async {
    if (_locked) return;

    setState(() {
      _workingId = episode.id;
      _status = '保存を開始します…';
    });

    try {
      await _save(episode);
      _message('保存しました');
    } catch (error) {
      _message('保存に失敗しました。\n$error');
    } finally {
      if (mounted) {
        await _loadLocal();
        if (mounted) {
          setState(() => _workingId = null);
        }
      }
    }
  }

  Future<void> _downloadAll() async {
    if (_locked) return;

    final targets = _episodes
        .where((episode) => !_saved.contains(episode.id))
        .toList();

    if (targets.isEmpty) {
      _message('表示中のチャプターはすべて保存済みです');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('一括ダウンロード'),
        content: Text(
          '${_series.title}の未保存${targets.length}件を順番に保存します。\n\n'
          '通信量と保存容量にご注意ください。\n'
          '停止操作は現在の話の処理後に反映されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('開始'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _batch = true;
      _stop = false;
    });

    var completed = 0;
    final failed = <String>[];

    for (final episode in targets) {
      if (!mounted || _stop) break;

      setState(() {
        _workingId = episode.id;
        _status =
            '${completed + failed.length + 1} / '
            '${targets.length}件目を処理中';
      });

      try {
        await _save(episode);
        completed++;
      } catch (_) {
        failed.add(episode.title);
      }

      if (mounted && !_stop) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    if (!mounted) return;

    await _loadLocal();
    if (!mounted) return;

    final stopped = _stop;

    setState(() {
      _batch = false;
      _workingId = null;
      _status =
          '${stopped ? "停止しました" : "処理が完了しました"}'
          '：今回保存$completed件・失敗${failed.length}件';
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

  Future<void> _delete(ComicEpisode episode) async {
    if (_locked) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存データを削除'),
        content: Text('${episode.title}の保存データを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _workingId = episode.id);

    try {
      final directory = _store(episode).directory;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      _message('削除しました');
    } catch (error) {
      _message('削除を完了できませんでした。\n$error');
    } finally {
      if (mounted) {
        await _loadLocal();
        if (mounted) {
          setState(() => _workingId = null);
        }
      }
    }
  }

  Future<void> _showCredits(ComicEpisode episode) async {
    if (_locked) return;
    setState(() => _workingId = episode.id);

    String text;

    try {
      final file = _creditsFile(episode);
      text = await file.exists()
          ? await file.readAsString()
          : (await _fetchPage(episode)).credits;
    } catch (_) {
      text =
          'この話のクレジットを取得できませんでした。\n'
          'ネット接続後に再度お試しください。\n\n'
          '出典: ${episode.url}';
    }

    if (!mounted) return;

    setState(() => _workingId = null);

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
    if (widget.series == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('作品一覧'),
          actions: [
            IconButton(
              tooltip: '作品画像を更新',
              onPressed: _thumbnailLoading ? null : _loadSeriesThumbnails,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_thumbnailLoading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: comicSeries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final series = comicSeries[index];
                  final thumbnail = _seriesThumbnails[series.id];

                  return Material(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                CatalogPage(root: widget.root, series: series),
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
                                child: thumbnail == null
                                    ? _thumbnailPlaceholder()
                                    : Image.network(
                                        thumbnail,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return _thumbnailPlaceholder();
                                            },
                                        loadingBuilder:
                                            (context, child, progress) {
                                              if (progress == null) {
                                                return child;
                                              }

                                              return const ColoredBox(
                                                color: Color(0xFF252525),
                                                child: Center(
                                                  child: SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                      ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    series.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'チャプター一覧を開く',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: !_locked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_series.title),
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
                  Text(_status, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  if (_batch)
                    OutlinedButton.icon(
                      onPressed: _stop
                          ? null
                          : () {
                              setState(() => _stop = true);
                            },
                      icon: const Icon(Icons.stop),
                      label: Text(_stop ? '現在の話の処理後に停止します' : '一括保存を停止'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _locked || _episodes.isEmpty
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
              child: _episodes.isEmpty && !_busy
                  ? const Center(
                      child: Text(
                        '一覧がありません。\n右上の更新ボタンで取得してください。',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final episode = _episodes[index];
                        final saved = _saved.contains(episode.id);

                        return ListTile(
                          leading: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          title: Text(episode.title),
                          subtitle: Text(
                            saved ? '保存済み・オフライン閲覧可能' : 'オンラインで読む',
                            style: TextStyle(
                              color: saved ? Colors.tealAccent : Colors.white54,
                            ),
                          ),
                          onTap: _locked ? null : () => _open(episode),
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
                                      : () => _download(episode),
                                  icon: const Icon(Icons.download),
                                ),
                              PopupMenuButton<String>(
                                enabled: !_locked,
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _delete(episode);
                                  } else {
                                    _showCredits(episode);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'credits',
                                    child: Text('クレジット'),
                                  ),
                                  const PopupMenuItem(
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
