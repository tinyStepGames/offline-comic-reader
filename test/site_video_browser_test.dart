import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_comic_reader/services/site_video_browser_policy.dart';
import 'package:offline_comic_reader/site_video_browser_page.dart';

void main() {
  test('keeps the selected episode URL rather than a fixed mirror URL', () {
    final first = SiteVideoBrowserPolicy(
      'https://example.com/episode-1/?server=moon',
    );
    final second = SiteVideoBrowserPolicy('https://example.com/episode-2/');

    expect(first.initial.path, '/episode-1/');
    expect(first.initial.query, 'server=moon');
    expect(second.initial.path, '/episode-2/');
  });

  test('main frame stays on the original origin', () {
    final policy = SiteVideoBrowserPolicy('https://example.com/episode-1/');

    expect(policy.allowsMainFrame('https://example.com/episode-2/'), isTrue);
    expect(policy.allowsMainFrame('https://mirror.example.org/'), isFalse);
    expect(policy.allowsMainFrame('http://example.com/'), isFalse);
    expect(
      policy.allowsMainFrame('https://user:password@example.com/'),
      isFalse,
    );
  });

  test('allows external HTTPS embedded players', () {
    final policy = SiteVideoBrowserPolicy('https://example.com/episode-1/');

    expect(
      policy.allowsSubframe('https://mirror.example.org/embed/episode-1'),
      isTrue,
    );
    expect(policy.allowsSubframe('about:blank'), isTrue);
    expect(policy.allowsSubframe('about:srcdoc'), isTrue);
    expect(
      policy.allowsSubframe('blob:https://mirror.example.org/example-id'),
      isTrue,
    );
  });

  test('rejects file javascript insecure and credentialed frames', () {
    final policy = SiteVideoBrowserPolicy('https://example.com/episode-1/');

    for (final value in [
      'file:///C:/private.txt',
      'javascript:alert(1)',
      'http://mirror.example.org/embed',
      'https://user:password@mirror.example.org/embed',
      'blob:file:///C:/private.txt',
      'blob:null/example-id',
      'https://localhost/embed',
    ]) {
      expect(policy.allowsSubframe(value), isFalse, reason: value);
    }
  });

  test('initial page rejects unsafe schemes and local hostnames', () {
    for (final value in [
      'file:///C:/private.txt',
      'http://example.com/',
      'https://localhost/',
      'https://machine.local/',
    ]) {
      expect(() => SiteVideoBrowserPolicy(value), throwsFormatException);
    }
  });

  testWidgets('browser entry invokes only the explicit user action', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SiteVideoBrowserButton(onPressed: () => calls++)),
      ),
    );

    expect(calls, 0);
    expect(find.text('サイトプレーヤーで開く'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled browser entry does not navigate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SiteVideoBrowserButton(onPressed: null)),
      ),
    );

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('compact entry uses an icon without adding another row', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              SiteVideoBrowserButton(compact: true, onPressed: () => calls++),
            ],
          ),
        ),
      ),
    );

    expect(find.byTooltip('サイトプレーヤーで開く'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
