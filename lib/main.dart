import 'reader_page.dart';
import 'reading_progress.dart';
export 'reader_page.dart' show ReaderPage, ReadingMode;
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'catalog_page.dart';

const episodeId = 'peppercarrot-en-ep01';
const episodeTitle = 'Pepper&Carrot 第1話（英語版）';

final episodeUrl = Uri.parse(
  'https://www.peppercarrot.com/en/webcomic/'
  'ep01_Potion-of-Flight.html',
);

const attribution = '''
Pepper&Carrot by David Revoy
https://www.peppercarrot.com
CC BY 4.0
https://creativecommons.org/licenses/by/4.0/

Based on the universe of Hereva created by David Revoy
with contributions by Craig Maloney.
Corrections by Willem Sonke, Moini, Hali, CGand and Alex Gryson.

画像は取得したデータを変更せず保存します。
本アプリは非公式の閲覧サンプルです。
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, 'comics', episodeId));
  await directory.create(recursive: true);

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
          surface: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        dividerColor: Colors.white24,
      ),
      home: CatalogPage(root: directory.parent),
    ),
  );
}

class EpisodeStore {
  EpisodeStore(this.directory, {String? id, Uri? url, String? title})
    : episodeId = id ?? 'peppercarrot-en-ep01',
      episodeUrl =
          url ??
          Uri.parse(
            'https://www.peppercarrot.com/en/webcomic/'
            'ep01_Potion-of-Flight.html',
          ),
      episodeTitle = title ?? 'Pepper&Carrot 第1話（英語版）';

  final String episodeId;
  final Uri episodeUrl;
  final String episodeTitle;

  final Directory directory;

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  File get manifest => File(p.join(directory.path, 'manifest.json'));

  // ネットワークを使わず、保存済みの話を復元する。
  Future<List<File>> load() async {
    if (!await manifest.exists()) return [];

    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;

    if (data['episodeId'] != episodeId || data['complete'] != true) {
      throw const FormatException('保存情報が不正です');
    }

    final names = List<String>.from(data['pages'] as List);
    if (names.isEmpty) {
      throw const FormatException('ページがありません');
    }

    final files = <File>[];

    for (final name in names) {
      // JSON内のパスをそのまま信用しない。
      if (!RegExp(r'^\d{4}\.jpg$').hasMatch(name)) {
        throw const FormatException('ファイル名が不正です');
      }

      final file = File(p.join(directory.path, name));
      if (!await file.exists() || await file.length() == 0) {
        throw const FormatException('保存画像が不足しています');
      }
      files.add(file);
    }

    return files;
  }

  Future<List<File>> download(
    void Function(int done, int total) onProgress,
  ) async {
    // 完了済みなら再取得しない。
    try {
      final saved = await load();
      if (saved.isNotEmpty) return saved;
    } catch (_) {
      // 破損・不足時は全体を再ダウンロードする。
    }

    if (await manifest.exists()) {
      await manifest.delete();
    }

    final response = await dio.get<String>(
      episodeUrl.toString(),
      options: Options(responseType: ResponseType.plain),
    );

    final document = html.parse(response.data ?? '');
    final urls = <Uri>[];
    final seen = <String>{};

    for (final image in document.querySelectorAll(
      '.webcomic-page img, #panel-all img.mft-cv-image',
    )) {
      final src = image.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final url = episodeUrl.resolve(src);

      // 初期版は確認した公式ホスト・JPEGだけに限定。
      if (url.scheme != 'https' ||
          url.host != episodeUrl.host ||
          !RegExp(
            r'\.(?:jpe?g|png|webp|gif)$',
            caseSensitive: false,
          ).hasMatch(url.path)) {
        throw const FormatException('未対応の画像URLです');
      }

      if (seen.add(url.toString())) {
        urls.add(url);
      }
    }

    if (urls.isEmpty) {
      throw StateError('漫画画像が見つかりません。取得ルールを確認してください。');
    }

    final names = <String>[];
    onProgress(0, urls.length);

    // サーバーへの負荷を抑えるため、まずは直列で取得。
    for (var i = 0; i < urls.length; i++) {
      final name = '${i.toString().padLeft(4, '0')}.jpg';
      final target = File(p.join(directory.path, name));
      final temporary = File('${target.path}.part');

      await dio.download(
        urls[i].toString(),
        temporary.path,
        deleteOnError: true,
      );

      // HTMLのエラーページなどを画像として保存しないよう、
      // 実際にデコードできることを確認。
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

      names.add(name);
      onProgress(i + 1, urls.length);
    }

    final data = {
      'version': 1,
      'episodeId': episodeId,
      'title': episodeTitle,
      'sourceUrl': episodeUrl.toString(),
      'attribution': attribution,
      'complete': true,
      'pages': names,
    };

    final temporaryManifest = File('${manifest.path}.part');

    await temporaryManifest.writeAsString(jsonEncode(data), flush: true);
    await temporaryManifest.rename(manifest.path);

    return load();
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});

  final EpisodeStore store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<File> files = [];
  bool busy = true;
  String status = '保存状態を確認中…';

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final saved = await widget.store.load();
      if (!mounted) return;

      setState(() {
        files = saved;
        status = saved.isEmpty ? '未保存' : '${saved.length}ページ保存済み・オフライン閲覧可能';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        files = [];
        status = '保存データが不完全です。再保存してください。';
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> download() async {
    setState(() {
      busy = true;
      status = '画像一覧を取得中…';
    });

    try {
      // 削除後や保存先がない場合にも対応。
      await widget.store.directory.create(recursive: true);

      final saved = await widget.store.download((done, total) {
        if (!mounted) return;

        setState(() {
          status = '保存中：$done / $total ページ';
        });
      });

      if (!mounted) return;

      setState(() {
        files = saved;
        status = '${saved.length}ページ保存済み・オフライン閲覧可能';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        status = '保存に失敗しました。再試行できます。\n$error';
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> deleteSaved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('保存データを削除'),
          content: const Text(
            'この話の保存画像を削除します。\n'
            '再びオフラインで読むには、ダウンロードが必要です。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                '削除する',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      busy = true;
      status = '保存データを削除中…';
    });

    try {
      // 現在の話専用フォルダだけを削除する。
      // 未完了ダウンロードの一時ファイルも対象。
      final directory = widget.store.directory;

      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }

      await directory.create(recursive: true);

      if (!mounted) return;

      setState(() {
        files = [];
        status = '保存データを削除しました。再ダウンロードできます。';
      });
    } catch (error) {
      if (!mounted) return;

      // 部分的に削除された可能性があるため、
      // この画面から保存画像を開かないようにする。
      setState(() {
        files = [];
        status = '削除を完了できませんでした。\n$error';
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('オフライン漫画リーダー')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.store.episodeTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                files.isEmpty
                    ? Icons.cloud_download_outlined
                    : Icons.offline_pin,
                color: files.isEmpty ? Colors.white70 : Colors.tealAccent,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(status)),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy || files.isNotEmpty ? null : download,
            icon: const Icon(Icons.download),
            label: const Text('この話を保存'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy || files.isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReaderPage(
                          files: files,
                          title: widget.store.episodeTitle,
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.menu_book),
            label: const Text('保存した話を読む'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : deleteSaved,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            label: const Text(
              '保存データを削除',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '削除対象はこの話の保存データのみです。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const Divider(height: 40),
          const SelectableText(
            attribution,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
