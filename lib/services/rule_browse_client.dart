import 'package:dio/dio.dart';

import 'html_probe.dart';
import 'list_extraction_rule.dart';
import 'site_rule_store.dart';

typedef RulePageFetcher =
    Future<HtmlProbePage> Function(
      String input, {
      required CancelToken cancelToken,
      required String allowedOrigin,
    });

class RuleBrowseItem {
  const RuleBrowseItem({
    required this.title,
    required this.url,
    required this.thumbnail,
    required this.date,
    required this.latestChapter,
    required this.issues,
  });

  final String title;
  final Uri? url;
  final Uri? thumbnail;
  final String date;
  final String latestChapter;
  final List<String> issues;
}

class RuleBrowseResult {
  const RuleBrowseResult({
    required this.pageUri,
    required this.total,
    required this.items,
  });

  final Uri pageUri;
  final int total;
  final List<RuleBrowseItem> items;
}

class RuleBrowseClient {
  RuleBrowseClient({RulePageFetcher? fetcher}) : _fetcher = fetcher;

  final HtmlProbeClient _client = HtmlProbeClient();
  final RulePageFetcher? _fetcher;

  static const maxRows = 5000;

  void _checkCancelled(CancelToken token) {
    if (token.isCancelled) throw StateError('取得を中止しました');
  }

  Future<RuleBrowseResult> load({
    required SavedSiteRule site,
    required String kind,
    required CancelToken cancelToken,
    String? targetUrl,
  }) async {
    _checkCancelled(cancelToken);

    if (!const ['works', 'chapters'].contains(kind)) {
      throw const FormatException('未対応の一覧の種類です');
    }

    final template = site.rules[kind];
    if (template == null) {
      throw StateError(
        '${kind == 'works' ? '作品一覧' : 'チャプター一覧'}が未設定です。'
        'サイトルール管理で設定してください',
      );
    }

    template.validate();
    if (template.kind != kind) {
      throw const FormatException('保存先と一覧ルールの種類が一致しません');
    }
    if (template.acquisition != 'staticHtml') {
      throw const FormatException(
        'この設定は「ページを表示して取得」の方式です。'
        '今回の自動取得は通常HTMLのみ対応しています。'
        '通常HTMLで取得できる場合は、編集画面で通常HTML取得後に保存し直してください',
      );
    }

    if (kind == 'chapters' && (targetUrl == null || targetUrl.trim().isEmpty)) {
      throw const FormatException('作品のURLが必要です。サンプルURLを代わりに使用することはできません');
    }

    final sample = htmlProbeUri(template.pageUrl);
    final target = htmlProbeUri(targetUrl ?? template.pageUrl);

    if (target.origin != sample.origin) {
      throw const FormatException(
        '選択したURLと、この一覧設定の取得元が異なります。'
        'サブドメイン・www・ポート番号も含めて設定を確認してください',
      );
    }

    final page = _fetcher == null
        ? await _client.fetch(
            target.toString(),
            cancelToken: cancelToken,
            allowedOrigin: target.origin,
          )
        : await _fetcher(
            target.toString(),
            cancelToken: cancelToken,
            allowedOrigin: target.origin,
          );

    _checkCancelled(cancelToken);

    final finalUri = htmlProbeUri(page.uri.toString());
    if (finalUri.origin != target.origin) {
      throw const FormatException('取得結果が別の取得元になっています');
    }

    // 保存されたサンプルURLではなく、今回取得したページへルールを適用。
    // 末尾スラッシュなど、同じ取得元内の転送後URLもここで反映する。
    final effectiveRule = ListExtractionRule(
      pageUrl: finalUri.toString(),
      groupSelector: template.groupSelector,
      fields: Map.of(template.fields),
      kind: template.kind,
      acquisition: template.acquisition,
    );

    final report = await extractListRowsSafely(
      page,
      effectiveRule,
      maxRows: maxRows,
    );
    _checkCancelled(cancelToken);

    if (report.total > maxRows) {
      throw const FormatException('一覧が5000件を超えました。取得範囲やページ分割の設定が必要です');
    }

    final nextTemplate = kind == 'works' ? site.rules['chapters'] : null;
    final linkOrigin = nextTemplate == null
        ? finalUri.origin
        : htmlProbeUri(nextTemplate.pageUrl).origin;

    final items = <RuleBrowseItem>[];

    for (final row in report.rows) {
      final issues = List<String>.of(row.issues);
      final title = row.values['title']?.trim() ?? '';
      Uri? url;

      try {
        final candidate = htmlProbeUri(row.values['url'] ?? '');
        if (candidate.origin != linkOrigin) {
          throw const FormatException('次の取得設定とは異なる取得元のリンクです');
        }
        url = candidate;
      } catch (error) {
        issues.add('リンクを開けません：$error');
      }

      if (title.isEmpty) {
        issues.add('タイトルが空です');
        url = null;
      }

      Uri? thumbnail;
      final rawThumbnail = row.values['thumbnail'] ?? '';
      if (rawThumbnail.isNotEmpty) {
        try {
          thumbnail = htmlProbeUri(rawThumbnail);
        } catch (_) {
          issues.add('表紙は認証情報を含まないHTTPSのURLにしてください');
        }
      }

      items.add(
        RuleBrowseItem(
          title: title.isEmpty ? 'タイトル未取得' : title,
          url: url,
          thumbnail: thumbnail,
          date: row.values['date'] ?? '',
          latestChapter: row.values['latestChapter'] ?? '',
          issues: List.unmodifiable(issues),
        ),
      );
    }

    return RuleBrowseResult(
      pageUri: finalUri,
      total: report.total,
      items: List.unmodifiable(items),
    );
  }

  void close() => _client.close();
}
