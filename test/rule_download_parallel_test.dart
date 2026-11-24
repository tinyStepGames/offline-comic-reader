import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/services/rule_downloads.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';

class _ParallelNetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ParallelNetworkBinding();

  test('4画像を並列取得し、保存完了後は取り直さない', () async {
    final root = await Directory.systemTemp.createTemp('custom-parallel-');
    final store = DownloadStore(root, maxConcurrentImages: 4);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    addTearDown(() async {
      store.close();
      await server.close(force: true);
      await root.delete(recursive: true);
    });

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);

    late List<int> png;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      png = data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }

    final firstFour = Completer<void>();
    var active = 0;
    var maximum = 0;
    var hits = 0;

    server.listen((request) async {
      active++;
      hits++;
      if (active > maximum) maximum = active;
      if (active >= 4 && !firstFour.isCompleted) {
        firstFour.complete();
      }

      try {
        await firstFour.future.timeout(const Duration(seconds: 5));
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
        await request.response.close();
      } catch (_) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      } finally {
        active--;
      }
    });

    final chapter = ruleSavedChapter(
      siteId: 'AAAAAAAAAAAAAAAAAAAAAA',
      workUrl: 'https://example.com/work/',
      chapterUrl: 'https://example.com/chapter/1/',
      title: '並列テスト',
    );

    // 保存エンジンのローカル実通信テスト。
    // 実サイトの本文抽出は引き続きHTTPS限定。
    final content = ChapterContent(
      images: List.generate(
        8,
        (index) => Uri.parse('http://127.0.0.1:${server.port}/$index'),
      ),
      credits: 'Local test',
    );

    await store.download(chapter, content, (_, _) {});

    expect(maximum, 4);
    expect(hits, 8);
    expect(await store.load(chapter), hasLength(8));

    await store.download(chapter, content, (_, _) {});

    expect(hits, 8);
    expect(await store.incompleteDownloads(chapter.sourceId), isEmpty);
  });
}
