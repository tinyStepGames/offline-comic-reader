import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_diagnostics.dart';

HtmlProbePage makePage(String source) => HtmlProbePage(
  uri: Uri.parse('https://example.com/list/'),
  source: source,
  bytes: source.length,
);

ListExtractionRule makeRule({
  String group = '.slot',
  String titleSelector = '.title',
  String titlePattern = '',
  String titleReplacement = '',
}) {
  final fields = defaultListFields();

  fields['title'] = ListFieldRule(
    selector: titleSelector,
    pattern: titlePattern,
    replacement: titleReplacement,
  );

  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );

  return ListExtractionRule(
    pageUrl: 'https://example.com/list/',
    groupSelector: group,
    fields: fields,
  );
}

DioException dioError(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: 'https://example.com/list/'),
  type: type,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final type in DioExceptionType.values) {
    test('every Dio exception type produces a message: ${type.name}', () {
      final message = ruleFailureMessage(
        dioError(type),
        stage: RuleDiagnosticStage.fetch,
      );
      expect(message, isNotEmpty);
    });
  }

  test('transform timeout is not classified as a network timeout', () {
    final message = ruleFailureMessage(
      dioError(DioExceptionType.transformTimeout),
      stage: RuleDiagnosticStage.fetch,
    );

    expect(message, contains('応答データの変換処理'));
    expect(message, contains('接続や受信のタイムアウトとは別'));
    expect(message, contains('自動再試行は行いません'));
    expect(message, isNot(contains('通信がタイムアウトしました')));
  });

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('network timeout is distinguished: ${type.name}', () {
      final message = ruleFailureMessage(
        dioError(type),
        stage: RuleDiagnosticStage.fetch,
      );

      expect(message, contains('通信がタイムアウト'));
      expect(message, contains('自動再試行は行いません'));
    });
  }

  test('HTTP errors remain StateErrors and retain their code', () {
    final error = HtmlProbeHttpException(403);

    expect(error, isA<StateError>());
    expect(error.statusCode, 403);

    final message = ruleFailureMessage(error, stage: RuleDiagnosticStage.fetch);

    expect(message, contains('HTTP 403'));
    expect(message, contains('拒否'));
  });

  test('HTTP 404, 429 and 503 have different guidance', () {
    String message(int code) => ruleFailureMessage(
      HtmlProbeHttpException(code),
      stage: RuleDiagnosticStage.fetch,
    );

    expect(message(404), contains('見つかりません'));
    expect(message(429), contains('時間を置いて'));
    expect(message(429), contains('手動'));
    expect(message(503), contains('サイト側でエラー'));
  });

  test('connection, certificate and cancellation are distinguished', () {
    expect(
      ruleFailureMessage(
        dioError(DioExceptionType.connectionError),
        stage: RuleDiagnosticStage.fetch,
      ),
      contains('接続できません'),
    );

    expect(
      ruleFailureMessage(
        dioError(DioExceptionType.badCertificate),
        stage: RuleDiagnosticStage.fetch,
      ),
      contains('証明書の検証は無効にしません'),
    );

    expect(
      ruleFailureMessage(
        dioError(DioExceptionType.cancel),
        stage: RuleDiagnosticStage.fetch,
      ),
      '取得を中止しました。',
    );
  });

  test('bad HTTP response uses its response status', () {
    final request = RequestOptions(path: 'https://example.com/list/');
    final error = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(requestOptions: request, statusCode: 429),
    );

    expect(
      ruleFailureMessage(error, stage: RuleDiagnosticStage.fetch),
      contains('HTTP 429'),
    );
  });

  test('unknown failures do not assert a network cause', () {
    final message = ruleFailureMessage(
      StateError('unexpected failure'),
      stage: RuleDiagnosticStage.browsing,
    );

    expect(message, contains('原因を特定できない'));
    expect(message, contains('unexpected failure'));
    expect(message, isNot(contains('通信がタイムアウト')));
  });

  test('generic timeout does not assert a network cause', () {
    final message = ruleFailureMessage(
      TimeoutException('operation timeout'),
      stage: RuleDiagnosticStage.browsing,
    );

    expect(message, contains('処理が時間内に完了しません'));
    expect(message, isNot(contains('通信がタイムアウト')));
  });

  test('format errors remain format-related diagnostics', () {
    final message = ruleFailureMessage(
      const FormatException('URLの形式を確認してください'),
      stage: RuleDiagnosticStage.fetch,
    );

    expect(message, contains('URL・設定・取得データの形式'));
    expect(message, contains('URLの形式を確認してください'));
  });

  test('zero matches do not prove that works do not exist', () {
    final advice = emptyListAdvice(total: 0, acquisition: 'staticHtml');

    expect(advice, contains('0件'));
    expect(advice, contains('断定できません'));
    expect(advice, contains('取得方式は自動変更していません'));
  });

  test('all-empty groups are distinguished from zero matches', () {
    final advice = emptyListAdvice(total: 2, acquisition: 'renderedDom');

    expect(advice, contains('2件のまとまりに一致'));
    expect(advice, contains('表示対象の項目がありません'));
    expect(advice, isNot(contains('0件でした')));
    expect(advice, isNot(contains('通常HTMLで一致しない理由')));
  });

  test('normal browse status retains existing header behavior', () {
    expect(
      browseListStatus(
        total: 26,
        itemCount: 24,
        openableCount: 24,
        acquisition: 'renderedDom',
      ),
      '24件を取得しました',
    );
  });

  test('all unopenable items are not labelled as normal success', () {
    final message = browseListStatus(
      total: 3,
      itemCount: 3,
      openableCount: 0,
      acquisition: 'staticHtml',
    );

    expect(message, contains('開ける項目がありません'));
    expect(message, isNot(contains('件を取得しました')));
  });

  test('regex mismatch guidance preserves original field diagnosis', () {
    const issue = '表紙：FormatException: 正規表現に一致しません';
    final message = ruleIssueMessage(issue);

    expect(message, startsWith(issue));
    expect(message, contains('加工前の値'));
  });

  test('empty-field issue strings remain unchanged for slot filtering', () {
    expect(ruleIssueMessage('タイトル：取得できません'), 'タイトル：取得できません');
    expect(ruleIssueMessage('リンク：取得できません'), 'リンク：取得できません');
  });

  test('invalid group selector remains a FormatException', () {
    expect(
      () => extractListRows(
        makePage('<div class="slot"></div>'),
        makeRule(group: '['),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('まとまりのセレクターが不正です'),
        ),
      ),
    );
  });

  test('invalid item selector produces a field-specific issue', () {
    final report = extractListRows(
      makePage('<div class="slot"><a href="/work/1/">Work</a></div>'),
      makeRule(titleSelector: '['),
    );

    expect(report.rows, hasLength(1));
    expect(
      report.rows.single.issues.any(
        (issue) => issue.contains('タイトル') && issue.contains('項目のセレクターが不正です'),
      ),
      isTrue,
    );
  });

  test('invalid regex validation identifies the field', () {
    expect(
      () => makeRule(titlePattern: '[').validate(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('タイトル'), contains('正規表現・整形テンプレート')),
        ),
      ),
    );
  });

  test('regex mismatch remains a field issue', () {
    final report = extractListRows(
      makePage(
        '<div class="slot">'
        '<a href="/work/1/"><span class="title">Work</span></a>'
        '</div>',
      ),
      makeRule(titlePattern: r'^REQUIRED:(.*)$', titleReplacement: r'$1'),
    );

    expect(report.rows.single.values['title'], isEmpty);
    expect(
      report.rows.single.issues.any(
        (issue) => issue.contains('タイトル') && issue.contains('正規表現に一致しません'),
      ),
      isTrue,
    );
  });

  test('editor advice distinguishes zero matches from empty rows', () {
    final zero = listReportAdvice(
      const ListExtractionReport(0, []),
      acquisition: 'staticHtml',
    );

    final empty = listReportAdvice(
      const ListExtractionReport(2, [
        ExtractedListRow({'title': '', 'url': ''}, []),
        ExtractedListRow({'title': '', 'url': ''}, []),
      ]),
      acquisition: 'staticHtml',
    );

    expect(zero, contains('0件'));
    expect(empty, contains('表示中の全項目でタイトルとリンクが空'));
  });

  test('normal report has no additional warning', () {
    final report = ListExtractionReport(1, [
      ExtractedListRow({
        'title': 'Work',
        'url': 'https://example.com/work/1/',
      }, const []),
    ]);

    expect(listReportAdvice(report, acquisition: 'staticHtml'), isEmpty);
  });

  test('group selector diagnosis survives the isolate', () async {
    await expectLater(
      extractListRowsSafely(
        makePage('<div class="slot"></div>'),
        makeRule(group: '['),
        timeout: const Duration(seconds: 10),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('まとまりのセレクターが不正です'),
        ),
      ),
    );
  });

  test('extraction timeout is not classified as network timeout', () {
    final message = ruleFailureMessage(
      const FormatException('一覧テストが時間上限を超えました。正規表現やセレクターを簡単にしてください'),
      stage: RuleDiagnosticStage.extraction,
    );

    expect(message, contains('抽出処理が時間上限'));
    expect(message, contains('通信のタイムアウトとは別'));
  });

  test('diagnostic helpers are connected to both pages', () {
    final lab = File('lib/list_rule_lab_page.dart').readAsStringSync();
    final browse = File('lib/rule_browse_page.dart').readAsStringSync();

    expect(lab, contains("import 'services/rule_diagnostics.dart';"));
    expect(lab, contains('listReportAdvice('));
    expect(lab, contains('ruleIssueMessage(issue)'));

    expect(browse, contains("import 'services/rule_diagnostics.dart';"));
    expect(browse, contains('browseListStatus('));
    expect(browse, contains('next.items.isEmpty'));
    expect(browse, contains('map(ruleIssueMessage)'));
  });
}
