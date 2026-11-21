import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/tag_browse_url.dart';

void main() {
  group('tagBrowseTargetUri', () {
    test('RawkumaのジャンルURLを更新順の作品一覧へ変換する', () {
      final result = tagBrowseTargetUri(
        Uri.parse('https://rawkuma.net/genre/seinen/'),
      );

      expect(result.origin, 'https://rawkuma.net');
      expect(result.path, '/library/');
      expect(result.queryParameters['the_genre'], 'seinen');
      expect(result.queryParameters['the_page'], '1');
      expect(result.queryParameters['orderby'], 'updated');
      expect(result.queryParameters['order'], 'desc');
      expect(result.hasFragment, isFalse);
    });

    test('ジャンル名を固定せずリンク先から取得する', () {
      final result = tagBrowseTargetUri(
        Uri.parse('https://rawkuma.net/genre/fantasy/'),
      );

      expect(result.queryParameters['the_genre'], 'fantasy');
      expect(result.queryParameters['orderby'], 'updated');
    });

    test('既存の絞り込み条件を維持する', () {
      final result = tagBrowseTargetUri(
        Uri.parse(
          'https://rawkuma.net/library/'
          '?the_genre=seinen'
          '&the_author='
          '&the_artist='
          '&the_exclude='
          '&the_status=ongoing'
          '&search_term=magic'
          '&project=0'
          '&the_page=7'
          '&orderby=title'
          '&order=asc',
        ),
      );

      expect(result.queryParameters['the_genre'], 'seinen');
      expect(result.queryParameters['the_author'], '');
      expect(result.queryParameters['the_artist'], '');
      expect(result.queryParameters['the_exclude'], '');
      expect(result.queryParameters['the_status'], 'ongoing');
      expect(result.queryParameters['search_term'], 'magic');
      expect(result.queryParameters['project'], '0');
      expect(result.queryParameters['the_page'], '1');
      expect(result.queryParameters['orderby'], 'updated');
      expect(result.queryParameters['order'], 'desc');
    });

    test('他サイトのタグURLは変更しない', () {
      final input = Uri.parse(
        'https://example.com/genre/seinen/?page=3&order=asc',
      );

      expect(tagBrowseTargetUri(input), input);
    });

    test('未対応のRawkumaのパスは変更しない', () {
      final input = Uri.parse('https://rawkuma.net/manga/example/');

      expect(tagBrowseTargetUri(input), input);
    });

    test('www付きでも取得元を維持する', () {
      final result = tagBrowseTargetUri(
        Uri.parse('https://www.rawkuma.net/genre/seinen/'),
      );

      expect(result.origin, 'https://www.rawkuma.net');
      expect(result.path, '/library/');
      expect(result.queryParameters['the_genre'], 'seinen');
    });

    test('フラグメントを除去して余分な末尾シャープを付けない', () {
      final result = tagBrowseTargetUri(
        Uri.parse('https://rawkuma.net/genre/seinen/#list'),
      );

      expect(result.hasFragment, isFalse);
      expect(result.toString().endsWith('#'), isFalse);
    });

    test('同じ処理を繰り返しても結果が変わらない', () {
      final first = tagBrowseTargetUri(
        Uri.parse('https://rawkuma.net/genre/seinen/'),
      );

      final second = tagBrowseTargetUri(first);

      expect(second, first);
    });
  });
}
