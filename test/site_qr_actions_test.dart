import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:offline_comic_reader/services/site_qr_actions.dart';

Uint8List sampleBytes() =>
    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]);

void main() {
  test('写真保存へQR画像のバイト列を渡す', () async {
    final bytes = sampleBytes();
    var called = 0;

    await saveSiteQrToPhotos(
      bytes,
      writer: (received) async {
        called++;
        expect(received, orderedEquals(bytes));
      },
    );

    expect(called, 1);
  });

  test('PNGではないデータは写真保存へ渡さない', () async {
    var called = 0;

    await expectLater(
      saveSiteQrToPhotos(
        Uint8List.fromList([1, 2, 3]),
        writer: (_) async {
          called++;
        },
      ),
      throwsFormatException,
    );

    expect(called, 0);
  });

  test('共有へ画像・ファイル名・iPadの表示位置を渡す', () async {
    final bytes = sampleBytes();
    const origin = Rect.fromLTWH(20, 30, 100, 40);
    var called = 0;

    final message = await shareSiteQrImage(
      bytes,
      origin: origin,
      invoker: (params) async {
        called++;

        expect(params.fileNameOverrides, ['site-rule.png']);
        expect(params.sharePositionOrigin, origin);
        expect(params.text, isNull);
        expect(params.files, hasLength(1));

        final file = params.files!.single;

        expect(file.mimeType, 'image/png');
        expect(await file.readAsBytes(), orderedEquals(bytes));

        return const ShareResult('test', ShareResultStatus.success);
      },
    );

    expect(called, 1);
    expect(message, contains('共有操作が完了'));
  });

  test('共有のキャンセルを送信成功と表示しない', () async {
    final message = await shareSiteQrImage(
      sampleBytes(),
      origin: const Rect.fromLTWH(0, 0, 100, 40),
      invoker: (_) async => const ShareResult('', ShareResultStatus.dismissed),
    );

    expect(message, '共有を閉じました。');
  });

  test('共有結果を取得できない場合は送信成功と断定しない', () async {
    final message = await shareSiteQrImage(
      sampleBytes(),
      origin: const Rect.fromLTWH(0, 0, 100, 40),
      invoker: (_) async =>
          const ShareResult('', ShareResultStatus.unavailable),
    );

    expect(message, contains('共有結果は共有先アプリ'));
    expect(message, isNot(contains('送信しました')));
  });

  test('不正な画像や表示位置では共有を呼ばない', () async {
    var called = 0;

    Future<ShareResult> fakeShare(ShareParams params) async {
      called++;
      return const ShareResult('', ShareResultStatus.success);
    }

    await expectLater(
      shareSiteQrImage(
        Uint8List(0),
        origin: const Rect.fromLTWH(0, 0, 100, 40),
        invoker: fakeShare,
      ),
      throwsFormatException,
    );

    await expectLater(
      shareSiteQrImage(sampleBytes(), origin: Rect.zero, invoker: fakeShare),
      throwsFormatException,
    );

    expect(called, 0);
  });
}
