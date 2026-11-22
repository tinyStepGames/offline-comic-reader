import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/editor_unsaved_changes.dart';

class _Editor extends StatefulWidget {
  const _Editor({super.key});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> with EditorUnsavedChanges<_Editor> {
  final input = TextEditingController(text: 'original');
  bool busy = false;

  @override
  List<TextEditingController> get editorInputs => [input];

  @override
  bool get editorBusy => busy;

  @override
  String get editorSnapshot => encodeEditorSnapshot({'value': input.text});

  void saveSuccessfully() => setState(markEditorSaved);

  void setBusy(bool value) => setState(() => busy = value);

  @override
  Widget build(BuildContext context) => guardEditor(
    Scaffold(
      appBar: AppBar(leading: editorBackButton, title: const Text('editor')),
      body: Column(
        children: [
          TextField(controller: input),
          TextButton(
            onPressed: () async {
              await applyEditorResult('applied');
            },
            child: const Text('apply'),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}

void main() {
  Future<GlobalKey<_EditorState>> open(
    WidgetTester tester, {
    List<String?>? results,
  }) async {
    final key = GlobalKey<_EditorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(builder: (_) => _Editor(key: key)),
                );
                results?.add(result);
              },
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  test('比較用JSONはMapの挿入順に影響されない', () {
    expect(
      encodeEditorSnapshot({
        'b': {'y': 2, 'x': 1},
        'a': [1, 2],
      }),
      encodeEditorSnapshot({
        'a': [1, 2],
        'b': {'x': 1, 'y': 2},
      }),
    );
  });

  test('正規表現や改行を比較時に変更しない', () {
    expect(
      encodeEditorSnapshot({'pattern': ' (.+)\n'}),
      isNot(encodeEditorSnapshot({'pattern': '(.+)'})),
    );
  });

  testWidgets('変更なしなら確認せず戻れる', (tester) async {
    await open(tester);
    await back(tester);
    expect(find.text('open editor'), findsOneWidget);
    expect(find.text('変更が保存されていません'), findsNothing);
  });

  testWidgets('変更時は確認して編集を続けられる', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'changed';
    await tester.pump();

    await back(tester);
    expect(find.text('変更が保存されていません'), findsOneWidget);

    await tester.tap(find.text('編集を続ける'));
    await tester.pumpAndSettle();

    expect(find.text('editor'), findsOneWidget);
    expect(key.currentState!.input.text, 'changed');
  });

  testWidgets('破棄を選ぶと戻れる', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'changed';
    await tester.pump();

    await back(tester);
    await tester.tap(find.text('変更を破棄して戻る'));
    await tester.pumpAndSettle();

    expect(find.text('open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('元の値に戻せば確認しない', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'changed';
    await tester.pump();
    key.currentState!.input.text = 'original';
    await tester.pump();

    await back(tester);
    expect(find.text('open editor'), findsOneWidget);
    expect(find.text('変更が保存されていません'), findsNothing);
  });

  testWidgets('文字選択だけでは未保存にしない', (tester) async {
    final key = await open(tester);
    key.currentState!.input.selection = const TextSelection.collapsed(
      offset: 2,
    );
    await tester.pump();

    await back(tester);
    expect(find.text('open editor'), findsOneWidget);
  });

  testWidgets('保存成功後は確認しない', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'saved';
    key.currentState!.saveSuccessfully();
    await tester.pump();

    await back(tester);
    expect(find.text('open editor'), findsOneWidget);
    expect(find.text('変更が保存されていません'), findsNothing);
  });

  testWidgets('保存後の再編集は確認する', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'saved';
    key.currentState!.saveSuccessfully();
    await tester.pump();

    key.currentState!.input.text = 'edited again';
    await tester.pump();
    await back(tester);

    expect(find.text('変更が保存されていません'), findsOneWidget);
  });

  testWidgets('処理中は戻らず完了後に確認する', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'changed';
    key.currentState!.setBusy(true);
    await tester.pump();

    await back(tester);
    expect(find.text('editor'), findsOneWidget);
    expect(find.text('変更が保存されていません'), findsNothing);

    key.currentState!.setBusy(false);
    await tester.pump();
    await back(tester);

    expect(find.text('変更が保存されていません'), findsOneWidget);
  });

  testWidgets('システムの戻るでも確認する', (tester) async {
    final key = await open(tester);
    key.currentState!.input.text = 'changed';
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('変更が保存されていません'), findsOneWidget);
  });

  testWidgets('設定反映時は結果を親に返せる', (tester) async {
    final results = <String?>[];
    final key = await open(tester, results: results);

    key.currentState!.input.text = 'changed';
    await tester.pump();
    await tester.tap(find.text('apply'));
    await tester.pumpAndSettle();

    expect(results, ['applied']);
    expect(find.text('変更が保存されていません'), findsNothing);
    expect(find.text('open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
