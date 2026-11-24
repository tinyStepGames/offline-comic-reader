import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/download_store.dart';
import 'package:offline_comic_reader/sources/source_adapter.dart';
import 'package:path/path.dart' as p;

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _NetworkTestBinding();

  late Directory root;
  late DownloadStore store;
  late HttpServer server;
  late List<int> png;
  late List<int> hits;
  late bool failLast;

  final chapter = ComicChapter(
    sourceId: 'sample',
    language: 'ja',
    workId: 'work',
    id: 'chapter1',
    title: 'テストの話',
    url: Uri(scheme: 'https', host: 'example.com', path: '/chapter1'),
    storageId: 'sample-ja-work-chapter1',
    progressSourceId: 'sample',
    progressChapterId: 'chapter1',
  );

  ChapterContent content() => ChapterContent(
    images: List.generate(
      3,
      (index) => Uri.parse('http://127.0.0.1:${server.port}/$index'),
    ),
    credits: 'Test credits',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comic-resume-');
    store = DownloadStore(root, maxConcurrentImages: 1);
    hits = [0, 0, 0];
    failLast = true;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      png = data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final index = int.parse(request.uri.pathSegments.single);
      hits[index]++;

      if (failLast && index == 2) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      }

      await request.response.close();
    });
  });

  tearDown(() async {
    store.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test('失敗後は取得済みページを再利用し、再起動後も再開できる', () async {
    await expectLater(
      store.download(chapter, content(), (_, _) {}),
      throwsA(anything),
    );

    expect(await store.load(chapter), isEmpty);
    final incomplete = await store.incompleteDownloads('sample');
    expect(incomplete, hasLength(1));
    expect(incomplete.single.savedPages, 2);
    expect(incomplete.single.bytes, greaterThan(0));
    expect(await store.incompleteDownloads('other-site'), isEmpty);

    store.close();
    store = DownloadStore(root, maxConcurrentImages: 1);
    failLast = false;

    final progress = <int>[];
    await store.download(
      chapter,
      content(),
      (done, total) => progress.add(done),
    );

    expect(progress.first, 2);
    expect(progress.last, 3);
    expect(hits, [1, 1, 2]);
    expect(await store.load(chapter), hasLength(3));
    expect(await store.incompleteDownloads('sample'), isEmpty);
  });

  test('取得済み画像が破損していた場合は、そのページを取り直す', () async {
    await expectLater(
      store.download(chapter, content(), (_, _) {}),
      throwsA(anything),
    );

    await File(
      p.join(store.directory(chapter).path, '0000.jpg'),
    ).writeAsString('broken');

    failLast = false;
    await store.download(chapter, content(), (_, _) {});

    expect(hits, [2, 1, 2]);
    expect(await store.load(chapter), hasLength(3));
  });

  test('未完了フォルダだけ削除し、別のユーザーデータを残す', () async {
    final sentinel = File(p.join(root.path, '_library', 'keep.txt'));
    await sentinel.parent.create(recursive: true);
    await sentinel.writeAsString('keep');

    await expectLater(
      store.download(chapter, content(), (_, _) {}),
      throwsA(anything),
    );

    final item = (await store.incompleteDownloads('sample')).single;
    await store.deleteIncomplete(item, 'sample');

    expect(await store.directory(chapter).exists(), isFalse);
    expect(await sentinel.readAsString(), 'keep');
  });
}
