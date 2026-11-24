import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/serial_download_batch.dart';

void main() {
  test('保存済みをスキップし、未保存だけを順番に処理する', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final saved = <int>[];

    await queue.run(
      [1, 2, 3],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '第$item話',
      isSaved: (item) async => item == 2,
      save: (item) async => saved.add(item),
    );

    expect(saved, [1, 3]);
    expect(queue.state.value.saved, 2);
    expect(queue.state.value.skipped, 1);
    expect(queue.state.value.processed, 3);
    expect(queue.state.value.running, isFalse);
  });

  test('同じ保存IDの重複を処理しない', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final saved = <int>[];

    await queue.run(
      [1, 1, 2],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '$item',
      isSaved: (_) async => false,
      save: (item) async => saved.add(item),
    );

    expect(saved, [1, 2]);
    expect(queue.state.value.total, 2);
  });

  test('失敗した話を記録して次の話を処理する', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final attempted = <int>[];

    await queue.run(
      [1, 2, 3],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '第$item話',
      isSaved: (_) async => false,
      save: (item) async {
        attempted.add(item);
        if (item == 2) throw StateError('test failure');
      },
    );

    expect(attempted, [1, 2, 3]);
    expect(queue.state.value.saved, 2);
    expect(queue.state.value.failures.single, contains('第2話'));
    expect(queue.state.value.processed, 3);
  });

  test('停止後は次の話へ進まず、中断を失敗として数えない', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final entered = Completer<void>();
    final release = Completer<void>();
    final attempted = <int>[];

    final operation = queue.run(
      [1, 2, 3],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '$item',
      isSaved: (_) async => false,
      save: (item) async {
        attempted.add(item);
        entered.complete();
        await release.future;
        throw StateError('cancelled');
      },
    );

    await entered.future;
    queue.stop();
    release.complete();
    await operation;

    expect(attempted, [1]);
    expect(queue.state.value.stopped, isTrue);
    expect(queue.state.value.failures, isEmpty);
    expect(queue.state.value.saved, 0);
  });

  test('話を並列処理せず、同時に開始しない', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final entered = Completer<void>();
    final release = Completer<void>();
    final saved = <int>[];

    final operation = queue.run(
      [1, 2],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '$item',
      isSaved: (_) async => false,
      save: (item) async {
        saved.add(item);
        if (item == 1) {
          entered.complete();
          await release.future;
        }
      },
    );

    await entered.future;
    expect(saved, [1]);

    await expectLater(
      queue.run(
        [3],
        scope: 'other',
        keyOf: (item) => '$item',
        titleOf: (item) => '$item',
        isSaved: (_) async => false,
        save: (_) async {},
      ),
      throwsStateError,
    );

    release.complete();
    await operation;

    expect(saved, [1, 2]);
  });

  test('再実行時は前回保存した話をスキップする', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final completed = <int>{};
    final saved = <int>[];

    Future<void> run() => queue.run(
      [1, 2],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '$item',
      isSaved: (item) async => completed.contains(item),
      save: (item) async {
        completed.add(item);
        saved.add(item);
      },
    );

    await run();
    await run();

    expect(saved, [1, 2]);
    expect(queue.state.value.saved, 0);
    expect(queue.state.value.skipped, 2);
  });

  test('保存済み確認中の停止でも次の話を開始しない', () async {
    final queue = SerialDownloadBatch<int>();
    addTearDown(queue.state.dispose);

    final entered = Completer<void>();
    final checked = Completer<bool>();
    final saved = <int>[];

    final operation = queue.run(
      [1, 2],
      scope: 'work',
      keyOf: (item) => '$item',
      titleOf: (item) => '$item',
      isSaved: (_) {
        entered.complete();
        return checked.future;
      },
      save: (item) async => saved.add(item),
    );

    await entered.future;
    queue.stop();
    checked.complete(false);
    await operation;

    expect(saved, isEmpty);
    expect(queue.state.value.stopped, isTrue);
  });
}
