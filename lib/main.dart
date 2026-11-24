import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'catalog_page.dart';
import 'services/download_store.dart';
import 'sources/peppercarrot_adapter.dart';

export 'reader_page.dart' show ReaderPage, ReadingMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'comics'));
  await root.create(recursive: true);

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
      home: SourceHome(
        adapter: PepperCarrotAdapter(),
        store: DownloadStore(root),
      ),
    ),
  );
}
