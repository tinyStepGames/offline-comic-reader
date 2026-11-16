import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'services/html_probe.dart';
import 'services/selector_check.dart';

class VisualPick {
  const VisualPick({
    required this.page,
    required this.selector,
    required this.mode,
    required this.attribute,
  });

  final HtmlProbePage page;
  final String selector;
  final HtmlValueMode mode;
  final String attribute;
}

/// 外部ページにネイティブ操作のハンドラーを公開しない。
/// アプリから選択結果だけを読み取る。
const _pickerScript = r'''
(() => {
  if (window.__ocrPicker) return;
  let enabled = false;
  let selected = null;
  let sequence = 0;
  let snapshot = null;
  let marked = [];
  let scopeSelector = '';
  let fieldKey = '';

  const scopeGroups = () => scopeSelector
    ? [...document.querySelectorAll(scopeSelector)]
    : [];

  const scopedNodes = selector => {
    if (!scopeSelector) return [...document.querySelectorAll(selector)];
    const result = [];
    for (const group of scopeGroups()) {
      if (!selector) result.push(group);
      else result.push(...group.querySelectorAll(selector));
    }
    return [...new Set(result)];
  };

  const scopeOf = el => {
    if (!scopeSelector) return null;
    for (let node = el; node; node = node.parentElement) {
      if (node.matches(scopeSelector)) return node;
    }
    return null;
  };

  const restore = () => {
    for (const item of marked) {
      item.el.style.outline = item.outline;
      item.el.style.outlineOffset = item.offset;
    }
    marked = [];
  };

  const safeName = value => /^[A-Za-z_][A-Za-z0-9_-]*$/.test(value);

  const quote = value =>
    '"' + value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';

  const simple = el => {
    const tag = el.tagName.toLowerCase();
    const classes = [...el.classList]
      .filter(v => v.length < 50 && safeName(v) && !/\d{5}/.test(v))
      .slice(0, 2);
    return tag + classes.map(v => '.' + v).join('');
  };

  const strong = el => {
    const tag = el.tagName.toLowerCase();

    if (el.id && el.id.length < 120 && !/[\r\n\f]/.test(el.id)) {
      return safeName(el.id)
        ? '#' + el.id
        : tag + '[id=' + quote(el.id) + ']';
    }

    for (const key of [
      'data-testid', 'data-test', 'itemprop', 'name', 'role', 'lang'
    ]) {
      const value = el.getAttribute(key);
      if (value && value.length < 100 && !/[\r\n\f]/.test(value)) {
        return tag + '[' + key + '=' + quote(value) + ']';
      }
    }

    return simple(el);
  };

  const exactSegment = el => {
    const base = strong(el);
    const parent = el.parentElement;
    if (!parent) return base;

    const siblings = [...parent.children];
    const matching = siblings.filter(node => node.matches(base));

    if (matching.length <= 1) return base;

    const index = siblings.indexOf(el);

    // 空白テキストノードに左右されない、要素同士の隣接関係を使う。
    return siblings.slice(0, index + 1)
      .map((node, i) =>
        strong(node) + (i === 0 ? ':first-child' : '')
      )
      .join(' + ');
  };

  const path = (el, root = null) => {
    const parts = [];
    let depth = 0;

    for (
      let node = el;
      node && node !== root && node.nodeType === 1 && depth < 30;
      node = node.parentElement, depth++
    ) {
      parts.unshift(exactSegment(node));
      if (!root && node.id) break;
    }

    return parts.join(' > ');
  };
  const highlight = selector => {
    restore();
    let nodes;
    try { nodes = scopedNodes(selector); }
    catch (_) { return; }

    for (const el of nodes.slice(0, 100)) {
      marked.push({
        el,
        outline: el.style.outline,
        offset: el.style.outlineOffset
      });
      el.style.outline = '3px solid #00c8ff';
      el.style.outlineOffset = '-3px';
    }
  };

  const describe = el => {
    const root = scopeSelector ? scopeOf(el) : null;
    if (scopeSelector && !root) return;

    restore();
    selected = el;
    const candidates = [];
    let proposals;

    if (scopeSelector && el === root) {
      proposals = [''];
    } else {
      proposals = [strong(el), simple(el)];

      if (el.parentElement && el.parentElement !== root) {
        proposals.push(
          strong(el.parentElement) + ' > ' + strong(el)
        );
      }

      let ancestor = el.parentElement;
      for (let depth = 0;
           ancestor && ancestor !== root && depth < 5;
           ancestor = ancestor.parentElement, depth++) {
        if (ancestor.id) {
          proposals.push(strong(ancestor) + ' ' + strong(el));
          break;
        }
      }

      proposals.push(path(el, root));
    }

    proposals = proposals
      .filter(selector => selector.length <= 8192)
      .slice(0, 10);
    for (const selector of [...new Set(proposals)]) {
      try {
        candidates.push({
          selector,
          count: scopedNodes(selector).length
        });
      } catch (_) {}
    }

    const attrs = {};
    for (const key of [
      'id', 'class', 'href', 'src', 'data-src', 'alt', 'title', 'style'
    ]) {
      if (el.hasAttribute(key)) attrs[key] = el.getAttribute(key).slice(0, 2000);
    }

    snapshot = {
      sequence: ++sequence,
      tag: el.tagName.toLowerCase(),
      text: (el.textContent || '').trim().slice(0, 1000),
      html: el.outerHTML.slice(0, 6000),
      attrs,
      candidates
    };

    if (candidates.length) highlight(candidates[0].selector);
  };

  document.addEventListener('click', event => {
    if (!enabled) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.target instanceof Element) describe(event.target);
  }, true);

  window.__ocrPicker = {
    configureScope(selector, key) {
      restore();
      scopeSelector = selector || '';
      fieldKey = key || '';
      selected = null;
      snapshot = null;

      if (scopeSelector) {
        const groups = scopeGroups();
        if (!groups.length) {
          throw new Error('まとまりが見つかりません。URLとセレクターを確認してください');
        }
        highlight('');
        groups[0].scrollIntoView({block: 'center'});
      }
    },
    enable(value) {
      enabled = !!value;
      if (!enabled) restore();
    },
    read() { return snapshot; },
    highlight,
    parent() {
      if (selected && selected.parentElement) describe(selected.parentElement);
    },
    child() {
      if (selected && selected.firstElementChild) describe(selected.firstElementChild);
    },
    capture() {
      restore();
      const source = document.documentElement.outerHTML;
      if (source.length > 2000000) throw new Error('DOMが大きすぎます');
      return JSON.stringify({url: location.href, source});
    }
  };
})();
''';

class ElementInspectorPage extends StatefulWidget {
  const ElementInspectorPage({
    super.key,
    required this.url,
    this.groupSelector = '',
    this.fieldKey = '',
  });

  final String url;
  final String groupSelector;
  final String fieldKey;

  @override
  State<ElementInspectorPage> createState() => _ElementInspectorPageState();
}

class _ElementInspectorPageState extends State<ElementInspectorPage> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  Timer? _timer;
  Uri? _initial;
  bool _prepared = false;
  bool _ready = false;
  bool _selecting = true;
  bool _polling = false;
  bool _capturing = false;
  int _sequence = -1;
  Map<String, dynamic>? _selected;
  String _selector = '';
  String _value = 'text';
  String _status = 'ページ表示を準備中';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      _initial = htmlProbeUri(widget.url);

      if (Platform.isWindows) {
        final version = await WebViewEnvironment.getAvailableVersion();
        if (version == null) {
          throw StateError('Microsoft Edge WebView2 Runtimeが必要です');
        }

        final support = await getApplicationSupportDirectory();
        _environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: p.join(support.path, 'rule-inspector-webview'),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _prepared = true;
          _status = '読み込み中';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = '準備できませんでした：$error');
    }
  }

  Future<dynamic> _eval(String source) async =>
      _controller?.evaluateJavascript(source: source);

  Future<void> _poll() async {
    if (!mounted || !_ready || !_selecting || _polling || _capturing) {
      return;
    }

    _polling = true;
    try {
      final raw = await _eval(
        'JSON.stringify(window.__ocrPicker?.read() ?? null)',
      );

      if (raw is! String || raw.length > 64000 || raw == 'null') return;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);

      if (data['sequence'] is! int ||
          data['sequence'] == _sequence ||
          data['candidates'] is! List ||
          data['attrs'] is! Map) {
        return;
      }

      final candidates = List<Map<String, dynamic>>.from(
        (data['candidates'] as List).map(
          (value) => Map<String, dynamic>.from(value as Map),
        ),
      );

      if (candidates.isEmpty ||
          candidates.length > 10 ||
          candidates.any(
            (value) =>
                value['selector'] is! String ||
                (value['selector'] as String).length > 8192 ||
                value['count'] is! int,
          )) {
        return;
      }

      final attrs = Map<String, dynamic>.from(data['attrs'] as Map);
      if (!mounted) return;

      setState(() {
        _sequence = data['sequence'] as int;
        _selected = data;
        _selector = candidates.first['selector'] as String;
        _value = attrs.containsKey('src')
            ? 'src'
            : attrs.containsKey('href')
            ? 'href'
            : attrs.containsKey('data-src')
            ? 'data-src'
            : 'text';
        if (widget.groupSelector.isNotEmpty) {
          if (widget.fieldKey == 'title' ||
              widget.fieldKey == 'date' ||
              widget.fieldKey == 'latestChapter') {
            _value = 'text';
          } else if (widget.fieldKey == 'url') {
            _value = 'href';
          } else if (widget.fieldKey == 'id') {
            _value = 'id';
          } else if (widget.fieldKey == 'thumbnail') {
            _value = attrs.containsKey('data-src')
                ? 'data-src'
                : attrs.containsKey('src')
                ? 'src'
                : attrs.containsKey('style')
                ? 'style'
                : 'src';
          }
        }
        _status = widget.groupSelector.isEmpty
            ? '選択：${data['tag']}／青枠は同じ条件に一致する要素'
            : '選択：${data['tag']}／まとまりの内側だけを対象にしています';
      });
    } catch (_) {
      // 読み込み途中やページ遷移中は、次回の選択で取り直す。
    } finally {
      _polling = false;
    }
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    final next = !_selecting;

    try {
      await _eval('window.__ocrPicker?.enable($next)');
      if (mounted) {
        setState(() {
          _selecting = next;
          _status = next
              ? '調べたい部分をタップ／クリックしてください'
              : '通常操作モードです。リンク移動・スクロールができます';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = '切り替えできませんでした：$error');
    }
  }

  Future<void> _move(String direction) async {
    if (!_ready) return;
    try {
      await _eval('window.__ocrPicker?.$direction()');
      await _poll();
    } catch (error) {
      if (mounted) setState(() => _status = '選択を変更できませんでした：$error');
    }
  }

  Future<void> _use() async {
    if (!_ready || _capturing || _selected == null) return;
    if (widget.groupSelector.isEmpty && _selector.isEmpty) return;

    if (widget.groupSelector.isNotEmpty && _value == 'innerHtml') {
      setState(() => _status = '一覧の項目には文字列または属性を選んでください');
      return;
    }

    final selectedSelector = _selector;
    final selectedValue = _value;
    final candidates = (_selected!['candidates'] as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();

    setState(() => _capturing = true);

    try {
      final raw = await _eval('window.__ocrPicker.capture()');

      if (raw is! String || raw.length > 2200000) {
        throw const FormatException('表示後DOMを取得できないか、大きすぎます');
      }

      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final uri = htmlProbeUri(data['url'] as String);

      if (uri.origin != _initial!.origin) {
        throw const FormatException('最初のページと異なる接続先です');
      }

      final source = data['source'] as String;
      final bytes = utf8.encode(source).length;

      if (bytes > HtmlProbeClient.maxBytes) {
        throw const FormatException('表示後DOMが上限の2MiBを超えています');
      }

      final mode = selectedValue == 'text'
          ? HtmlValueMode.text
          : selectedValue == 'innerHtml'
          ? HtmlValueMode.innerHtml
          : HtmlValueMode.attribute;

      final selectors = candidates
          .map((candidate) => candidate['selector'] as String)
          .toSet()
          .toList();

      if (!selectors.contains(selectedSelector)) {
        throw const FormatException('選択中のセレクターが候補にありません');
      }

      final results = await checkSelectorCandidates(
        source: source,
        selectors: selectors,
        scope: widget.groupSelector,
        valueMode: mode.name,
        attribute: mode == HtmlValueMode.attribute ? selectedValue : '',
      );

      final chosen = results.firstWhere(
        (result) => result['selector'] == selectedSelector,
      );

      final chosenError = chosen['error'] as String;
      final chosenCount = chosen['count'] as int;
      final canUse = chosenError.isEmpty && chosenCount > 0;

      if (!mounted) return;

      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('セレクターの抽出確認'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('現在の表示後HTMLを、実際のHTML抽出用パーサーで確認しました。'),
                  const SizedBox(height: 12),
                  const Text(
                    '選択中の候補',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText(
                    selectedSelector.isEmpty
                        ? '要素自身（まとまりそのもの）'
                        : selectedSelector,
                  ),
                  const SizedBox(height: 8),
                  if (chosenError.isNotEmpty)
                    Text(
                      '使用できません：$chosenError',
                      style: const TextStyle(color: Colors.orangeAccent),
                    )
                  else if (chosenCount == 0)
                    const Text(
                      'HTML抽出側で一致0件のため使用できません。',
                      style: TextStyle(color: Colors.orangeAccent),
                    )
                  else ...[
                    Text('HTML抽出側：$chosenCount件に一致'),
                    if (chosenCount > 1)
                      const Text(
                        '複数一致しています。一覧用には必要な場合がありますが、'
                        '作品詳細では意図しない先頭要素を取得しないか確認してください。',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    const SizedBox(height: 8),
                    const Text('取得内容の例（先頭3件・各240文字まで）'),
                    for (final preview in chosen['previews'] as List) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        (preview as String).isEmpty
                            ? '（取得する値が空です。取得方法や属性を確認してください）'
                            : preview,
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text(
                    'ほかの候補の確認結果',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final result in results) ...[
                    const SizedBox(height: 10),
                    SelectableText(
                      (result['selector'] as String).isEmpty
                          ? '要素自身'
                          : result['selector'] as String,
                    ),
                    Text(
                      (result['error'] as String).isNotEmpty
                          ? '使用不可：${result['error']}'
                          : 'HTML抽出側：${result['count']}件に一致',
                      style: TextStyle(
                        color:
                            (result['error'] as String).isNotEmpty ||
                                result['count'] == 0
                            ? Colors.orangeAccent
                            : Colors.white70,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    '候補を変える場合は「戻って選び直す」を押してください。\n'
                    'これは現在の表示後HTMLでの確認です。通常HTMLや別作品でも'
                    '使えるかは、設定画面のテストで確認してください。\n'
                    'プレビューは正規表現・整形・相対URL解決などを適用する前の値です。',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('戻って選び直す'),
            ),
            FilledButton(
              onPressed: canUse
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('この設定を使う'),
            ),
          ],
        ),
      );

      if (approved != true || !mounted) return;

      // 確認ダイアログを閉じるフレームと画面を閉じる処理を分ける。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      Navigator.pop(
        context,
        VisualPick(
          page: HtmlProbePage(uri: uri, source: source, bytes: bytes),
          selector: selectedSelector,
          mode: mode,
          attribute: mode == HtmlValueMode.attribute ? selectedValue : 'href',
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _status = '確認・反映できませんでした：$error');
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // WebView本体はWidget側が破棄する。
    super.dispose();
  }

  Widget _details() {
    final selected = _selected;
    final attrs = selected == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(selected['attrs'] as Map);

    final candidates = selected == null
        ? <Map<String, dynamic>>[]
        : (selected['candidates'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map))
              .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(_status),
        const SizedBox(height: 8),
        if (selected == null)
          const Text(
            '上のページの表紙・タイトル・画像などを選んでください。\n'
            'iframe内やShadow DOM内の選択には、この初版は対応しません。',
          ),
        if (selected != null) ...[
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _ready ? () => _move('parent') : null,
                child: const Text('親要素へ'),
              ),
              OutlinedButton(
                onPressed: _ready ? () => _move('child') : null,
                child: const Text('子要素へ'),
              ),
            ],
          ),
          const Text('セレクター候補（押すと一致箇所を強調）'),
          for (final candidate in candidates)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text(
                (candidate['selector'] as String).isEmpty
                    ? '要素自身（まとまりそのもの）'
                    : candidate['selector'] as String,
              ),
              subtitle: Text(
                '${candidate['count']}件に一致'
                '${(candidate['selector'] as String).contains(':first-child') ? '／位置依存のため変更に弱い候補' : ''}',
              ),
              value: candidate['selector'] as String,
              groupValue: _selector,
              onChanged: !_ready
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() => _selector = value);
                      try {
                        await _eval(
                          'window.__ocrPicker?.highlight(${jsonEncode(value)})',
                        );
                      } catch (error) {
                        if (mounted) {
                          setState(() => _status = '強調できませんでした：$error');
                        }
                      }
                    },
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('$_sequence:$_value'),
            initialValue: _value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'この要素から取得する値',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'text', child: Text('文字列')),
              DropdownMenuItem(value: 'innerHtml', child: Text('内側のHTML')),
              DropdownMenuItem(value: 'href', child: Text('href：リンク')),
              DropdownMenuItem(value: 'src', child: Text('src：画像等')),
              DropdownMenuItem(value: 'data-src', child: Text('data-src')),
              DropdownMenuItem(value: 'style', child: Text('style：背景画像など')),
              DropdownMenuItem(value: 'id', child: Text('id')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _value = value);
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _ready && !_capturing ? _use : null,
            child: Text(_capturing ? '確認中…' : '確認してこの設定を使う'),
          ),
          const SizedBox(height: 12),
          const Text('文字列プレビュー'),
          SelectableText(selected['text'] as String? ?? ''),
          const SizedBox(height: 12),
          if (widget.fieldKey == 'thumbnail' && _value == 'style')
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '表紙に反映すると、style 内の最初の url(...) を取得します。',
                style: TextStyle(color: Colors.tealAccent),
              ),
            ),
          const Text('主な属性'),
          SelectableText(const JsonEncoder.withIndent('  ').convert(attrs)),
          const SizedBox(height: 12),
          const Text('選択部分のHTML（先頭6000文字まで）'),
          SelectableText(
            selected['html'] as String? ?? '',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ページから要素を選ぶ'),
      actions: [
        IconButton(
          tooltip: _selecting ? '通常操作に切り替え' : '要素選択に切り替え',
          onPressed: _ready ? _toggle : null,
          icon: Icon(_selecting ? Icons.ads_click : Icons.pan_tool_alt),
        ),
      ],
    ),
    body: SafeArea(
      child: !_prepared
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_status),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final browser = InAppWebView(
                  webViewEnvironment: _environment,
                  initialUrlRequest: URLRequest(
                    url: WebUri(_initial.toString()),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    mediaPlaybackRequiresUserGesture: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportMultipleWindows: true,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                    incognito: true,
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    _timer = Timer.periodic(
                      const Duration(milliseconds: 400),
                      (_) => _poll(),
                    );
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    final url = action.request.url;
                    final uri = url == null
                        ? null
                        : Uri.tryParse(url.toString());

                    if (uri == null ||
                        uri.scheme != 'https' ||
                        uri.userInfo.isNotEmpty ||
                        uri.origin != _initial!.origin) {
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (_ready && _selecting && action.isForMainFrame) {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: (controller, action) async => false,
                  onPermissionRequest: (controller, request) async =>
                      PermissionResponse(
                        resources: request.resources,
                        action: PermissionResponseAction.DENY,
                      ),
                  onLoadStart: (controller, url) {
                    if (!mounted) return;
                    setState(() {
                      _ready = false;
                      _selected = null;
                      _sequence = -1;
                      _selector = '';
                      _status = 'ページを読み込み中';
                    });
                  },
                  onLoadStop: (controller, url) async {
                    try {
                      final current = url == null
                          ? null
                          : Uri.tryParse(url.toString());

                      if (current == null ||
                          current.origin != _initial!.origin) {
                        throw const FormatException('接続先が変わったため選択を中止しました');
                      }

                      await controller.evaluateJavascript(
                        source: _pickerScript,
                      );
                      await controller.evaluateJavascript(
                        source:
                            'window.__ocrPicker.configureScope('
                            '${jsonEncode(widget.groupSelector)},'
                            '${jsonEncode(widget.fieldKey)})',
                      );
                      await controller.evaluateJavascript(
                        source: 'window.__ocrPicker.enable($_selecting)',
                      );

                      if (mounted) {
                        setState(() {
                          _ready = true;
                          _status = _selecting
                              ? widget.groupSelector.isEmpty
                                    ? '調べたい部分をタップ／クリックしてください'
                                    : '青枠のまとまりの中から、この項目に使う部分を選んでください'
                              : '通常操作モードです';
                        });
                      }
                    } catch (error) {
                      if (mounted) {
                        setState(() => _status = '選択機能を準備できませんでした：$error');
                      }
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(() => _status = '読み込みエラー：${error.description}');
                    }
                  },
                );

                if (constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: browser),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 2, child: _details()),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(flex: 3, child: browser),
                    Container(
                      height: 24,
                      alignment: Alignment.center,
                      color: Colors.white10,
                      child: const Text(
                        '下側：選択した要素の情報',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(flex: 2, child: _details()),
                  ],
                );
              },
            ),
    ),
  );
}
