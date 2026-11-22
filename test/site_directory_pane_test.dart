import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/site_directory_pane.dart';

void main() {
  testWidgets('サイト一覧に制作室と内蔵サンプルを表示する', (tester) async {
    var labOpened = false;
    var builtinOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiteDirectoryPane(
            sites: const [],
            activeSiteId: null,
            busy: false,
            error: null,
            onOpen: (site) {
              builtinOpened = site == null;
            },
            onManage: (_) {},
            onLab: () => labOpened = true,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('サイト管理・JSON／QR'), findsOneWidget);
    expect(find.text('新規サイトルール作成'), findsOneWidget);

    await tester.tap(find.text('新規サイトルール作成'));
    expect(labOpened, isTrue);

    await tester.ensureVisible(find.text('ペッパー＆キャロット'));
    await tester.tap(find.text('ペッパー＆キャロット'));

    expect(builtinOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('狭い画面でも操作部分がオーバーフローしない', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiteDirectoryPane(
            sites: const [],
            activeSiteId: null,
            busy: false,
            error: null,
            onOpen: (_) {},
            onManage: (_) {},
            onLab: () {},
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
