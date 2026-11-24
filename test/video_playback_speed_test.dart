import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/video_playback_speed.dart';
import '../lib/video_speed_button.dart';

void main() {
  setUp(() => VideoPlaybackSpeed.remember(1));
  tearDown(() => VideoPlaybackSpeed.remember(1));

  test('supports agreed playback speeds and readable labels', () {
    expect(VideoPlaybackSpeed.values, [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]);
    expect(VideoPlaybackSpeed.label(1), '1×');
    expect(VideoPlaybackSpeed.label(1.75), '1.75×');
    expect(VideoPlaybackSpeed.label(2), '2×');
  });

  test('remembers playback speed for later player sessions', () {
    expect(VideoPlaybackSpeed.rate, 1);
    VideoPlaybackSpeed.remember(2);
    expect(VideoPlaybackSpeed.rate, 2);
    VideoPlaybackSpeed.remember(0.75);
    expect(VideoPlaybackSpeed.rate, 0.75);
  });

  test('invalid rates cannot replace the selected speed', () {
    VideoPlaybackSpeed.remember(1.5);
    for (final value in [0.0, -1.0, 3.0, double.nan, double.infinity]) {
      expect(() => VideoPlaybackSpeed.remember(value), throwsArgumentError);
    }
    expect(VideoPlaybackSpeed.rate, 1.5);
  });

  testWidgets('menu applies a speed and updates current label', (tester) async {
    var rate = 1.0;
    double? applied;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            appBar: AppBar(
              title: const Text('Video'),
              actions: [
                VideoSpeedButton(
                  rate: rate,
                  enabled: true,
                  onChanged: (value) async {
                    applied = value;
                    setState(() => rate = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video-speed-current')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(CheckedPopupMenuItem<double>, '2×'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '2×'));
    await tester.pumpAndSettle();

    expect(applied, 2);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('video-speed-current')))
          .data,
      '2×',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled speed control cannot open the menu', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              VideoSpeedButton(
                rate: 1,
                enabled: false,
                onChanged: (_) async {
                  calls++;
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video-speed-current')));
    await tester.pumpAndSettle();

    expect(find.text('2×'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('failed application preserves displayed speed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              VideoSpeedButton(
                rate: 1,
                enabled: true,
                onChanged: (_) async => throw StateError('test failure'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video-speed-current')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(CheckedPopupMenuItem<double>, '2×'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '2×'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('video-speed-current')))
          .data,
      '1×',
    );
    expect(find.textContaining('再生速度を変更できませんでした'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('speed button stays fixed size with enlarged text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: VideoSpeedButton(
                key: const ValueKey('speed-button'),
                rate: 1.75,
                enabled: true,
                onChanged: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('speed-button'))),
      const Size(56, 48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('speed menu stays disabled while change is pending', (
    tester,
  ) async {
    final completer = Completer<void>();
    var rate = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            appBar: AppBar(
              actions: [
                VideoSpeedButton(
                  rate: rate,
                  enabled: true,
                  onChanged: (value) async {
                    await completer.future;
                    setState(() => rate = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video-speed-current')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(CheckedPopupMenuItem<double>, '2×'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '2×'));
    await tester.pumpAndSettle();

    final popup = tester.widget<PopupMenuButton<double>>(
      find.byType(PopupMenuButton<double>),
    );
    expect(popup.enabled, isFalse);

    completer.complete();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('video-speed-current')))
          .data,
      '2×',
    );
    expect(tester.takeException(), isNull);
  });
}
