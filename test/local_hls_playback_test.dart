import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:offline_comic_reader/services/local_hls_playback.dart';

const playlist = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-TARGETDURATION:14
#EXTINF:13.013011,
s00000.ts
#EXT-X-DISCONTINUITY
#EXTINF:8.508511,
s00001.ts
#EXT-X-ENDLIST
''';

void main() {
  final directory = Directory(
    p.join(Directory.systemTemp.path, 'offline hls playback test'),
  );
  const segments = {'s00000.ts', 's00001.ts'};

  String convert(String text) => localHlsPlaybackPlaylist(
    playlist: text,
    directory: directory,
    segments: segments,
  );

  test('uses explicit local paths rather than relative segment names', () {
    final result = convert(playlist);
    final paths = result
        .split('\n')
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();

    expect(paths, [
      'file:${p.join(directory.absolute.path, 's00000.ts').replaceAll(r'\', '/')}',
      'file:${p.join(directory.absolute.path, 's00001.ts').replaceAll(r'\', '/')}',
    ]);
    expect(result, isNot(contains('http:')));
    expect(result, isNot(contains('https:')));
  });

  test('preserves timing discontinuity and end markers', () {
    final result = convert(playlist);
    expect(result, contains('#EXTINF:13.013011,'));
    expect(result, contains('#EXTINF:8.508511,'));
    expect(result, contains('#EXT-X-DISCONTINUITY'));
    expect(result, contains('#EXT-X-ENDLIST'));
  });

  test('original playlist remains unchanged', () {
    convert(playlist);
    expect(playlist, contains('\ns00000.ts\n'));
    expect(playlist, isNot(contains('file:')));
  });

  test('rejects network parent and arbitrary file references', () {
    for (final reference in [
      '../s00000.ts',
      'https://example.com/segment.ts',
      'file:C:/other.ts',
      's00000.ts?x=1',
      r'folder\s00000.ts',
    ]) {
      expect(
        () => convert(playlist.replaceFirst('s00000.ts', reference)),
        throwsFormatException,
      );
    }
  });

  test('rejects missing segment metadata', () {
    expect(
      () => localHlsPlaybackPlaylist(
        playlist: playlist,
        directory: directory,
        segments: {'s00000.ts'},
      ),
      throwsFormatException,
    );
  });

  test('rejects ambiguous directory characters', () {
    expect(
      () => localHlsPlaybackPlaylist(
        playlist: playlist,
        directory: Directory('${directory.path}#ambiguous'),
        segments: segments,
      ),
      throwsFormatException,
    );
  });
}
