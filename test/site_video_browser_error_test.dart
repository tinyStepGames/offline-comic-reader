import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/site_video_browser_error.dart';

void main() {
  bool show({
    bool mainFrame = true,
    bool aborted = true,
    bool loaded = false,
    bool blocked = false,
  }) => showSiteVideoBrowserLoadError(
    mainFrame: mainFrame,
    connectionAborted: aborted,
    pageLoaded: loaded,
    explicitlyBlocked: blocked,
  );

  test('initial unexplained main page cancellation is visible', () {
    expect(show(), isTrue);
  });

  test('cancellation after page load is not a foreground error', () {
    expect(show(loaded: true), isFalse);
  });

  test('explicitly blocked navigation cancellation is not an error', () {
    expect(show(blocked: true), isFalse);
  });

  test('other main page errors remain visible after load', () {
    expect(show(aborted: false, loaded: true), isTrue);
  });

  test('blocking does not suppress unrelated error types', () {
    expect(show(aborted: false, blocked: true), isTrue);
  });

  test('subframe errors are not presented as whole page failures', () {
    expect(show(mainFrame: false, aborted: false), isFalse);
  });
}
