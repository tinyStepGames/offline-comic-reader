import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/reader_horizontal_pager.dart';

Future<void> mountPager(
  WidgetTester tester, {
  required PageController controller,
  ValueChanged<int>? onPageChanged,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onToggleControls,
  ValueChanged<int>? onZoom,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 400,
            child: ReaderHorizontalPager(
              key: const ValueKey('pager'),
              controller: controller,
              itemCount: 3,
              onPageChanged: onPageChanged ?? (_) {},
              onPrevious: onPrevious,
              onNext: onNext,
              onToggleControls: onToggleControls ?? () {},
              onZoom: onZoom ?? (_) {},
              imageBuilder: (context, index) {
                return Text('page-$index');
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('左右1/3と中央1/3で操作を分ける', (tester) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);

    var previous = 0;
    var next = 0;
    var controls = 0;

    await mountPager(
      tester,
      controller: controller,
      onPrevious: () => previous++,
      onNext: () => next++,
      onToggleControls: () => controls++,
    );

    final rect = tester.getRect(find.byKey(const ValueKey('pager')));

    await tester.tapAt(Offset(rect.left + rect.width / 6, rect.center.dy));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(previous, 1);
    expect(next, 0);
    expect(controls, 0);

    await tester.tapAt(rect.center);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(previous, 1);
    expect(next, 0);
    expect(controls, 1);

    await tester.tapAt(Offset(rect.right - rect.width / 6, rect.center.dy));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(previous, 1);
    expect(next, 1);
    expect(controls, 1);
  });

  testWidgets('タッチスワイプで次と前のページへ移動する', (tester) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);

    var current = 1;

    await mountPager(
      tester,
      controller: controller,
      onPageChanged: (index) => current = index,
    );

    await tester.drag(
      find.byKey(const ValueKey('pager')),
      const Offset(-450, 0),
    );
    await tester.pumpAndSettle();

    expect(current, 2);

    await tester.drag(
      find.byKey(const ValueKey('pager')),
      const Offset(450, 0),
    );
    await tester.pumpAndSettle();

    expect(current, 1);
  });

  testWidgets('マウスドラッグでページを移動できる', (tester) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);

    var current = 1;

    await mountPager(
      tester,
      controller: controller,
      onPageChanged: (index) => current = index,
    );

    final rect = tester.getRect(find.byKey(const ValueKey('pager')));
    final gesture = await tester.startGesture(
      Offset(rect.right - 50, rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 30));

    await gesture.moveBy(const Offset(-420, 0));
    await tester.pump(const Duration(milliseconds: 150));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(current, 2);
  });

  testWidgets('ダブルタップではページ送りせず拡大する', (tester) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);

    var next = 0;
    var zoomed = -1;

    await mountPager(
      tester,
      controller: controller,
      onNext: () => next++,
      onZoom: (index) => zoomed = index,
    );

    final rect = tester.getRect(find.byKey(const ValueKey('pager')));
    final position = Offset(rect.right - rect.width / 6, rect.center.dy);

    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(position);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(zoomed, 1);
    expect(next, 0);
  });

  testWidgets('端のページで無効なタップをしてもエラーにならない', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);

    await mountPager(tester, controller: controller);

    final rect = tester.getRect(find.byKey(const ValueKey('pager')));

    await tester.tapAt(Offset(rect.left + 30, rect.center.dy));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    await tester.tapAt(Offset(rect.right - 30, rect.center.dy));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(controller.page, 0);
  });
}
