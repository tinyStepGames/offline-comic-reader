import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/reader_look_ahead.dart';

Future<void> settleQueue() => Future<void>.delayed(Duration.zero);

void main() {
  test('画像を指定順に1件ずつ先読みする', () async {
    final started = <int>[];
    final first = Completer<void>();

    final queue = ReaderLookAhead(
      load: (index) async {
        started.add(index);
        if (index == 1) await first.future;
      },
    );
    addTearDown(queue.dispose);

    queue.update([1, 2]);

    expect(started, [1]);

    first.complete();
    await settleQueue();

    expect(started, [1, 2]);
  });

  test('読書位置変更で古い未着手の予約を破棄する', () async {
    final started = <int>[];
    final first = Completer<void>();

    final queue = ReaderLookAhead(
      load: (index) async {
        started.add(index);
        if (index == 1) await first.future;
      },
    );
    addTearDown(queue.dispose);

    queue.update([1, 2]);
    queue.update([8, 9]);

    first.complete();
    await settleQueue();

    expect(started, [1, 8, 9]);
  });

  test('空の予約に更新すると未着手の先読みを止める', () async {
    final started = <int>[];
    final first = Completer<void>();

    final queue = ReaderLookAhead(
      load: (index) async {
        started.add(index);
        await first.future;
      },
    );
    addTearDown(queue.dispose);

    queue.update([1, 2]);
    queue.update([]);

    first.complete();
    await settleQueue();

    expect(started, [1]);
  });

  test('同じ画像の自動先読みを繰り返さない', () async {
    final started = <int>[];

    final queue = ReaderLookAhead(
      load: (index) async {
        started.add(index);
      },
    );
    addTearDown(queue.dispose);

    queue.update([1, 1, 2]);
    await settleQueue();

    queue.update([1, 2, 3]);
    await settleQueue();

    expect(started, [1, 2, 3]);
  });

  test('先読み失敗でキュー全体を失敗させない', () async {
    final started = <int>[];

    final queue = ReaderLookAhead(
      load: (index) async {
        started.add(index);
        if (index == 1) throw StateError('test failure');
      },
    );
    addTearDown(queue.dispose);

    queue.update([1, 2]);
    await settleQueue();

    expect(started, [1, 2]);
  });

  test('終了後に次の先読みを開始しない', () async {
    final started = <int>[];
    final first = Completer<void>();

    final queue = ReaderLookAhead(
      load: (index) async {
        started.add(index);
        await first.future;
      },
    );

    queue.update([1, 2]);
    queue.dispose();
    queue.update([3, 4]);

    first.complete();
    await settleQueue();

    expect(started, [1]);
  });
}
