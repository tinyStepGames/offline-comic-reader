import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'services/site_rule_bundle.dart';
import 'site_bundle_qr_page.dart';
import 'services/site_rule_store.dart';

class SiteBundlePage extends StatefulWidget {
  const SiteBundlePage({super.key, required this.repository, this.initialSite});

  final SiteRuleStore repository;
  final SavedSiteRule? initialSite;

  @override
  State<SiteBundlePage> createState() => _SiteBundlePageState();
}

class _SiteBundlePageState extends State<SiteBundlePage> {
  final _text = TextEditingController();

  SiteRuleBundle? _bundle;
  List<SavedSiteRule> _sites = [];

  String _target = '';
  String? _qr;
  String _status = '';

  bool _busy = false;
  CancelToken? _cancel;

  bool get _exporting => widget.initialSite != null;

  bool get _canScan => Platform.isIOS || Platform.isAndroid;

  @override
  void initState() {
    super.initState();

    if (_exporting) {
      try {
        _bundle = SiteRuleBundle.fromSite(widget.initialSite!);
        _text.text = _bundle!.encodeJson();
        _status = 'このJSONにサイト1件分の設定が入っています。';
      } catch (error) {
        _status = '共有内容を作成できませんでした：$error';
      }
    }
  }

  @override
  void dispose() {
    _cancel?.cancel('画面を閉じました');
    _text.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));

      if (mounted) {
        setState(() => _status = '$labelをコピーしました');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'コピーできませんでした：$error');
      }
    }
  }

  Future<void> _showQr() async {
    final bundle = _bundle;
    if (bundle == null || _busy) return;

    try {
      final payload = bundle.encodeQr();

      setState(() {
        _qr = payload;
        _status = '設定一式のQRを作成しました。';
      });

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              SiteBundleQrPage(payload: payload, siteName: bundle.site.name),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _qr = null;
        _status = 'QRを表示できませんでした：$error';
      });
    }
  }

  Future<void> _scan() async {
    if (!_canScan || _busy) return;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _SiteQrScanner()),
    );

    if (!mounted || result == null) return;

    _text.text = result;
    await _inspect();
  }

  Future<void> _inspect() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _bundle = null;
    });

    try {
      final bundle = SiteRuleBundle.parse(_text.text);
      final sites = await widget.repository.load();

      if (!mounted) return;

      setState(() {
        _bundle = bundle;
        _sites = sites;
        _target = '';
        _status = '形式を確認しました。まだ通信・保存はしていません。';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = '読み取れませんでした：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _summary(SavedSiteRule site) {
    final works = site.rules['works'];
    final chapters = site.rules['chapters'];
    final tags = site.tagNavigation;
    final search = site.searchSettings;

    String acquisitionLabel(String? value) {
      if (value == null) return '未設定';
      return value == 'renderedDom' ? '表示後HTML' : '通常HTML';
    }

    final origins = {
      for (final rule in site.rules.values) Uri.parse(rule.pageUrl).origin,
      if (site.images != null) Uri.parse(site.images!.pageUrl).origin,
      if (tags != null) Uri.parse(tags.rule.pageUrl).origin,
      if (search != null) Uri.parse(search.template.url('sample')).origin,
      for (final tab in site.browseTabs) Uri.parse(tab.pageUrl).origin,
    };

    final tabNames = site.browseTabs.map((tab) => tab.title).join(' ／ ');

    final searchRuleLabel = search == null
        ? '未設定'
        : search.rule != null
        ? '検索専用'
        : tags != null
        ? 'タグ先を使用'
        : '通常一覧を使用';

    return 'サイト：${site.name}\n\n'
        '作品一覧：${acquisitionLabel(works?.acquisition)}\n'
        '通常一覧のページ送り：'
        '${works?.paginationUrl.isNotEmpty == true ? 'あり' : 'なし'}\n'
        'チャプター一覧：${acquisitionLabel(chapters?.acquisition)}\n'
        '作品詳細：'
        '${chapters?.details.isNotEmpty == true ? 'あり' : '未設定'}\n'
        '本文画像：${acquisitionLabel(site.images?.acquisition)}\n\n'
        'タグ先一覧：${acquisitionLabel(tags?.rule.acquisition)}\n'
        'タグURL変換：'
        '${tags?.urlPattern.isNotEmpty == true ? 'あり' : 'なし'}\n'
        '検索：${search == null ? '未設定' : 'あり'}\n'
        '検索の抽出ルール：$searchRuleLabel\n'
        'サイト別タブ：${site.browseTabs.length}件\n'
        '${tabNames.isEmpty ? '' : '$tabNames\n'}\n'
        '含めないもの：保存画像・お気に入り・履歴・'
        '閲覧位置・開いたマーク・実行時キャッシュ・Cookie\n\n'
        '注意：設定内のURLや整形テンプレートは共有されます。'
        '秘密のトークンなどを書いている場合は共有前に確認してください。\n\n'
        '取得元：\n${origins.join('\n')}';
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String accept,
  }) async {
    if (!mounted) return false;

    return await showDialog<bool>(
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
                child: Text(accept),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _apply() async {
    final bundle = _bundle;

    if (_busy || bundle == null || _exporting) return;

    final matches = _sites.where((site) => site.id == _target);
    final target = matches.isEmpty ? null : matches.single;

    // 確認ダイアログを含めて二重実行を防ぐ。
    setState(() => _busy = true);

    CancelToken? token;

    try {
      final confirmed = await _confirm(
        title: 'サイト設定を反映しますか？',
        message:
            '${_summary(bundle.site)}\n\n'
            '${target == null ? '新しいサイトとして追加します。' : '「${target.name}」の設定一式を置き換えます。共有側にない設定は未設定になります。'}\n\n'
            '続けると、この設定のURLへ通常HTML取得の通信を行います。'
            '作品一覧の先頭ページを確認し、作品一覧がなければ'
            'チャプター一覧のサンプルURLを確認します。\n\n'
            '本文画像の全件検証・全作品の検証ではありません。'
            '通常HTML／表示後HTMLの保存設定は維持します。\n\n'
            '信頼できる提供元の設定だけ取り込んでください。',
        accept: '通常HTMLを取得して反映',
      );

      if (!mounted || !confirmed) return;

      final activeToken = CancelToken();
      token = activeToken;
      _cancel = activeToken;

      setState(() {
        _status = '通常HTMLを取得して一覧を確認しています…';
      });

      String checkMessage;

      try {
        final result = await checkSiteBundleStatic(
          bundle,
          cancelToken: activeToken,
        );

        final usable = result.items.where((item) => item.url != null).length;

        checkMessage = '通常HTMLで開ける一覧項目を$usable件確認しました。';
      } catch (error) {
        if (!mounted || activeToken.isCancelled) return;

        final saveAnyway = await _confirm(
          title: '通常HTMLでは確認できませんでした',
          message:
              '$error\n\n'
              'まだ保存していません。\n'
              '表示後HTMLが必要なサイトでは、通常HTMLだけでは'
              '一覧を確認できないことがあります。\n\n'
              'このまま設定だけを反映しますか？'
              '動作確認済みとしては扱いません。',
          accept: '未確認の設定として反映',
        );

        if (!mounted || !saveAnyway || activeToken.isCancelled) {
          if (mounted) {
            setState(() {
              _status =
                  '反映を取り消しました。'
                  '保存設定は変更していません。';
            });
          }
          return;
        }

        checkMessage = '通常HTMLでの取得は未確認です。';
      }

      if (!mounted || activeToken.isCancelled) return;

      await widget.repository.importSiteBundle(
        incoming: bundle.site,
        targetId: target?.id,
        expectedUpdatedAt: target?.updatedAt,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('サイト設定を反映しました'),
          content: Text(
            '$checkMessage\n\n'
            '作品詳細・本文画像など、含まれている設定を'
            'まとめて保存しました。\n'
            '保存画像・お気に入り・履歴は変更していません。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = '反映できませんでした：$error');
      }
    } finally {
      if (identical(_cancel, token)) {
        _cancel = null;
      }

      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(_exporting ? 'サイト一式のJSON・QR' : 'サイト一式を取り込む')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'サイト1件分の独自形式です。Yealico互換ではありません。\n'
              '作品一覧・ページ送り・チャプター一覧・作品詳細・'
              '本文画像・正規表現など、保存されている設定をまとめます。\n'
              '保存画像・お気に入り・履歴・Cookieは含みません。\n'
              '共有前に、設定URLに個人用トークンがないか確認してください。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              readOnly: _exporting || _busy,
              minLines: 7,
              maxLines: 12,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'サイト一式JSON／QR内容の文字列',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_bundle != null) {
                  setState(() => _bundle = null);
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_exporting && bundle != null) ...[
                  OutlinedButton(
                    onPressed: () => _copy(_text.text, 'JSON'),
                    child: const Text('JSONをコピー'),
                  ),
                  OutlinedButton(
                    onPressed: _showQr,
                    child: const Text('設定一式のQRを表示'),
                  ),
                  if (_qr != null)
                    OutlinedButton(
                      onPressed: () => _copy(_qr!, 'QR内容'),
                      child: const Text('QR内容をコピー'),
                    ),
                ],
                if (!_exporting) ...[
                  OutlinedButton(
                    onPressed: _busy ? null : _inspect,
                    child: const Text('内容を確認'),
                  ),
                  if (_canScan)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('カメラでQRを読む'),
                    ),
                ],
              ],
            ),
            if (!_exporting && !_canScan)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'この環境ではカメラ読み取りを使いません。'
                  'JSONまたはQR内容の文字列を貼り付けてください。',
                ),
              ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            SelectableText(_status),
            if (bundle != null) ...[
              const SizedBox(height: 20),
              SelectableText(_summary(bundle.site)),
              if (!_exporting) ...[
                const SizedBox(height: 16),
                const Text('反映先'),
                DropdownButton<String>(
                  value: _target,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('新しいサイトとして追加'),
                    ),
                    for (final site in _sites)
                      DropdownMenuItem(
                        value: site.id,
                        child: Text(
                          '${site.name} を更新',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _target = value ?? '';
                          });
                        },
                ),
                const Text(
                  '更新では選択した保存先のIDを維持します。'
                  'サイト名が同じでも自動では上書きしません。',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _apply,
                  icon: const Icon(Icons.download_done),
                  label: const Text('通常HTMLを取得して反映'),
                ),
              ],
            ],
            if (_qr != null) ...[
              const SizedBox(height: 20),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: QrImageView(
                          data: _qr!,
                          version: QrVersions.auto,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'この1枚に設定一式が入っています。'
                'スクリーンショットで共有できます。\n'
                '読み取りにくい場合は、大きい画面で表示するか'
                'JSONを使用してください。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SiteQrScanner extends StatefulWidget {
  const _SiteQrScanner();

  @override
  State<_SiteQrScanner> createState() => _SiteQrScannerState();
}

class _SiteQrScannerState extends State<_SiteQrScanner> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('サイト一式のQRを読む')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '「サイト一式のJSON・QR」で作成したQRを写してください。'
            '読み取りだけでは通信・保存しません。',
          ),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              if (_accepted) return;

              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;

                if (value == null || !value.startsWith(SiteRuleBundle.prefix)) {
                  continue;
                }

                _accepted = true;

                // カメライベント中の直接的な画面遷移を避ける。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    Navigator.pop(context, value);
                  }
                });

                break;
              }
            },
          ),
        ),
      ],
    ),
  );
}
