import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/site_rule_bundle.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';
import 'package:offline_comic_reader/site_qr_scanner_page.dart';

String validQr() {
  final fields = defaultListFields();
  fields['title'] = const ListFieldRule(selector: 'a');
  fields['url'] = const ListFieldRule(
    selector: 'a',
    mode: ListValueMode.attribute,
    attribute: 'href',
  );
  return SiteRuleBundle.fromSite(
    SavedSiteRule(
      id: 'AAAAAAAAAAAAAAAAAAAAAA',
      name: 'QR scanner test',
      updatedAt: DateTime.utc(2026, 11, 26),
      rules: {
        'works': ListExtractionRule(
          pageUrl: 'https://example.com/list/',
          kind: 'works',
          groupSelector: '.entry',
          fields: fields,
        ),
      },
    ),
  ).encodeQr();
}

class FakeQrBackend implements SiteQrScannerBackend {
  final events = StreamController<List<String>>.broadcast(sync: true);
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  Object? startError;
  Completer<void>? stopGate;
  List<String> imageCodes = [];

  @override
  Stream<List<String>> get codes => events.stream;

  @override
  Widget preview() => const ColoredBox(color: Colors.black);

  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop() async {
    stops++;
    final gate = stopGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<List<String>> analyze(String path) async => imageCodes;

  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
  }
}

class PopLog extends NavigatorObserver {
  int count = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    count++;
    super.didPop(route, previousRoute);
  }
}

Future<void> openScanner(
  WidgetTester tester,
  FakeQrBackend backend,
  PopLog log,
  List<String?> results, {
  Future<String?> Function()? pickImage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      navigatorObservers: [log],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<String>(
                CupertinoPageRoute<String>(
                  builder: (_) =>
                      SiteQrScannerPage(backend: backend, pickImage: pickImage),
                ),
              );
              results.add(result);
            },
            child: const Text('open scanner'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open scanner'));
  await tester.pumpAndSettle();
  expect(backend.starts, greaterThan(0), reason: '画面遷移完了後に、疑似カメラの開始処理が実行されること');
}

void main() {
  test('validates supported QR without saving or network', () {
    final qr = validQr();
    expect(validateSiteQrPayload(qr), qr);
    expect(
      () => validateSiteQrPayload('https://example.com/'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('非対応'),
        ),
      ),
    );
    expect(
      () => validateSiteQrPayload('${SiteRuleBundle.prefix}broken'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('解析できません'),
        ),
      ),
    );
  });

  testWidgets('valid detection returns once without another tap', (
    tester,
  ) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(tester, backend, log, results);
    final qr = validQr();

    backend.events.add([qr]);
    backend.events.add([qr]);
    await tester.pumpAndSettle();

    expect(results, [qr]);
    expect(log.count, 1);
    expect(find.text('open scanner'), findsOneWidget);
    expect(backend.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported and malformed QR remain on scanner', (tester) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(tester, backend, log, results);

    backend.events.add(['https://example.com/']);
    await tester.pump();
    expect(find.textContaining('非対応のQR'), findsOneWidget);

    backend.events.add(['${SiteRuleBundle.prefix}broken']);
    await tester.pump();
    expect(find.textContaining('サイト設定を解析できません'), findsOneWidget);
    expect(log.count, 0);
    expect(results, isEmpty);

    await tester.tap(find.byKey(const ValueKey('site-qr-back')));
    await tester.pumpAndSettle();
  });

  testWidgets('back during camera stop never pops parent', (tester) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(tester, backend, log, results);

    final gate = Completer<void>();
    backend.stopGate = gate;
    backend.events.add([validQr()]);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('site-qr-back')));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(log.count, 1);
    expect(results, [null]);
    expect(find.text('open scanner'), findsOneWidget);
    expect(backend.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photo cancellation restores scanning', (tester) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(
      tester,
      backend,
      log,
      results,
      pickImage: () async => null,
    );

    await tester.tap(find.byKey(const ValueKey('site-qr-photo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('選択をキャンセル'), findsOneWidget);
    expect(log.count, 0);

    final qr = validQr();
    backend.events.add([qr]);
    await tester.pumpAndSettle();
    expect(results, [qr]);
  });

  testWidgets('photo QR uses the same validation and return path', (
    tester,
  ) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    final qr = validQr();
    backend.imageCodes = [qr];

    await openScanner(
      tester,
      backend,
      log,
      results,
      pickImage: () async => '/test/qr.png',
    );
    await tester.tap(find.byKey(const ValueKey('site-qr-photo')));
    await tester.pumpAndSettle();

    expect(results, [qr]);
    expect(log.count, 1);
    expect(backend.disposals, 1);
  });

  testWidgets('photo with no QR gives a reason and does not close', (
    tester,
  ) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(
      tester,
      backend,
      log,
      results,
      pickImage: () async => '/test/no-qr.png',
    );

    await tester.tap(find.byKey(const ValueKey('site-qr-photo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('QRを検出できませんでした'), findsOneWidget);
    expect(log.count, 0);

    await tester.tap(find.byKey(const ValueKey('site-qr-back')));
    await tester.pumpAndSettle();
  });

  testWidgets('late photo result after back does not pop parent', (
    tester,
  ) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    final photo = Completer<String?>();
    backend.imageCodes = [validQr()];

    await openScanner(
      tester,
      backend,
      log,
      results,
      pickImage: () => photo.future,
    );
    await tester.tap(find.byKey(const ValueKey('site-qr-photo')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('site-qr-back')));
    await tester.pumpAndSettle();
    photo.complete('/test/qr.png');
    await tester.pumpAndSettle();

    expect(log.count, 1);
    expect(results, [null]);
    expect(find.text('open scanner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera failure is visible and photo remains available', (
    tester,
  ) async {
    final backend = FakeQrBackend()..startError = StateError('camera failed');
    final log = PopLog();
    final results = <String?>[];

    await openScanner(
      tester,
      backend,
      log,
      results,
      pickImage: () async => null,
    );
    expect(find.textContaining('カメラを起動・使用できませんでした'), findsOneWidget);
    expect(find.byKey(const ValueKey('site-qr-photo')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('site-qr-back')));
    await tester.pumpAndSettle();
  });

  testWidgets('inactive blocks detection and resumed restarts camera', (
    tester,
  ) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(tester, backend, log, results);
    final starts = backend.starts;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    backend.events.add([validQr()]);
    await tester.pump();
    expect(log.count, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.starts, greaterThan(starts));

    backend.events.add([validQr()]);
    await tester.pumpAndSettle();
    expect(log.count, 1);
  });

  testWidgets('cancelled iOS back swipe leaves scanner usable', (tester) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(tester, backend, log, results);

    final gesture = await tester.startGesture(const Offset(2, 300));
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 100));

    backend.events.add([validQr()]);
    await tester.pump();
    expect(log.count, 0);

    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(SiteQrScannerPage), findsOneWidget);
    expect(log.count, 0);

    backend.events.add([validQr()]);
    await tester.pumpAndSettle();
    expect(log.count, 1);
    expect(results.single, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed iOS back swipe closes only the scanner', (
    tester,
  ) async {
    final backend = FakeQrBackend();
    final log = PopLog();
    final results = <String?>[];
    await openScanner(tester, backend, log, results);

    final gesture = await tester.startGesture(const Offset(2, 300));
    await gesture.moveBy(const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 100));
    backend.events.add([validQr()]);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(log.count, 1);
    expect(results, [null]);
    expect(find.text('open scanner'), findsOneWidget);
    expect(backend.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanner can be opened and closed repeatedly', (tester) async {
    final log = PopLog();
    final results = <String?>[];

    for (var i = 0; i < 3; i++) {
      final backend = FakeQrBackend();
      await openScanner(tester, backend, log, results);
      await tester.tap(find.byKey(const ValueKey('site-qr-back')));
      await tester.pumpAndSettle();
      expect(backend.disposals, 1);
      expect(find.text('open scanner'), findsOneWidget);
    }
    expect(results, [null, null, null]);
    expect(tester.takeException(), isNull);
  });
}
