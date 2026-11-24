import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../lib/services/hls_download_plan.dart';
import '../lib/services/video_download_engine.dart';

const master = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
https://cdn.example.com/high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low.m3u8
''';

const media = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:9.5,
segment.tar?r_file=one.ts&r_range=100-475
#EXT-X-DISCONTINUITY
#EXTINF:8.0,
two.ts?token=abc
#EXT-X-ENDLIST
''';

List<int> tsBytes() {
  final bytes = List<int>.filled(376, 0);
  bytes[0] = 0x47;
  bytes[188] = 0x47;
  return bytes;
}

List<int> mp4Bytes() => [
  0,
  0,
  0,
  16,
  ...ascii.encode('ftyp'),
  ...ascii.encode('isom'),
  0,
  0,
  0,
  0,
];

Response<ResponseBody> response(
  Uri url,
  List<int> bytes, {
  int status = 200,
  Map<String, List<String>> extraHeaders = const {},
}) {
  final headers = {
    'content-length': ['${bytes.length}'],
    ...extraHeaders,
  };

  return Response<ResponseBody>(
    requestOptions: RequestOptions(path: url.toString()),
    statusCode: status,
    headers: Headers.fromMap(headers),
    data: ResponseBody.fromBytes(bytes, status, headers: headers),
  );
}

void main() {
  test('master offers quality choices without hardcoded URLs', () {
    final choices = parseHlsChoices(
      Uri.parse('https://video.example.com/master.m3u8'),
      master,
    );

    expect(choices, hasLength(2));
    expect(choices.first.label, contains('1280x720'));
    expect(choices.last.url.toString(), 'https://video.example.com/low.m3u8');
  });

  test('separate audio is rejected rather than silently omitted', () {
    expect(
      () => parseHlsChoices(
        Uri.parse('https://video.example.com/master.m3u8'),
        '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="audio"
video.m3u8
''',
      ),
      throwsFormatException,
    );
  });

  test('HLS query-based segments are preserved and rewritten locally', () {
    final plan = parseHlsMedia(
      Uri.parse('https://cdn.example.com/dir/list.m3u8'),
      media,
    );

    expect(plan.segments, hasLength(2));
    expect(plan.segments.first.url.queryParameters['r_range'], '100-475');

    final local = plan.localPlaylist();
    expect(local, isNot(contains('https://')));
    expect(local, isNot(contains('?token=')));
    expect(local, contains('#EXT-X-DISCONTINUITY'));

    validateLocalHls(local, {'s00000.ts', 's00001.ts'});
  });

  test('encrypted live ranged and init-map HLS are rejected', () {
    final base = Uri.parse('https://cdn.example.com/list.m3u8');

    for (final text in [
      media.replaceFirst(
        '#EXT-X-VERSION:3',
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"',
      ),
      media.replaceFirst('#EXT-X-ENDLIST', ''),
      media.replaceFirst(
        '#EXTINF:9.5,',
        '#EXT-X-BYTERANGE:376@0\n#EXTINF:9.5,',
      ),
      media.replaceFirst(
        '#EXTINF:9.5,',
        '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:9.5,',
      ),
    ]) {
      expect(() => parseHlsMedia(base, text), throwsFormatException);
    }
  });

  test('local playlist cannot reference network or parent paths', () {
    final plan = parseHlsMedia(
      Uri.parse('https://cdn.example.com/list.m3u8'),
      media,
    );
    final local = plan.localPlaylist();

    for (final reference in [
      'https://evil.example.com/remote.ts',
      '../s00000.ts',
      'file:///C:/other.ts',
      's00000.ts?remote=1',
    ]) {
      expect(
        () => validateLocalHls(local.replaceFirst('s00000.ts', reference), {
          's00000.ts',
          's00001.ts',
        }),
        throwsFormatException,
      );
    }
  });

  test('identity keeps site work and chapter isolation', () {
    expect(
      VideoDownloadRepository.idFor('site-a/work/episode-1'),
      isNot(VideoDownloadRepository.idFor('site-b/work/episode-1')),
    );
    expect(
      VideoDownloadRepository.idFor('site-a/work/episode-1'),
      isNot(VideoDownloadRepository.idFor('site-a/work/episode-2')),
    );
  });

  test('redirect destination requires approval before contact', () async {
    final calls = <String>[];
    final http = VideoDownloadHttp(
      allowedOrigins: ['https://video.example.com'],
      approveOrigin: (_) async => false,
      transport: (url, token) async {
        calls.add(url.origin);
        return response(
          url,
          const [],
          status: 302,
          extraHeaders: {
            'location': ['https://other.example.com/video.mp4'],
          },
        );
      },
    );
    addTearDown(http.close);

    await expectLater(
      http.inspect(Uri.parse('https://video.example.com/start'), CancelToken()),
      throwsStateError,
    );
    expect(calls, ['https://video.example.com']);
  });

  test('insecure redirect is rejected', () async {
    final http = VideoDownloadHttp(
      allowedOrigins: ['https://video.example.com'],
      approveOrigin: (_) async => true,
      transport: (url, token) async => response(
        url,
        const [],
        status: 302,
        extraHeaders: {
          'location': ['http://other.example.com/video.mp4'],
        },
      ),
    );
    addTearDown(http.close);

    await expectLater(
      http.inspect(Uri.parse('https://video.example.com/start'), CancelToken()),
      throwsFormatException,
    );
  });

  test('HLS saves complete local package and detects corruption', () async {
    final root = await Directory.systemTemp.createTemp('video-hls-test-');
    final requests = <String>[];
    final approvals = <String>[];

    final http = VideoDownloadHttp(
      allowedOrigins: ['https://video.example.com'],
      approveOrigin: (origin) async {
        approvals.add(origin);
        return true;
      },
      transport: (url, token) async {
        requests.add(url.toString());
        if (url.path == '/master.m3u8') {
          return response(url, utf8.encode(master));
        }
        if (url.path == '/high.m3u8') {
          return response(url, utf8.encode(media));
        }
        return response(url, tsBytes(), status: 206);
      },
    );

    try {
      final repository = VideoDownloadRepository(root);
      final engine = VideoDownloadEngine(repository);
      final token = CancelToken();

      final inspection = await http.inspect(
        Uri.parse('https://video.example.com/master.m3u8'),
        token,
      );

      final saved = await engine.save(
        identity: 'site-a/work/episode-1',
        title: 'Episode 1',
        metadata: {'kind': 'test'},
        http: http,
        inspection: inspection,
        choice: inspection.choices.first,
        cancelToken: token,
        onProgress: (_, _, _) {},
      );

      expect(approvals, ['https://cdn.example.com']);
      expect(requests.any((url) => url.contains('r_range=100-475')), isTrue);
      expect(saved.entry, 'main.m3u8');
      expect(saved.files, hasLength(3));
      expect((await repository.scan()).videos, hasLength(1));

      // 動画ルート直下には画像保存用manifest.jsonを置かない。
      expect(
        await File(p.join(repository.root.path, 'manifest.json')).exists(),
        isFalse,
      );

      final segment = File(
        p.join(repository.directory(saved.id).path, 's00000.ts'),
      );
      final altered = tsBytes();
      altered[20] = 123;
      await segment.writeAsBytes(altered, flush: true);

      await expectLater(
        repository.load(saved.id, verifyHashes: true),
        throwsFormatException,
      );
    } finally {
      http.close();
      await root.delete(recursive: true);
    }
  });

  test('MP4 saves and deletion affects only its video package', () async {
    final root = await Directory.systemTemp.createTemp('video-mp4-test-');
    final unrelated = File(p.join(root.path, 'keep.txt'));
    await unrelated.writeAsString('keep');

    final http = VideoDownloadHttp(
      allowedOrigins: ['https://video.example.com'],
      approveOrigin: (_) async => false,
      transport: (url, token) async => response(url, mp4Bytes()),
    );

    try {
      final repository = VideoDownloadRepository(root);
      final engine = VideoDownloadEngine(repository);
      final token = CancelToken();
      final inspection = await http.inspect(
        Uri.parse('https://video.example.com/video.mp4'),
        token,
      );

      expect(inspection.isMp4, isTrue);

      final saved = await engine.save(
        identity: 'site-a/work/mp4',
        title: 'MP4',
        metadata: const {},
        http: http,
        inspection: inspection,
        choice: inspection.choices.single,
        cancelToken: token,
        onProgress: (_, _, _) {},
      );

      expect(saved.entry, 'video.mp4');
      expect(await repository.load(saved.id, verifyHashes: true), isNotNull);

      await repository.delete(saved.id);
      expect((await repository.scan()).videos, isEmpty);
      expect(await unrelated.readAsString(), 'keep');
    } finally {
      http.close();
      await root.delete(recursive: true);
    }
  });

  test('cancel leaves no completed or temporary video package', () async {
    final root = await Directory.systemTemp.createTemp('video-cancel-test-');
    final http = VideoDownloadHttp(
      allowedOrigins: ['https://cdn.example.com'],
      approveOrigin: (_) async => false,
      transport: (url, token) async => response(url, tsBytes()),
    );

    try {
      final repository = VideoDownloadRepository(root);
      final engine = VideoDownloadEngine(repository);
      final token = CancelToken();
      final inspection = VideoInspection(
        url: Uri.parse('https://cdn.example.com/list.m3u8'),
        isMp4: false,
        playlist: media,
      );

      await expectLater(
        engine.save(
          identity: 'cancel-test',
          title: 'Cancel',
          metadata: const {},
          http: http,
          inspection: inspection,
          choice: inspection.choices.single,
          cancelToken: token,
          onProgress: (_, _, _) {
            token.cancel('test cancel');
          },
        ),
        throwsStateError,
      );

      expect(engine.busy, isFalse);
      expect((await repository.scan()).videos, isEmpty);
      expect(await repository.root.list().toList(), isEmpty);
    } finally {
      http.close();
      await root.delete(recursive: true);
    }
  });

  test('HTML or truncated media is never marked completed', () async {
    final root = await Directory.systemTemp.createTemp('video-invalid-test-');
    final http = VideoDownloadHttp(
      allowedOrigins: ['https://video.example.com'],
      approveOrigin: (_) async => false,
      transport: (url, token) async =>
          response(url, utf8.encode('<html>Access denied</html>')),
    );

    try {
      final repository = VideoDownloadRepository(root);
      final engine = VideoDownloadEngine(repository);
      final inspection = VideoInspection(
        url: Uri.parse('https://video.example.com/video.mp4'),
        isMp4: true,
      );

      await expectLater(
        engine.save(
          identity: 'invalid-test',
          title: 'Invalid',
          metadata: const {},
          http: http,
          inspection: inspection,
          choice: inspection.choices.single,
          cancelToken: CancelToken(),
          onProgress: (_, _, _) {},
        ),
        throwsFormatException,
      );

      expect((await repository.scan()).videos, isEmpty);
      expect(engine.busy, isFalse);
    } finally {
      http.close();
      await root.delete(recursive: true);
    }
  });

  test('path traversal is rejected by repository API', () async {
    final root = await Directory.systemTemp.createTemp('video-path-test-');

    try {
      final repository = VideoDownloadRepository(root);
      expect(() => repository.directory('../outside'), throwsFormatException);
      await expectLater(repository.delete('../outside'), throwsFormatException);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
