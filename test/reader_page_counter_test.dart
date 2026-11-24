import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/reader_page_counter.dart';

Widget controls({
  required bool showCounter,
  int current = 12,
  int total = 80,
  double scale = 1,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                key: const ValueKey('title-row'),
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'A long work title that must not wrap',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        if (showCounter) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: ReaderPageCounter(
                              current: current,
                              total: total,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.star_border),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.visibility_off_outlined),
                  ),
                ],
              ),
              const SizedBox(key: ValueKey('reading-mode-row'), height: 40),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows current image and total', (tester) async {
    await tester.pumpWidget(controls(showCounter: true));

    expect(find.text('12 / 80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates when current image changes', (tester) async {
    await tester.pumpWidget(controls(showCounter: true, current: 12));
    expect(find.text('12 / 80'), findsOneWidget);

    await tester.pumpWidget(controls(showCounter: true, current: 13));
    expect(find.text('13 / 80'), findsOneWidget);
    expect(find.text('12 / 80'), findsNothing);
  });

  testWidgets('counter does not increase title row or move mode controls', (
    tester,
  ) async {
    await tester.pumpWidget(controls(showCounter: false));

    final titleBefore = tester
        .getSize(find.byKey(const ValueKey('title-row')))
        .height;

    final modeBefore = tester
        .getTopLeft(find.byKey(const ValueKey('reading-mode-row')))
        .dy;

    await tester.pumpWidget(controls(showCounter: true));

    final titleAfter = tester
        .getSize(find.byKey(const ValueKey('title-row')))
        .height;

    final modeAfter = tester
        .getTopLeft(find.byKey(const ValueKey('reading-mode-row')))
        .dy;

    expect(titleAfter, titleBefore);
    expect(modeAfter, modeBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large image counts and enlarged text fit without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      controls(showCounter: true, current: 12345, total: 99999, scale: 2),
    );

    expect(find.text('12345 / 99999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty image list has no counter', (tester) async {
    await tester.pumpWidget(controls(showCounter: true, current: 0, total: 0));

    expect(
      find.byKey(const ValueKey('reader-page-counter-text')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('displayed page is kept within available image range', (
    tester,
  ) async {
    await tester.pumpWidget(
      controls(showCounter: true, current: 100, total: 80),
    );
    expect(find.text('80 / 80'), findsOneWidget);

    await tester.pumpWidget(controls(showCounter: true, current: 0, total: 80));
    expect(find.text('1 / 80'), findsOneWidget);
  });
}
