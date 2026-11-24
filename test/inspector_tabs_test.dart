import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/inspector_tabs.dart';

class BrowserProbe extends StatefulWidget {
  const BrowserProbe({super.key});

  static int starts = 0;
  static int stops = 0;

  @override
  State<BrowserProbe> createState() => _BrowserProbeState();
}

class _BrowserProbeState extends State<BrowserProbe> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    BrowserProbe.starts++;
  }

  @override
  void dispose() {
    BrowserProbe.stops++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('browser taps: $taps'),
    ),
  );
}

Widget inspector() => const MaterialApp(
  home: Scaffold(
    body: InspectorTabs(
      browser: BrowserProbe(),
      tree: Center(child: Text('tree content')),
      details: Center(child: Text('details content')),
    ),
  ),
);

void resetProbe() {
  BrowserProbe.starts = 0;
  BrowserProbe.stops = 0;
}

void main() {
  testWidgets('wide layout places the page left and tools right', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    resetProbe();

    await tester.pumpWidget(inspector());
    await tester.pumpAndSettle();

    final split = tester.widget<Flex>(
      find.byKey(const ValueKey('inspector-split')),
    );
    expect(split.direction, Axis.horizontal);

    final pageRect = tester.getRect(
      find.byKey(const ValueKey('inspector-page-pane')),
    );
    final toolsRect = tester.getRect(
      find.byKey(const ValueKey('inspector-tools-pane')),
    );

    expect(pageRect.right, lessThanOrEqualTo(toolsRect.left));
    expect(find.text('browser taps: 0').hitTestable(), findsOneWidget);
    expect(find.text('tree content').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout places the page above the tools', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    resetProbe();

    await tester.pumpWidget(inspector());
    await tester.pumpAndSettle();

    final split = tester.widget<Flex>(
      find.byKey(const ValueKey('inspector-split')),
    );
    expect(split.direction, Axis.vertical);

    final pageRect = tester.getRect(
      find.byKey(const ValueKey('inspector-page-pane')),
    );
    final toolsRect = tester.getRect(
      find.byKey(const ValueKey('inspector-tools-pane')),
    );

    expect(pageRect.bottom, lessThanOrEqualTo(toolsRect.top));
    expect(find.text('browser taps: 0').hitTestable(), findsOneWidget);
    expect(find.text('tree content').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching tools keeps the page visible and preserves its state',
    (tester) async {
      resetProbe();

      await tester.pumpWidget(inspector());
      await tester.pumpAndSettle();

      await tester.tap(find.text('browser taps: 0'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('inspector-tab-details')));
      await tester.pumpAndSettle();

      expect(find.text('browser taps: 1').hitTestable(), findsOneWidget);
      expect(find.text('details content').hitTestable(), findsOneWidget);
      expect(find.text('tree content').hitTestable(), findsNothing);

      await tester.tap(find.byKey(const ValueKey('inspector-tab-tree')));
      await tester.pumpAndSettle();

      expect(find.text('browser taps: 1').hitTestable(), findsOneWidget);
      expect(find.text('tree content').hitTestable(), findsOneWidget);
      expect(BrowserProbe.starts, 1);
      expect(BrowserProbe.stops, 0);

      await tester.pumpWidget(const SizedBox());
      expect(BrowserProbe.stops, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resizing preserves browser state and the selected tool', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    resetProbe();

    await tester.pumpWidget(inspector());
    await tester.pumpAndSettle();

    await tester.tap(find.text('browser taps: 0'));
    await tester.tap(find.byKey(const ValueKey('inspector-tab-details')));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.text('browser taps: 1').hitTestable(), findsOneWidget);
    expect(find.text('details content').hitTestable(), findsOneWidget);
    expect(BrowserProbe.starts, 1);
    expect(BrowserProbe.stops, 0);

    final split = tester.widget<Flex>(
      find.byKey(const ValueKey('inspector-split')),
    );
    expect(split.direction, Axis.vertical);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen with large text does not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    resetProbe();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: InspectorTabs(
            browser: BrowserProbe(),
            tree: Center(child: Text('tree')),
            details: Center(child: Text('details')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('browser taps: 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
