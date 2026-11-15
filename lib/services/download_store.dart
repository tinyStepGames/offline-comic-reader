import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../sources/source_adapter.dart';

class DownloadStore {
  DownloadStore(this.root, {this.maxConcurrentImages = 3}) {
    if (maxConcurrentImages < 1 || maxConcurrentImages > 4) {
      throw ArgumentError.value(
        maxConcurrentImages,
        'maxConcurrentImages',
        '同時取得数は1～4で指定してください',
      );
    }
  }

  /// 1話の中で同時取得する画像数。
  final int maxConcurrentImages;

  final Directory root;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  Directory directory(ComicChapter chapter) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(chapter.storageId)) {
      throw const FormatException('保存IDが不正です');
    }
    return Directory(p.join(root.path, chapter.storageId));
  }

  File _manifest(ComicChapter chapter) =>
      File(p.join(directory(chapter).path, 'manifest.json'));

  Future<void> _writeJson(File file, Object data) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }

  File _cacheFile(String key) {
    final hash = sha256.convert(utf8.encode(key)).toString();
    return File(p.join(root.path, '_cache', '$hash.json'));
  }

  Future<dynamic> readCache(String key) async {
    try {
      return jsonDecode(await _cacheFile(key).readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCache(String key, Object data) =>
      _writeJson(_cacheFile(key), data);

  Future<List<File>> load(ComicChapter chapter) async {
    final manifest = _manifest(chapter);
    if (!await manifest.exists()) return [];

    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;

    if (data['complete'] != true || data['episodeId'] != chapter.storageId) {
      throw const FormatException('保存情報が不正です');
    }

    final names = List<String>.from(data['pages'] as List);
    if (names.isEmpty) {
      throw const FormatException('保存ページがありません');
    }

    final files = <File>[];
    for (final name in names) {
      if (!RegExp(r'^\d{4,}\.jpg$').hasMatch(name)) {
        throw const FormatException('保存ファイル名が不正です');
      }

      final file = File(p.join(directory(chapter).path, name));
      if (!await file.exists() || await file.length() == 0) {
        throw const FormatException('保存画像が不足しています');
      }
      files.add(file);
    }
    return files;
  }

  Future<List<ComicChapter>> localChapters(SourceAdapter adapter) async {
    final result = <ComicChapter>[];
    await root.create(recursive: true);

    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory || p.basename(entry.path) == '_cache') {
        continue;
      }

      try {
        final data =
            jsonDecode(
                  await File(
                    p.join(entry.path, 'manifest.json'),
                  ).readAsString(),
                )
                as Map<String, dynamic>;

        final chapter = adapter.restoreChapter(data);
        if (chapter != null && p.basename(entry.path) == chapter.storageId) {
          result.add(chapter);
        }
      } catch (_) {
        // 他サイト・未完了・破損した記録は復元しない。
      }
    }
    return result;
  }

  Future<void> rememberCredits(ComicChapter chapter, String credits) async {
    final target = File(p.join(directory(chapter).path, 'credits.txt'));
    await target.parent.create(recursive: true);
    await target.writeAsString(credits, flush: true);
  }

  Future<String?> readCredits(ComicChapter chapter) async {
    try {
      return await File(
        p.join(directory(chapter).path, 'credits.txt'),
      ).readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> download(
    ComicChapter chapter,
    ChapterContent content,
    void Function(int done, int total) progress,
  ) async {
    // 呼び出し元でリストが変更されても影響を受けないように固定する。
    final images = List<Uri>.unmodifiable(content.images);

    if (images.isEmpty) {
      throw const FormatException('保存対象の画像がありません');
    }

    // ファイルに変更を加える前に、全URLの取得方式を確認する。
    for (final url in images) {
      if (!['https', 'http'].contains(url.scheme) || url.host.isEmpty) {
        throw const FormatException('未対応の画像取得方式です');
      }
    }

    final folder = directory(chapter);
    await folder.create(recursive: true);

    final manifest = _manifest(chapter);

    // すべての画像が正常に保存されるまで、完了扱いにしない。
    if (await manifest.exists()) {
      await manifest.delete();
    }

    await rememberCredits(chapter, content.credits);

    // 完了した順ではなく、元のページ順にファイル名を確定する。
    final names = List<String>.generate(
      images.length,
      (index) => '${index.toString().padLeft(4, '0')}.jpg',
      growable: false,
    );

    var nextIndex = 0;
    var completed = 0;
    var stopped = false;

    progress(0, images.length);

    Future<void> saveImage(int index) async {
      final target = File(p.join(folder.path, names[index]));
      final temporary = File('${target.path}.part');

      try {
        await _dio.download(
          images[index].toString(),
          temporary.path,
          deleteOnError: true,
        );

        // 従来どおり、実際に画像として読み込めるか確認する。
        final codec = await ui.instantiateImageCodec(
          await temporary.readAsBytes(),
          targetWidth: 64,
        );

        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }

        if (await target.exists()) {
          await target.delete();
        }

        await temporary.rename(target.path);
      } finally {
        // 失敗した一時ファイルは可能な範囲で片付ける。
        // 片付けの失敗で、本来の通信エラーなどを隠さない。
        try {
          if (await temporary.exists()) {
            await temporary.delete();
          }
        } catch (_) {
          // 次回の取得で同じ一時パスを使用する。
        }
      }
    }

    Future<void> worker() async {
      while (!stopped) {
        // この取得部分にはawaitを挟まず、各ワーカーへ別の番号を渡す。
        final index = nextIndex;
        if (index >= images.length) return;
        nextIndex++;

        try {
          await saveImage(index);

          completed++;
          progress(completed, images.length);
        } catch (_) {
          // 他ワーカーは実行中の画像だけを処理し、
          // それ以降の画像を新しく開始しない。
          stopped = true;
          rethrow;
        }
      }
    }

    final workerCount = images.length < maxConcurrentImages
        ? images.length
        : maxConcurrentImages;

    // eagerError:falseにより、失敗時も実行中のワーカー終了を待つ。
    // リトライと前回の書き込みが重ならないようにする。
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
      eagerError: false,
    );

    // 全ページ成功時だけ完了情報を書き込む。
    await _writeJson(manifest, {
      'version': 2,
      'episodeId': chapter.storageId,
      'title': chapter.title,
      'sourceUrl': chapter.url.toString(),
      'chapter': chapter.toJson(),
      'complete': true,
      'pages': names,
    });
  }

  Future<void> delete(ComicChapter chapter) async {
    final target = directory(chapter);
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
  }

  void close() => _dio.close(force: true);
}
