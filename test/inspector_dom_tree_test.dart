import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/inspector_dom_tree.dart';

Map<String, Object?> node(
  int id, {
  int depth = 0,
  int children = 0,
  bool expanded = false,
  bool selectable = true,
  bool more = false,
}) => {
  'id': id,
  'depth': depth,
  'tag': more ? '' : 'div',
  'attrs': more ? <String, String>{} : {'class': 'item-$id'},
  'text': more ? '' : 'node $id',
  'childCount': children,
  'expanded': expanded,
  'selectable': selectable,
  'more': more,
  'remaining': more ? 70 : 0,
  'canLoadMore': more,
};

InspectorTreeSnapshot snapshot(
  List<Object?> rows, {
  int selected = 0,
  Set<int> expanded = const {},
}) => InspectorTreeSnapshot.fromJson({
  'rows': rows,
  'selectedId': selected,
  'expanded': expanded.toList(),
  'limited': false,
});

void main() {
  test('tree snapshot parses attributes and selection', () {
    final value = snapshot([node(1)], selected: 1);
    expect(value.selectedId, 1);
    expect(value.rows.single.attrs['class'], 'item-1');
  });

  test('malformed and excessive tree data are rejected', () {
    expect(
      () => InspectorTreeSnapshot.fromJson({'rows': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => snapshot(List.generate(1201, (index) => node(index + 1))),
      throwsFormatException,
    );
    expect(() => snapshot([node(1, depth: 100)]), throwsFormatException);
    expect(() => snapshot([node(1), node(1)]), throwsFormatException);
  });

  testWidgets('branches expand and collapse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorDomTree(
            revision: 0,
            onSelect: (_) async => true,
            onRead: (expanded, limits, reveal) async => snapshot([
              node(1, children: 1, expanded: expanded.contains(1)),
              if (expanded.contains(1)) node(2, depth: 1),
            ], expanded: expanded),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dom-node-2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dom-expand-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dom-node-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dom-expand-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dom-node-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a row delegates the exact element ID', (tester) async {
    final selected = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorDomTree(
            revision: 0,
            onRead: (expanded, limits, reveal) async => snapshot([node(7)]),
            onSelect: (id) async {
              selected.add(id);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dom-node-7')));
    await tester.pumpAndSettle();

    expect(selected, [7]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('out-of-scope rows cannot be selected', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorDomTree(
            revision: 0,
            onRead: (expanded, limits, reveal) async =>
                snapshot([node(1, selectable: false)]),
            onSelect: (_) async {
              calls++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.widget<InkWell>(
      find.byKey(const ValueKey('dom-node-1')),
    );
    expect(row.onTap, isNull);
    expect(calls, 0);
  });

  testWidgets('more button increases only the requested branch limit', (
    tester,
  ) async {
    var lastLimit = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorDomTree(
            revision: 0,
            onRead: (expanded, limits, reveal) async {
              lastLimit = limits[1] ?? 60;
              return snapshot(
                [
                  node(1, children: 130, expanded: true),
                  node(1, depth: 1, more: true),
                ],
                expanded: {1},
              );
            },
            onSelect: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dom-more-1')));
    await tester.pumpAndSettle();

    expect(lastLimit, 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen and large text do not overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: InspectorDomTree(
              revision: 0,
              onRead: (expanded, limits, reveal) async =>
                  snapshot([node(1, depth: 20)]),
              onSelect: (_) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
