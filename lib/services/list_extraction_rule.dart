import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'html_probe.dart';

enum ListValueMode { text, attribute, cssUrl }

const listFieldLabels = <String, String>{
  'title': 'タイトル',
  'url': 'リンク',
  'thumbnail': '表紙',
  'id': 'ID',
  'date': '公開日など',
};

class ListFieldRule {
  const ListFieldRule({
    this.selector = '',
    this.mode = ListValueMode.text,
    this.attribute = '',
    this.enabled = true,
  });

  final String selector;
  final ListValueMode mode;
  final String attribute;
  final bool enabled;

  ListFieldRule copyWith({
    String? selector,
    ListValueMode? mode,
    String? attribute,
    bool? enabled,
  }) => ListFieldRule(
    selector: selector ?? this.selector,
    mode: mode ?? this.mode,
    attribute: attribute ?? this.attribute,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'selector': selector,
    'mode': mode.name,
    'attribute': attribute,
    'enabled': enabled,
  };

  factory ListFieldRule.fromJson(Map<String, dynamic> data) {
    if (data.keys.any(
      (key) =>
          !const {'selector', 'mode', 'attribute', 'enabled'}.contains(key),
    )) {
      throw const FormatException('未対応の項目設定です');
    }

    final mode = ListValueMode.values.where(
      (value) => value.name == data['mode'],
    );

    if (mode.length != 1 || data['enabled'] is! bool) {
      throw const FormatException('取得方法が不正です');
    }

    return ListFieldRule(
      selector: data['selector'] as String,
      mode: mode.single,
      attribute: data['attribute'] as String,
      enabled: data['enabled'] as bool,
    );
  }
}

Map<String, ListFieldRule> defaultListFields() => {
  'title': const ListFieldRule(),
  'url': const ListFieldRule(mode: ListValueMode.attribute, attribute: 'href'),
  'thumbnail': const ListFieldRule(
    mode: ListValueMode.attribute,
    attribute: 'src',
    enabled: false,
  ),
  'id': const ListFieldRule(
    mode: ListValueMode.attribute,
    attribute: 'id',
    enabled: false,
  ),
  'date': const ListFieldRule(enabled: false),
};

class ListExtractionRule {
  ListExtractionRule({
    required this.pageUrl,
    required this.groupSelector,
    required this.fields,
    this.kind = 'works',
    this.acquisition = 'staticHtml',
  });

  static const qrPrefix = 'ocr-list:1:';

  final String pageUrl;
  final String groupSelector;
  final Map<String, ListFieldRule> fields;
  final String kind;
  final String acquisition;

  void validate() {
    htmlProbeUri(pageUrl);

    if (pageUrl.length > 4096 ||
        groupSelector.length > 2048 ||
        groupSelector.trim().isEmpty) {
      throw const FormatException('まとまりのセレクターが空、または長すぎます');
    }

    if (!const ['works', 'chapters'].contains(kind) ||
        !const ['staticHtml', 'renderedDom'].contains(acquisition)) {
      throw const FormatException('一覧の種類または取得方式が不正です');
    }

    if (fields.length != listFieldLabels.length ||
        fields.keys.any((key) => !listFieldLabels.containsKey(key))) {
      throw const FormatException('項目の構成が不正です');
    }

    for (final key in ['title', 'url']) {
      if (fields[key]?.enabled != true) {
        throw const FormatException('タイトルとリンクは有効にしてください');
      }
    }

    for (final field in fields.values) {
      if (field.selector.length > 2048 || field.attribute.length > 128) {
        throw const FormatException('項目設定が長すぎます');
      }

      if (field.enabled &&
          field.mode != ListValueMode.text &&
          !RegExp(r'^[A-Za-z_:][A-Za-z0-9_:.-]*$').hasMatch(field.attribute)) {
        throw const FormatException('属性名を確認してください');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'format': 'offline-comic-reader.list-extraction',
    'version': 1,
    'pageUrl': pageUrl,
    'kind': kind,
    'acquisition': acquisition,
    'groupSelector': groupSelector,
    'fields': fields.map((key, value) => MapEntry(key, value.toJson())),
  };

  String encodeJson() {
    validate();
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String encodeQr() {
    validate();
    final value =
        '$qrPrefix${base64Url.encode(utf8.encode(jsonEncode(toJson())))}';

    if (value.length > 1500) {
      throw const FormatException('この設定はQRの初版上限を超えています。JSONで共有してください');
    }
    return value;
  }

  static ListExtractionRule parse(String input) {
    var value = input.trim();

    if (utf8.encode(value).length > 65536) {
      throw const FormatException('設定が大きすぎます');
    }

    if (value.startsWith(qrPrefix)) {
      value = utf8.decode(
        base64Url.decode(base64Url.normalize(value.substring(qrPrefix.length))),
      );
    }

    if (utf8.encode(value).length > 65536) {
      throw const FormatException('設定が大きすぎます');
    }

    final data = Map<String, dynamic>.from(jsonDecode(value) as Map);

    if (data['format'] != 'offline-comic-reader.list-extraction' ||
        data['version'] != 1 ||
        data.keys.any(
          (key) => !const {
            'format',
            'version',
            'pageUrl',
            'kind',
            'acquisition',
            'groupSelector',
            'fields',
          }.contains(key),
        )) {
      throw const FormatException('未対応の一覧ルールです');
    }

    final rawFields = Map<String, dynamic>.from(data['fields'] as Map);
    final rule = ListExtractionRule(
      pageUrl: data['pageUrl'] as String,
      groupSelector: data['groupSelector'] as String,
      kind: data['kind'] as String,
      acquisition: data['acquisition'] as String,
      fields: rawFields.map(
        (key, value) => MapEntry(
          key,
          ListFieldRule.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );

    rule.validate();
    return rule;
  }
}

class ExtractedListRow {
  const ExtractedListRow(this.values, this.issues);

  final Map<String, String> values;
  final List<String> issues;
}

class ListExtractionReport {
  const ListExtractionReport(this.total, this.rows);

  final int total;
  final List<ExtractedListRow> rows;
}

/// 通常の url("...") / url('...') / url(...) の最初のURLを取り出す。
/// CSSエスケープや複数背景の完全解析は行わない。
String firstCssUrl(String value) {
  final match = RegExp(
    r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]+))\s*\)''',
    caseSensitive: false,
  ).firstMatch(value);

  return (match?.group(1) ?? match?.group(2) ?? match?.group(3) ?? '').trim();
}

ListExtractionReport extractListRows(
  HtmlProbePage page,
  ListExtractionRule rule,
) {
  rule.validate();

  if (htmlProbeUri(rule.pageUrl) != page.uri.replace(fragment: '')) {
    throw const FormatException('ルールのURLと取得したHTMLのURLが違います');
  }

  final document = html.parse(page.source);
  var baseUri = page.uri;
  final base = document.querySelector('base[href]')?.attributes['href'];

  if (base != null) {
    final candidate = page.uri.resolve(base);
    if (const ['https', 'http'].contains(candidate.scheme)) {
      baseUri = candidate;
    }
  }

  final groups = document.querySelectorAll(rule.groupSelector);
  final rows = <ExtractedListRow>[];

  for (final group in groups.take(100)) {
    final values = <String, String>{};
    final issues = <String>[];

    for (final entry in rule.fields.entries) {
      final key = entry.key;
      final field = entry.value;
      if (!field.enabled) continue;

      try {
        Element? element;

        if (field.selector.trim().isEmpty) {
          element = group;
        } else {
          // まとまりの外側を拾わないよう、候補を内側に限定する。
          final matches = group.querySelectorAll(field.selector);
          element = matches.isEmpty ? null : matches.first;

          if (matches.length > 1) {
            issues.add('${listFieldLabels[key]}：${matches.length}件あるため先頭を使用');
          }
        }

        var value = element == null
            ? ''
            : field.mode == ListValueMode.text
            ? element.text.trim()
            : element.attributes[field.attribute] ?? '';

        if (field.mode == ListValueMode.cssUrl) {
          value = firstCssUrl(value);
        }

        value = value.trim();

        if ((key == 'url' || key == 'thumbnail') && value.isNotEmpty) {
          final uri = baseUri.resolve(value);
          if (!const ['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            throw const FormatException('HTTP/HTTPSのURLではありません');
          }
          value = uri.toString();
        }

        values[key] = value;

        if ((key == 'title' || key == 'url') && value.isEmpty) {
          issues.add('${listFieldLabels[key]}：取得できません');
        }
      } catch (error) {
        values[key] = '';
        issues.add('${listFieldLabels[key]}：$error');
      }
    }

    rows.add(
      ExtractedListRow(Map.unmodifiable(values), List.unmodifiable(issues)),
    );
  }

  return ListExtractionReport(groups.length, List.unmodifiable(rows));
}

String encodeListRuleCache(dynamic data) => jsonEncode(data);
