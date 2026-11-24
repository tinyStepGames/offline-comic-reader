import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/html_probe.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/list_field_pick.dart';

void main() {
  test('タイトルは内側の文字列として設定する', () {
    final field = listFieldFromPick(
      key: 'title',
      selector: '.title',
      mode: HtmlValueMode.text,
      attribute: 'href',
    );
    expect(field.selector, '.title');
    expect(field.mode, ListValueMode.text);
    expect(field.attribute, '');
    expect(field.enabled, isTrue);
  });

  test('空セレクターは要素自身として保持する', () {
    final field = listFieldFromPick(
      key: 'url',
      selector: '',
      mode: HtmlValueMode.attribute,
      attribute: 'href',
    );
    expect(field.selector, '');
    expect(field.attribute, 'href');
    expect(field.mode, ListValueMode.attribute);
  });

  test('表紙のstyleは背景画像URLの取得にする', () {
    final field = listFieldFromPick(
      key: 'thumbnail',
      selector: '',
      mode: HtmlValueMode.attribute,
      attribute: 'style',
    );
    expect(field.mode, ListValueMode.cssUrl);
    expect(field.attribute, 'style');
    expect(field.enabled, isTrue);
  });

  test('遅延読込画像のdata-srcを保持する', () {
    final field = listFieldFromPick(
      key: 'thumbnail',
      selector: 'img',
      mode: HtmlValueMode.attribute,
      attribute: 'data-src',
    );
    expect(field.mode, ListValueMode.attribute);
    expect(field.attribute, 'data-src');
  });

  test('HTML取得は一覧の項目として受け付けない', () {
    expect(
      () => listFieldFromPick(
        key: 'title',
        selector: '',
        mode: HtmlValueMode.innerHtml,
        attribute: '',
      ),
      throwsFormatException,
    );
  });

  test('未対応の項目は受け付けない', () {
    expect(
      () => listFieldFromPick(
        key: 'unknown',
        selector: '',
        mode: HtmlValueMode.text,
        attribute: '',
      ),
      throwsFormatException,
    );
  });
}
