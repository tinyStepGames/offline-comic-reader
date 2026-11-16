import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'reader_page.dart';
import 'reading_progress.dart';
import 'rendered_rule_page.dart';
import 'services/html_probe.dart';
import 'services/rule_browse_client.dart';
import 'services/rule_content_client.dart';
import 'services/site_rule_store.dart';

class RuleOnlineReaderPage extends StatefulWidget {
  const RuleOnlineReaderPage({
    super.key,
    required this.site,
    required this.chapters,
    required this.initialIndex,
    this.workThumbnail,
  }) : assert(chapters.length > 0),
       assert(initialIndex >= 0 && initialIndex < chapters.length);

  final SavedSiteRule site;

  /// 開いた時点の一覧表示順を維持する。
  final List<RuleBrowseItem> chapters;
  final int initialIndex;
  final Uri? workThumbnail;

  @override
  State<RuleOnlineReaderPage> createState() => _RuleOnlineReaderPageState();
}

class _RuleOnlineReaderPageState extends State<RuleOnlineReaderPage> {
  final _client = RuleContentClient();

  CancelToken? _cancel;
  late int _index;
  List<Uri> _images = [];
  bool _loading = false;
  bool _opened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;

    // 画面を開く遷移中に別のWebView画面をpushしない。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      _load(_index);
    });
  }

  Future<HtmlProbePage> _fetchRendered(
    String input, {
    required CancelToken cancelToken,
    required String allowedOrigin,
    required String groupSelector,
  }) async {
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted ||
        cancelToken.isCancelled ||
        ModalRoute.of(context)?.isCurrent != true) {
      throw StateError('本文画像の取得を中止しました');
    }

    final page = await Navigator.of(context).push<HtmlProbePage>(
      MaterialPageRoute<HtmlProbePage>(
        builder: (_) => RenderedRulePage(
          url: input,
          allowedOrigin: allowedOrigin,
          groupSelector: groupSelector,
          cancelToken: cancelToken,
          backgroundMode: true,
          previewTitle: '本文画像を取得中',
          previewThumbnail: widget.workThumbnail,
        ),
      ),
    );

    if (page == null || cancelToken.isCancelled) {
      throw StateError('本文画像の取得を中止しました');
    }

    return page;
  }

  Future<void> _load(int target) async {
    if (_loading ||
        target < 0 ||
        target >= widget.chapters.length ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final chapter = widget.chapters[target];
    final url = chapter.url;

    if (url == null) return;

    final token = CancelToken();
    _cancel = token;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final images = await _client.load(
        site: widget.site,
        chapterUrl: url.toString(),
        cancelToken: token,
        renderedFetcher: _fetchRendered,
      );

      if (!mounted || token.isCancelled) return;

      setState(() {
        _index = target;
        _images = images;
        _opened = true;
      });
    } catch (error) {
      if (!mounted || token.isCancelled) return;

      final message = '「${chapter.title}」を開けませんでした。\n$error';

      if (_opened) {
        // 前後の話の取得失敗で、現在読めている本文は消さない。
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              action: SnackBarAction(
                label: '再試行',
                onPressed: () => _load(target),
              ),
            ),
          );
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (identical(_cancel, token)) _cancel = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cancel?.cancel('読書画面終了');
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapters[_index];

    if (!_opened) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(chapter.title)),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ?? '本文画像を取得する準備ができました。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _load(_index),
                        icon: const Icon(Icons.refresh),
                        label: const Text('再試行'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    final chapterUrl = chapter.url!.removeFragment().toString();

    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: _loading,
          child: ReaderPage(
            key: ValueKey('${widget.site.id}:$chapterUrl'),
            files: const <File>[],
            imageUrls: _images,
            title: chapter.title,
            progressKey: ReadingKey(
              // 既存の組み込みサイトの識別子とは分離する。
              sourceId: 'custom-site:${widget.site.id}',
              chapterId: chapterUrl,
            ),
            onPreviousChapter: _index > 0 ? () => _load(_index - 1) : null,
            onNextChapter: _index + 1 < widget.chapters.length
                ? () => _load(_index + 1)
                : null,
          ),
        ),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
