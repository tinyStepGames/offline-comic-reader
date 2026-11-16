import 'package:dio/dio.dart';

import 'chapter_image_probe.dart';
import 'html_probe.dart';
import 'rule_browse_client.dart';
import 'site_rule_store.dart';

class RuleContentClient {
  RuleContentClient({RulePageFetcher? fetcher}) : _fetcher = fetcher;

  final HtmlProbeClient _client = HtmlProbeClient();
  final RulePageFetcher? _fetcher;

  void _checkCancel(CancelToken token) {
    if (token.isCancelled) {
      throw StateError('本文画像の取得を中止しました');
    }
  }

  Future<List<Uri>> load({
    required SavedSiteRule site,
    required String chapterUrl,
    required CancelToken cancelToken,
    RenderedRulePageFetcher? renderedFetcher,
  }) async {
    _checkCancel(cancelToken);

    final settings = site.images;
    if (settings == null) {
      throw const FormatException('本文画像ルールが未設定です。サイトルール管理から設定してください');
    }

    settings.validateOrigins(site.rules.values.map((rule) => rule.pageUrl));

    final origin = htmlProbeUri(settings.pageUrl).origin;

    // サンプルURLではなく、選択されたチャプターのURLを使用する。
    final target = htmlProbeUri(chapterUrl);
    if (target.origin != origin) {
      throw const FormatException('チャプターURLの取得元がサイト設定と異なります');
    }

    final HtmlProbePage page;

    if (settings.acquisition == 'renderedDom') {
      if (renderedFetcher == null) {
        throw const FormatException('表示後HTMLの取得画面が接続されていません');
      }

      page = await renderedFetcher(
        target.toString(),
        cancelToken: cancelToken,
        allowedOrigin: origin,
        groupSelector: settings.rule.selector,
      );
    } else {
      final fetcher = _fetcher;
      page = fetcher == null
          ? await _client.fetch(
              target.toString(),
              cancelToken: cancelToken,
              allowedOrigin: origin,
            )
          : await fetcher(
              target.toString(),
              cancelToken: cancelToken,
              allowedOrigin: origin,
            );
    }

    _checkCancel(cancelToken);

    if (htmlProbeUri(page.uri.toString()).origin != origin) {
      throw const FormatException('転送後の本文ページが別の取得元です');
    }

    final report = await probeChapterImages(page: page, rule: settings.rule);

    _checkCancel(cancelToken);

    // 一部だけ取得できた状態で、正常な本文としてリーダーを開かない。
    if (!report.isUsable) {
      final details = report.issues.take(3).join('\n');
      throw FormatException(
        '本文画像を正常に抽出できませんでした。'
        '問題 ${report.issues.length}件\n$details',
      );
    }

    return List<Uri>.unmodifiable(report.images);
  }

  void close() => _client.close();
}
