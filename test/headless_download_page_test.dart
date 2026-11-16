import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/headless_download_page.dart';

void main() {
  test('開始前に中断された場合はWebViewを作らず終了する', () async {
    final token = CancelToken()..cancel('test');

    await expectLater(
      fetchRenderedDownloadPage(
        'https://example.com/chapter/1/',
        cancelToken: token,
        allowedOrigin: 'https://example.com',
        groupSelector: '.reader img',
      ),
      throwsStateError,
    );
  });

  test('別取得元のURLはWebViewを作らず拒否する', () async {
    await expectLater(
      fetchRenderedDownloadPage(
        'https://other.example/chapter/1/',
        cancelToken: CancelToken(),
        allowedOrigin: 'https://example.com',
        groupSelector: '.reader img',
      ),
      throwsFormatException,
    );
  });

  test('HTTPS以外のURLは拒否する', () async {
    await expectLater(
      fetchRenderedDownloadPage(
        'http://example.com/chapter/1/',
        cancelToken: CancelToken(),
        allowedOrigin: 'http://example.com',
        groupSelector: '.reader img',
      ),
      throwsFormatException,
    );
  });

  test('空の本文セレクターはWebViewを作らず拒否する', () async {
    await expectLater(
      fetchRenderedDownloadPage(
        'https://example.com/chapter/1/',
        cancelToken: CancelToken(),
        allowedOrigin: 'https://example.com',
        groupSelector: '   ',
      ),
      throwsFormatException,
    );
  });
}
