import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/extraction_rule_transfer.dart';
import 'package:offline_comic_reader/services/html_probe.dart';

void main() {
  const draft = ExtractionDraft(
    pageUrl: 'https://example.com/comics/',
    selector: '.comic-card img',
    attribute: 'src',
    mode: HtmlValueMode.attribute,
    resolveUrls: true,
    acquisition: 'renderedDom',
  );

  test('JSONで往復できる', () {
    final restored = ExtractionDraft.parse(draft.encodeJson());
    expect(restored.pageUrl, draft.pageUrl);
    expect(restored.selector, draft.selector);
    expect(restored.mode, draft.mode);
    expect(restored.acquisition, 'renderedDom');
  });

  test('QR内容の文字列で往復できる', () {
    final restored = ExtractionDraft.parse(draft.encodeQr());
    expect(restored.selector, draft.selector);
    expect(restored.attribute, 'src');
  });

  test('未対応バージョンを拒否する', () {
    final data = draft.toJson()..['version'] = 999;
    expect(
      () => ExtractionDraft.parse(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test('未知の設定項目を拒否する', () {
    final data = draft.toJson()..['script'] = 'not allowed';
    expect(
      () => ExtractionDraft.parse(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test('大きすぎるQRを拒否する', () {
    final large = ExtractionDraft(
      pageUrl: draft.pageUrl,
      selector: List.filled(1800, 'a').join(),
      attribute: draft.attribute,
      mode: draft.mode,
      resolveUrls: draft.resolveUrls,
      acquisition: draft.acquisition,
    );

    expect(large.encodeQr, throwsFormatException);
  });
}
