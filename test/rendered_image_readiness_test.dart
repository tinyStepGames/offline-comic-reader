import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/rendered_image_readiness.dart';

RenderedImageReadinessSample sample({
  String url = 'https://example.com/chapter/1',
  String ready = 'complete',
  int count = 152,
  int valid = 152,
  String signature = 'ordered-image-urls',
}) => RenderedImageReadinessSample(
  url: url,
  readyState: ready,
  count: count,
  validCount: valid,
  signature: signature,
);

void main() {
  final start = DateTime.utc(2026, 11, 26);

  test('waits for two seconds of stable image URLs', () {
    final tracker = RenderedImageStability();
    expect(tracker.observe(sample(), start), isFalse);
    expect(
      tracker.observe(sample(), start.add(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      tracker.observe(sample(), start.add(const Duration(seconds: 2))),
      isTrue,
    );
  });

  test('interactive DOM can be used without waiting for all resources', () {
    final tracker = RenderedImageStability();
    expect(tracker.observe(sample(ready: 'interactive'), start), isFalse);
    expect(
      tracker.observe(
        sample(ready: 'interactive'),
        start.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
  });

  test('incomplete attributes never count as ready', () {
    final tracker = RenderedImageStability();
    tracker.observe(sample(valid: 151), start);
    expect(
      tracker.observe(
        sample(valid: 151),
        start.add(const Duration(seconds: 20)),
      ),
      isFalse,
    );
  });

  test('URL content or order changes restart the wait', () {
    final tracker = RenderedImageStability();
    tracker.observe(sample(), start);
    expect(
      tracker.observe(
        sample(signature: 'different-order'),
        start.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        sample(signature: 'different-order'),
        start.add(const Duration(seconds: 4)),
      ),
      isTrue,
    );
  });

  test('count changes restart the wait', () {
    final tracker = RenderedImageStability();
    tracker.observe(sample(), start);
    expect(
      tracker.observe(
        sample(count: 153, valid: 153),
        start.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('page changes restart the wait', () {
    final tracker = RenderedImageStability();
    tracker.observe(sample(), start);
    expect(
      tracker.observe(
        sample(url: 'https://example.com/chapter/2'),
        start.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('zero candidates and loading DOM are not ready', () {
    expect(sample(count: 0, valid: 0).usable, isFalse);
    expect(sample(ready: 'loading').usable, isFalse);
  });

  test('reset requires a new stable interval', () {
    final tracker = RenderedImageStability();
    tracker.observe(sample(), start);
    tracker.reset();
    expect(
      tracker.observe(sample(), start.add(const Duration(seconds: 4))),
      isFalse,
    );
  });

  test('HTML size is not part of the image stability key', () {
    Map<String, dynamic> response(int size) => {
      'url': 'https://example.com/chapter/1',
      'ready': 'complete',
      'count': 152,
      'validCount': 152,
      'signature': 'same-images',
      'size': size,
    };

    final tracker = RenderedImageStability();
    tracker.observe(
      RenderedImageReadinessSample.decode(response(100000)),
      start,
    );
    expect(
      tracker.observe(
        RenderedImageReadinessSample.decode(response(130000)),
        start.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
  });

  test('invalid response counts are rejected', () {
    expect(
      () => RenderedImageReadinessSample.decode({
        'url': 'https://example.com/',
        'ready': 'complete',
        'count': 1,
        'validCount': 2,
        'signature': 'test',
      }),
      throwsFormatException,
    );
  });

  test('script retains the configured attribute and validates rules', () {
    final script = renderedImageReadinessScript(
      selector: '#reader img',
      attribute: 'data-src',
    );
    expect(script, contains('data-src'));
    expect(script, contains('getAttribute(attribute)'));
    expect(script, isNot(contains('outerHTML')));
    expect(
      () => renderedImageReadinessScript(
        selector: '#reader img',
        attribute: 'srcset',
      ),
      throwsFormatException,
    );
  });
}
