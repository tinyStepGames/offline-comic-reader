import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'element_inspector_page.dart';
import 'services/download_store.dart';
import 'services/html_probe.dart';
import 'services/list_extraction_rule.dart';
import 'services/list_field_pick.dart';
import 'services/site_rule_store.dart';

class ListRuleLabPage extends StatefulWidget {
  const ListRuleLabPage({
    super.key,
    required this.store,
    required this.initialPage,
    required this.initialUrl,
    required this.initialSelector,
    required this.initialAcquisition,
    this.initialRule,
    this.savedSite,
  });

  final DownloadStore store;
  final HtmlProbePage? initialPage;
  final String initialUrl;
  final String initialSelector;
  final String initialAcquisition;
  final ListExtractionRule? initialRule;
  final SavedSiteRule? savedSite;

  @override
  State<ListRuleLabPage> createState() => _ListRuleLabPageState();
}

class _ListRuleLabPageState extends State<ListRuleLabPage> {
  static const _cacheKey = 'rule-lab:list-draft:v1';

  late final TextEditingController _url;
  late final TextEditingController _group;
  late final TextEditingController _siteName;
  String? _savedSiteId;
  final _client = HtmlProbeClient();
  CancelToken? _cancel;
  HtmlProbePage? _page;
  late String _acquisition;
  String _kind = 'works';
  Map<String, ListFieldRule> _fields = defaultListFields();
  ListExtractionReport? _report;
  bool _busy = false;
  bool _showImages = false;
  int _revision = 0;
  String _status = '1作品／1話を囲む要素を指定してください';

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initialUrl);
    _group = TextEditingController(text: widget.initialSelector);
    _page = widget.initialPage;
    _acquisition = widget.initialAcquisition;
    _savedSiteId = widget.savedSite?.id;

    final host = Uri.tryParse(widget.initialUrl)?.host ?? '';
    _siteName = TextEditingController(
      text: widget.savedSite?.name ?? (host.isEmpty ? '新しいサイト' : host),
    );

    final initial = widget.initialRule;
    if (initial != null) {
      _url.text = initial.pageUrl;
      _group.text = initial.groupSelector;
      _kind = initial.kind;
      _acquisition = initial.acquisition;
      _fields = Map.of(initial.fields);
      _page = null;
      _status = '保存設定を開きました。HTML取得またはページから選択してください';
    }
  }

  ListExtractionRule _rule() => ListExtractionRule(
    pageUrl: _url.text.trim(),
    groupSelector: _group.text.trim(),
    fields: Map.of(_fields),
    kind: _kind,
    acquisition: _acquisition,
  );

  void _invalidate() {
    setState(() => _report = null);
  }

  Future<void> _fetch() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final token = CancelToken();
    _cancel = token;

    setState(() {
      _busy = true;
      _report = null;
      _page = null;
      _status = 'HTMLを取得中';
    });

    try {
      final page = await _client.fetch(_url.text, cancelToken: token);
      if (!mounted) return;
      setState(() {
        _page = page;
        _url.text = page.uri.toString();
        _acquisition = 'staticHtml';
        _status = '通常HTMLを取得しました。テストしてください';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '取得できませんでした：$error');
    } finally {
      if (identical(_cancel, token)) _cancel = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGroup() async {
    if (_busy) return;
    final pick = await Navigator.of(context).push<VisualPick>(
      MaterialPageRoute<VisualPick>(
        builder: (_) => ElementInspectorPage(url: _url.text),
      ),
    );

    if (!mounted || pick == null) return;
    setState(() {
      _page = pick.page;
      _url.text = pick.page.uri.toString();
      _group.text = pick.selector;
      _acquisition = 'renderedDom';
      _report = null;
      _status =
          '選択要素を「1件分のまとまり」にしました。'
          '複数件に一致する候補か確認してください';
    });
  }

  Future<void> _pickField(String key) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    try {
      htmlProbeUri(_url.text);
      final group = _group.text.trim();
      if (group.isEmpty) {
        throw StateError('先に「1件分のまとまり」を指定してください');
      }

      final pick = await Navigator.of(context).push<VisualPick>(
        MaterialPageRoute<VisualPick>(
          builder: (_) => ElementInspectorPage(
            url: _url.text.trim(),
            groupSelector: group,
            fieldKey: key,
          ),
        ),
      );

      if (!mounted || pick == null) return;

      final next = listFieldFromPick(
        key: key,
        selector: pick.selector,
        mode: pick.mode,
        attribute: pick.attribute,
      );

      setState(() {
        _page = pick.page;
        _url.text = pick.page.uri.toString();
        _acquisition = 'renderedDom';
        _fields[key] = next.copyWith(
          pattern: _fields[key]!.pattern,
          replacement: _fields[key]!.replacement,
          localizeRelativeTime: _fields[key]!.localizeRelativeTime,
        );
        _revision++;
        _report = null;
        _status =
            '${listFieldLabels[key]}だけに選択結果を反映しました。'
            '「一覧としてテスト」で他のまとまりも確認してください';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = '項目を選択できませんでした：$error');
      }
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final page = _page;

    if (page == null) {
      setState(() => _status = 'HTML取得またはページから選択してください');
      return;
    }

    setState(() {
      _busy = true;
      _report = null;
      _status = '一覧をテスト中';
    });

    try {
      final report = await extractListRowsSafely(page, _rule());
      if (!mounted) return;

      setState(() {
        _report = report;
        _status =
            '${report.total}件のまとまり／'
            '先頭${report.rows.length}件を表示\n'
            '取得元：$_acquisition';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _report = null;
          _status = 'テストできませんでした：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSite() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    try {
      final saved = await SiteRuleStore(
        widget.store.root,
      ).save(id: _savedSiteId, name: _siteName.text, rule: _rule());

      if (!mounted) return;
      setState(() {
        _savedSiteId = saved.id;
        _siteName.text = saved.name;
        _status =
            '「${saved.name}」の'
            '${_kind == 'works' ? '作品一覧' : 'チャプター一覧'}を保存しました。'
            '読書機能への接続はまだ行っていません。';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'サイトへ保存できませんでした：$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rule = _rule();
      rule.validate();
      await widget.store.writeCache(_cacheKey, rule.toJson());
      if (mounted) setState(() => _status = '一覧ルールの下書きを保存しました');
    } catch (error) {
      if (mounted) setState(() => _status = '保存できませんでした：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final data = await widget.store.readCache(_cacheKey);
      if (data == null) throw StateError('保存された下書きがありません');
      final rule = ListExtractionRule.parse(
        // JSON形式として再検証する。
        _encodeCache(data),
      );

      if (!mounted) return;
      final confirmed = await _confirm(
        '下書きを復元',
        '${rule.pageUrl}\n\n現在の編集内容を置き換えますか？',
      );
      if (confirmed && mounted) _apply(rule);
    } catch (error) {
      if (mounted) setState(() => _status = '復元できませんでした：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _encodeCache(dynamic data) => encodeListRuleCache(data);

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('置き換える'),
            ),
          ],
        ),
      ) ??
      false;

  void _apply(ListExtractionRule rule) {
    final samePage =
        _page?.uri.toString() == rule.pageUrl &&
        _acquisition == rule.acquisition;

    setState(() {
      if (!samePage) _page = null;
      _url.text = rule.pageUrl;
      _group.text = rule.groupSelector;
      _kind = rule.kind;
      _acquisition = rule.acquisition;
      _fields = Map.of(rule.fields);
      _revision++;
      _report = null;
      _status = samePage
          ? '設定を反映しました。テストしてください'
          : '設定を反映しました。対象HTMLを取得、またはページから選択してください';
    });
  }

  Future<void> _transfer() async {
    if (_busy) return;
    try {
      final rule = _rule();
      rule.validate();

      final imported = await Navigator.of(context).push<ListExtractionRule>(
        MaterialPageRoute<ListExtractionRule>(
          builder: (_) => ListRuleTransferPage(rule: rule),
        ),
      );

      if (mounted && imported != null) _apply(imported);
    } catch (error) {
      if (mounted) setState(() => _status = '共有画面を開けませんでした：$error');
    }
  }

  Widget _fieldEditor(String key, String label) {
    final rule = _fields[key]!;
    final requiredField = key == 'title' || key == 'url';

    void update(ListFieldRule next) {
      setState(() {
        _fields[key] = next;
        _report = null;
      });
    }

    return ExpansionTile(
      key: ValueKey('$_revision:$key'),
      initiallyExpanded: requiredField,
      title: Text('$label${requiredField ? '（必須）' : ''}'),
      subtitle: Text(
        !rule.enabled
            ? '無効'
            : '${rule.selector.isEmpty ? '要素自身' : rule.selector}'
                  '／${rule.mode.name}'
                  '${rule.attribute.isEmpty ? '' : '：${rule.attribute}'}',
      ),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickField(key),
            icon: const Icon(Icons.ads_click),
            label: Text('$labelをまとまりから選ぶ'),
          ),
        ),
        const SizedBox(height: 12),
        if (!requiredField)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('この項目を取得する'),
            value: rule.enabled,
            onChanged: _busy
                ? null
                : (value) => update(rule.copyWith(enabled: value)),
          ),
        if (rule.enabled) ...[
          TextFormField(
            initialValue: rule.selector,
            enabled: !_busy,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '内側のセレクター',
              helperText: '空欄＝まとまりの要素自身。入力＝その内側。',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                update(_fields[key]!.copyWith(selector: value)),
          ),
          const SizedBox(height: 12),
          if (key == 'date')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('相対時間（英語）を日本語にする'),
              subtitle: const Text(
                '例：2 hours ago → 2時間前\n'
                '未対応の表示は変更しません。日時の計算や自動更新は行いません。',
              ),
              isThreeLine: true,
              value: rule.localizeRelativeTime,
              onChanged: _busy
                  ? null
                  : (value) => update(
                      _fields[key]!.copyWith(localizeRelativeTime: value),
                    ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: rule.pattern,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '正規表現（任意）',
              hintText: r'(\d+(?:\.\d+)?)',
              helperText: '空欄なら正規表現による整形なし。日本語化がONの場合は、その後の文字列に適用。',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                update(_fields[key]!.copyWith(pattern: value)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: rule.replacement,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '整形テンプレート',
              hintText: r'最新第$1話',
              helperText: r'$1・$2＝括弧の内容、$0＝一致全体、$$＝ドル記号。',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                update(_fields[key]!.copyWith(replacement: value)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ListValueMode>(
            key: ValueKey('$_revision:$key:${rule.mode.name}'),
            initialValue: rule.mode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '取得方法',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: ListValueMode.text, child: Text('文字列')),
              DropdownMenuItem(
                value: ListValueMode.attribute,
                child: Text('属性（href・srcなど）'),
              ),
              DropdownMenuItem(
                value: ListValueMode.cssUrl,
                child: Text('属性の中の最初の url(...)'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) {
                      update(
                        _fields[key]!.copyWith(
                          mode: value,
                          attribute: value == ListValueMode.cssUrl
                              ? 'style'
                              : _fields[key]!.attribute,
                        ),
                      );
                    }
                  },
          ),
          if (rule.mode != ListValueMode.text) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('$_revision:$key:attr:${rule.mode.name}'),
              initialValue: rule.attribute,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '属性名',
                hintText: 'href / src / data-src / style / id',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  update(_fields[key]!.copyWith(attribute: value)),
            ),
          ],
        ],
      ],
    );
  }

  Widget _resultCard(ExtractedListRow row, int index) {
    final values = row.values;
    final image = values['thumbnail'] ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showImages && image.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.network(
                  image,
                  height: 100,
                  width: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    height: 100,
                    child: Center(child: Text('画像を表示できません')),
                  ),
                ),
              ),
            Text(
              '${index + 1}. ${values['title'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final entry in values.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SelectableText(
                  '${listFieldLabels[entry.key]}：'
                  '${entry.value.isEmpty ? '（空）' : entry.value}',
                ),
              ),
            for (final issue in row.issues)
              Text(issue, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancel?.cancel('画面を閉じました');
    _client.close();
    _url.dispose();
    _group.dispose();
    _siteName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('一覧ルール'),
        actions: [
          IconButton(
            tooltip: '下書きを復元',
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: '下書きを保存',
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '① 1作品／1話のまとまりを指定\n'
              '② 各項目を「要素自身」または「内側」から取得\n'
              '③ カードで組み合わせを確認',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _siteName,
              enabled: !_busy,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'サイト保存名',
                helperText: '保存ボタンで、現在選んでいる種類の一覧設定を保存します。',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _saveSite,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('サイトに保存'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '対象URL',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _invalidate(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _fetch,
                  child: const Text('通常HTMLを取得'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _pickGroup,
                  child: const Text('まとまりをページから選ぶ'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _transfer,
                  child: const Text('一覧JSON・QR'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 3,
              child: _busy
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox.expand(),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _status,
              style: const TextStyle(color: Colors.tealAccent),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('$_revision:$_kind'),
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: '一覧の種類',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'works', child: Text('作品一覧')),
                DropdownMenuItem(value: 'chapters', child: Text('チャプター一覧')),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _kind = value;
                          _report = null;
                        });
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _group,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '1件分のまとまり',
                hintText: '.comic-card / .chapter-row など',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _invalidate(),
            ),
            const SizedBox(height: 12),
            for (final entry in listFieldLabels.entries)
              _fieldEditor(entry.key, entry.value),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _test,
              icon: const Icon(Icons.science_outlined),
              label: const Text('一覧としてテスト'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('表紙画像を通信して表示'),
              subtitle: const Text('有効にすると抽出した画像URLへアクセスします'),
              value: _showImages,
              onChanged: (value) => setState(() => _showImages = value),
            ),
            if (report != null) ...[
              Text(
                '${report.total}件に一致'
                '・先頭${report.rows.length}件を表示',
              ),
              for (var i = 0; i < report.rows.length; i++)
                _resultCard(report.rows[i], i),
            ],
            const SizedBox(height: 16),
            const Text(
              '下書きは端末内に1件保存します。復元は明示操作です。\n'
              '「サイトに保存」で複数管理できます。読書機能への接続はまだ行いません。\n'
              '各項目の「まとまりから選ぶ」で内側を選択できます。セレクターの手入力も可能です。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class ListRuleTransferPage extends StatefulWidget {
  const ListRuleTransferPage({super.key, required this.rule});
  final ListExtractionRule rule;

  @override
  State<ListRuleTransferPage> createState() => _ListRuleTransferPageState();
}

class _ListRuleTransferPageState extends State<ListRuleTransferPage> {
  late final TextEditingController _text;
  String? _qr;
  String _status = '一覧ルール専用形式です。HTMLやCookieは含めません。';

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.rule.encodeJson());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      final rule = ListExtractionRule.parse(_text.text);
      await Clipboard.setData(ClipboardData(text: rule.encodeJson()));
      if (mounted) setState(() => _status = 'JSONをコピーしました');
    } catch (error) {
      if (mounted) setState(() => _status = 'コピーできませんでした：$error');
    }
  }

  void _makeQr() {
    try {
      final text = ListExtractionRule.parse(_text.text).encodeQr();
      setState(() {
        _qr = text;
        _status = 'QRはスクリーンショットで共有できます';
      });
    } catch (error) {
      setState(() {
        _qr = null;
        _status = 'QRを作れませんでした：$error';
      });
    }
  }

  Future<void> _import() async {
    try {
      final rule = ListExtractionRule.parse(_text.text);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('一覧ルールを取り込む'),
          content: SingleChildScrollView(
            child: Text(
              '${rule.pageUrl}\n\n'
              'まとまり：${rule.groupSelector}\n'
              '種類：${rule.kind}\n\n'
              '編集内容を置き換えます。通信・下書き保存はまだ行いません。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('取り込む'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) Navigator.pop(context, rule);
    } catch (error) {
      if (mounted) setState(() => _status = '取り込めませんでした：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('一覧JSON・QR')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '独自形式の一覧抽出ルールです。'
          '単一抽出のQRや他アプリのルールとは別形式です。\n'
          '共有前にURLへ個人用情報が入っていないか確認してください。',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 14,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'JSONまたはQRの内容文字列',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _qr = null),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: _copy, child: const Text('JSONコピー')),
            OutlinedButton(onPressed: _makeQr, child: const Text('QR表示')),
            FilledButton(onPressed: _import, child: const Text('確認して取り込む')),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(_status),
        if (_qr != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: _qr!,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
