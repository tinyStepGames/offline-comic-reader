import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:offline_comic_reader/services/site_qr_png.dart';
import 'package:offline_comic_reader/site_bundle_qr_page.dart';

void main() {
  for (final size in const [Size(390, 844), Size(900, 700)]) {
    testWidgets('QRと画像コピー・保存ボタンを表示する $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final payload =
          'ocr-site:1:gzip:'
          '${List.filled(1300, 'A').join()}';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: SiteBundleQrPage(payload: payload, siteName: 'テストサイト'),
        ),
      );

      await tester.pumpAndSettle();

      final finder = find.byKey(const ValueKey('site-bundle-qr-image'));

      expect(finder, findsOneWidget);
      expect(tester.takeException(), isNull);

      final qr = tester.widget<QrImageView>(finder);

      // QrImageViewにはdata getterがないため参照しない。
      expect(qr.size, greaterThan(0));
      expect(qr.backgroundColor, Colors.white);
      expect(qr.eyeStyle.color, Colors.black);
      expect(qr.dataModuleStyle.color, Colors.black);

      final renderedSize = tester.getSize(finder);

      expect(renderedSize.width, greaterThan(0));
      expect(renderedSize.width, renderedSize.height);

      expect(find.text('画像をコピー'), findsOneWidget);
      expect(find.text('PNGで保存'), findsOneWidget);
      expect(find.text('文字列をコピー'), findsOneWidget);

      expect(find.textContaining('QR画像を生成できませんでした'), findsNothing);
    });
  }

  testWidgets('書き出したPNGは正方形で四隅に白い余白がある', (tester) async {
    await tester.runAsync<void>(() async {
      final payload =
          'ocr-site:1:gzip:'
          '${List.filled(1300, 'A').join()}';

      final bytes = await createSiteQrPng(payload);

      expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);

      final codec = await ui.instantiateImageCodec(bytes);

      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;

        try {
          expect(image.width, image.height);
          expect(image.width, greaterThan(0));

          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );

          expect(pixels, isNotNull);

          final rgba = pixels!;

          for (final point in [
            (0, 0),
            (image.width - 1, 0),
            (0, image.height - 1),
            (image.width - 1, image.height - 1),
          ]) {
            final offset = (point.$2 * image.width + point.$1) * 4;

            expect(List.generate(4, (index) => rgba.getUint8(offset + index)), [
              255,
              255,
              255,
              255,
            ]);
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
  });

  testWidgets('空文字と過大なQR内容はPNG生成前に拒否する', (tester) async {
    await expectLater(createSiteQrPng(''), throwsFormatException);

    await expectLater(
      createSiteQrPng(List.filled(2201, 'A').join()),
      throwsFormatException,
    );
  });
}
