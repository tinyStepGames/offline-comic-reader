import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/rendered_list_readiness.dart';

void main() {
  bool observe(
    RenderedListReadiness gate,
    int milliseconds, {
    String ready = 'interactive',
    int count = 24,
    String signature = 'list-a',
  }) {
    return gate.observe(
      now: Duration(milliseconds: milliseconds),
      ready: ready,
      count: count,
      signature: signature,
    );
  }

  test('一覧があっても最初の観測だけでは取得しない', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 2000), isFalse);
  });

  test('最低待機時間より前には取得しない', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0), isFalse);
    expect(observe(gate, 1000), isFalse);
    expect(observe(gate, 1499), isFalse);
    expect(observe(gate, 1500), isTrue);
  });

  test('completeになる前でも一覧が安定すれば取得できる', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0), isFalse);
    expect(observe(gate, 1600), isTrue);
  });

  test('一覧の内容が変わると安定待ちをやり直す', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0), isFalse);
    expect(observe(gate, 1400, signature: 'list-b'), isFalse);
    expect(observe(gate, 2200, signature: 'list-b'), isFalse);
    expect(observe(gate, 2300, signature: 'list-b'), isTrue);
  });

  test('0件の状態では取得しない', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0, count: 0), isFalse);
    expect(observe(gate, 10000, count: 0), isFalse);
  });

  test('loadingの状態では取得しない', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0, ready: 'loading'), isFalse);
    expect(observe(gate, 10000, ready: 'loading'), isFalse);
  });

  test('ページ移動後は最低待機時間から確認し直す', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0), isFalse);
    expect(observe(gate, 2000), isTrue);

    gate.reset(const Duration(milliseconds: 2500));

    expect(observe(gate, 2600), isFalse);
    expect(observe(gate, 3999), isFalse);
    expect(observe(gate, 4000), isTrue);
  });

  test('途中で0件になると安定判定をやり直す', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0), isFalse);
    expect(observe(gate, 2000), isTrue);
    expect(observe(gate, 2100, count: 0), isFalse);
    expect(observe(gate, 2200), isFalse);
    expect(observe(gate, 3000), isFalse);
    expect(observe(gate, 3100), isTrue);
  });

  test('件数が増えた場合も安定待ちをやり直す', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0, count: 12, signature: '12:content-a'), isFalse);

    expect(observe(gate, 1400, count: 24, signature: '24:content-b'), isFalse);

    expect(observe(gate, 2200, count: 24, signature: '24:content-b'), isFalse);

    expect(observe(gate, 2300, count: 24, signature: '24:content-b'), isTrue);
  });

  test('空のフィンガープリントでは取得しない', () {
    final gate = RenderedListReadiness();

    expect(observe(gate, 0, signature: ''), isFalse);

    expect(observe(gate, 10000, signature: ''), isFalse);
  });
}
