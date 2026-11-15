import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'services/html_probe.dart';

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

  const restore = () => {
    for (const item of marked) {
      item.el.style.outline = item.outline;
      item.el.style.outlineOffset = item.offset;
    }
    marked = [];
  };

  const esc = s => CSS.escape(s);
  const simple = el => {
    const tag = el.tagName.toLowerCase();
    const classes = [...el.classList]
      .filter(v => v.length < 50 && !/\d{5}/.test(v))
      .slice(0, 2);
    return tag + classes.map(v => '.' + esc(v)).join('');
  };

  const path = el => {
    const parts = [];
    for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
      let part = node.tagName.toLowerCase();
      if (node.id) {
        part += '#' + esc(node.id);
        parts.unshift(part);
        break;
      }
      const parent = node.parentElement;
      if (parent) {
        const siblings = [...parent.children].filter(
          n => n.tagName === node.tagName
        );
        if (siblings.length > 1) {
          part += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';
        }
      }
      parts.unshift(part);
    }
    return parts.join(' > ');
  };

  const highlight = selector => {
    restore();
    let nodes;
    try { nodes = [...document.querySelectorAll(selector)]; }
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
    restore();
    selected = el;
    const candidates = [];
    const proposals = [simple(el)];

    if (el.parentElement) {
      proposals.push(simple(el.parentElement) + ' > ' + simple(el));
    }
    proposals.push(path(el));

    for (const selector of [...new Set(proposals)]) {
      try {
        candidates.push({
          selector,
          count: document.querySelectorAll(selector).length
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
  const ElementInspectorPage({super.key, required this.url});

  final String url;

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
        _status = '選択：${data['tag']}／青枠は同じ条件に一致する要素';
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
    if (!_ready || _selector.isEmpty || _capturing) return;
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

      final mode = _value == 'text'
          ? HtmlValueMode.text
          : _value == 'innerHtml'
          ? HtmlValueMode.innerHtml
          : HtmlValueMode.attribute;

      if (!mounted) return;
      Navigator.pop(
        context,
        VisualPick(
          page: HtmlProbePage(uri: uri, source: source, bytes: bytes),
          selector: _selector,
          mode: mode,
          attribute: mode == HtmlValueMode.attribute ? _value : 'href',
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _status = '反映できませんでした：$error');
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
              title: Text(candidate['selector'] as String),
              subtitle: Text(
                '${candidate['count']}件に一致'
                '${(candidate['selector'] as String).contains('nth-of-type') ? '／位置依存のため変更に弱い候補' : ''}',
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
              DropdownMenuItem(value: 'style', child: Text('style')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _value = value);
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _ready && !_capturing ? _use : null,
            child: Text(_capturing ? '反映中…' : 'この設定を使う'),
          ),
          const SizedBox(height: 12),
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
                        source: 'window.__ocrPicker.enable($_selecting)',
                      );

                      if (mounted) {
                        setState(() {
                          _ready = true;
                          _status = _selecting
                              ? '調べたい部分をタップ／クリックしてください'
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
