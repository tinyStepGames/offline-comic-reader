import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'list_extraction_rule.dart';

class SavedSiteRule {
  const SavedSiteRule({
    required this.id,
    required this.name,
    required this.rules,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final Map<String, ListExtractionRule> rules;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'rules': rules.map((key, rule) => MapEntry(key, rule.toJson())),
  };

  factory SavedSiteRule.fromJson(Map<String, dynamic> data) {
    if (data.keys.any(
      (key) => !const {'id', 'name', 'updatedAt', 'rules'}.contains(key),
    )) {
      throw const FormatException('未対応のサイト保存項目です');
    }

    final id = data['id'] as String;
    final name = checkedSiteRuleName(data['name'] as String);
    final updatedAt = DateTime.parse(data['updatedAt'] as String);
    final raw = Map<String, dynamic>.from(data['rules'] as Map);

    if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id) ||
        raw.isEmpty ||
        raw.keys.any((key) => !const ['works', 'chapters'].contains(key))) {
      throw const FormatException('サイト保存情報が不正です');
    }

    final rules = <String, ListExtractionRule>{};
    for (final entry in raw.entries) {
      final rule = ListExtractionRule.parse(jsonEncode(entry.value));
      if (rule.kind != entry.key) {
        throw const FormatException('一覧の保存先と種類が一致しません');
      }
      rules[entry.key] = rule;
    }

    return SavedSiteRule(
      id: id,
      name: name,
      rules: Map.unmodifiable(rules),
      updatedAt: updatedAt.toUtc(),
    );
  }
}

String checkedSiteRuleName(String value) {
  final name = value.trim();
  if (name.isEmpty || name.length > 100) {
    throw const FormatException('サイト保存名は1～100文字で入力してください');
  }
  return name;
}

/// 漫画保存フォルダーの隣に、名前付きの設定だけを保存する。
/// HTML、画像、Cookieは保存しない。
class SiteRuleStore {
  SiteRuleStore(Directory comicsRoot)
    : _file = File(p.join(comicsRoot.parent.path, '_site_rules', 'sites.json'));

  final File _file;
  static final Map<String, Future<void>> _queues = {};
  static const _maxBytes = 4 * 1024 * 1024;
  static const _maxSites = 200;

  Future<T> _locked<T>(Future<T> Function() action) {
    final key = p.normalize(_file.absolute.path);
    final previous = _queues[key] ?? Future<void>.value();
    final task = previous.then((_) => action());

    // 次の操作が、直前の失敗によって実行されなくなるのを防ぐ。
    _queues[key] = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return task;
  }

  Future<List<SavedSiteRule>> _read() async {
    if (!await _file.exists()) return [];
    if (await _file.length() > _maxBytes) {
      throw const FormatException('サイトルール保存ファイルが大きすぎます');
    }

    // 破損を空データ扱いにしない。上書きせずエラーを返す。
    final data = Map<String, dynamic>.from(
      jsonDecode(await _file.readAsString()) as Map,
    );

    if (data['version'] != 1 ||
        data.keys.any((key) => !const {'version', 'sites'}.contains(key)) ||
        data['sites'] is! List) {
      throw const FormatException('サイトルール保存形式が不正です');
    }

    final raw = data['sites'] as List;
    if (raw.length > _maxSites) {
      throw const FormatException('保存サイト数が上限を超えています');
    }

    final result = raw
        .map(
          (value) =>
              SavedSiteRule.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();

    if (result.map((site) => site.id).toSet().length != result.length) {
      throw const FormatException('保存サイトIDが重複しています');
    }

    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> _write(List<SavedSiteRule> sites) async {
    if (sites.length > _maxSites) {
      throw const FormatException('保存できるサイトは200件までです');
    }

    final text = jsonEncode({
      'version': 1,
      'sites': sites.map((site) => site.toJson()).toList(),
    });

    if (utf8.encode(text).length > _maxBytes) {
      throw const FormatException('サイトルールの保存容量上限を超えています');
    }

    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.part');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(_file.path);
  }

  String _newId(List<SavedSiteRule> sites) {
    final random = Random.secure();
    String id;
    do {
      id = base64Url
          .encode(List<int>.generate(16, (_) => random.nextInt(256)))
          .replaceAll('=', '');
    } while (sites.any((site) => site.id == id));
    return id;
  }

  int _requiredIndex(List<SavedSiteRule> sites, String id) {
    final index = sites.indexWhere((site) => site.id == id);
    if (index < 0) {
      throw StateError('保存先が見つかりません。管理画面を開き直してください');
    }
    return index;
  }

  Future<List<SavedSiteRule>> load() => _locked(_read);

  Future<SavedSiteRule> save({
    String? id,
    required String name,
    required ListExtractionRule rule,
  }) => _locked(() async {
    final checkedName = checkedSiteRuleName(name);
    final checkedRule = ListExtractionRule.parse(rule.encodeJson());
    final sites = await _read();
    final index = id == null ? -1 : _requiredIndex(sites, id);
    final rules = <String, ListExtractionRule>{};

    if (index >= 0) rules.addAll(sites[index].rules);
    rules[checkedRule.kind] = checkedRule;

    final saved = SavedSiteRule(
      id: id ?? _newId(sites),
      name: checkedName,
      rules: Map.unmodifiable(rules),
      updatedAt: DateTime.now().toUtc(),
    );

    if (index < 0) {
      sites.add(saved);
    } else {
      sites[index] = saved;
    }

    await _write(sites);
    return saved;
  });

  Future<void> rename(String id, String name) => _locked(() async {
    final checkedName = checkedSiteRuleName(name);
    final sites = await _read();
    final index = _requiredIndex(sites, id);
    final old = sites[index];

    sites[index] = SavedSiteRule(
      id: old.id,
      name: checkedName,
      rules: old.rules,
      updatedAt: DateTime.now().toUtc(),
    );
    await _write(sites);
  });

  Future<SavedSiteRule> duplicate(String id) => _locked(() async {
    final sites = await _read();
    final old = sites[_requiredIndex(sites, id)];
    final base = old.name.length > 96 ? old.name.substring(0, 96) : old.name;

    final copy = SavedSiteRule.fromJson({
      ...old.toJson(),
      'id': _newId(sites),
      'name': '$base（複製）',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    sites.add(copy);
    await _write(sites);
    return copy;
  });

  Future<void> delete(String id) => _locked(() async {
    final sites = await _read();
    final index = _requiredIndex(sites, id);
    sites.removeAt(index);
    await _write(sites);
  });
}
