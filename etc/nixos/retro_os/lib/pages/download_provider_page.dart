import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../utils/app_localizations.dart';
import '../utils/gamepad_keyboard.dart';

// 0 = URL field, 1 = Start Download button
const _kUrlField    = 0;
const _kStartButton = 1;

class DownloadProviderPage extends StatefulWidget {
  const DownloadProviderPage({super.key});

  @override
  State<DownloadProviderPage> createState() => _DownloadProviderPageState();
}

class _DownloadProviderPageState extends State<DownloadProviderPage> {
  late final StreamSubscription<GamepadAction> _sub;
  final _scrollController = ScrollController();

  String _providerUrl = '';
  final _logs = <String>[];
  int _selected    = _kUrlField;
  bool _downloading = false;
  bool _cancelled   = false;

  String get _consolesDir {
    final home = Platform.environment['HOME'] ?? '/home/admin';
    return '$home/.local/share/retro_os/Consoles';
  }

  @override
  void initState() {
    super.initState();
    _sub = GamepadService.instance.actions.listen(_handleAction);
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAction(GamepadAction action) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (_downloading) {
      if (action == GamepadAction.back) {
        setState(() => _cancelled = true);
        _appendLog(AppLocalizations.of(context).downloadProviderCancelled);
      }
      return;
    }
    switch (action) {
      case GamepadAction.left:
        setState(() => _selected = _kUrlField);
      case GamepadAction.right:
        setState(() => _selected = _kStartButton);
      case GamepadAction.confirm:
        if (_selected == _kUrlField) {
          _openKeyboard();
        } else {
          _startDownload();
        }
      case GamepadAction.back:
        Navigator.pop(context);
      default:
        break;
    }
  }

  Future<void> _openKeyboard() async {
    final result = await showGamepadKeyboard(
      context,
      initialValue: _providerUrl,
      hint: 'http://192.168.0.x:3000',
    );
    if (result != null) setState(() => _providerUrl = _normalizeUrl(result));
  }

  // ── Download ───────────────────────────────────────────────────────────────

  Future<void> _startDownload() async {
    final l = AppLocalizations.of(context);
    if (_providerUrl.isEmpty) {
      _appendLog(l.downloadProviderNoUrl);
      return;
    }

    setState(() {
      _downloading = true;
      _cancelled   = false;
      _logs.clear();
    });

    try {
      _appendLog(l.downloadProviderFetching);
      final manifest = await _fetchManifest();
      final consoles = (manifest['consoles'] as List).cast<Map<String, dynamic>>();

      for (final console in consoles) {
        if (_cancelled) break;
        final consoleName = console['name'] as String;

        await _downloadAsset(console['image'] as String?, consoleName);

        final games = (console['games'] as List).cast<Map<String, dynamic>>();
        for (final game in games) {
          if (_cancelled) break;
          final gameName = game['name'] as String;

          await _downloadAsset(game['image'] as String?, '$consoleName › $gameName image');
          await _downloadAsset(game['rom']   as String?, '$consoleName › $gameName ROM');
          if (game.containsKey('achievements')) {
            await _downloadAsset(game['achievements'] as String?, '$consoleName › $gameName achievements');
          }
        }
      }

      if (!_cancelled) _appendLog(l.downloadProviderDone);
    } catch (e) {
      if (mounted) _appendLog(AppLocalizations.of(context).downloadProviderError(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchManifest() async {
    final uri = Uri.parse('$_providerUrl/manifest.json');
    final client = HttpClient();
    try {
      final request  = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('manifest returned HTTP ${response.statusCode}', uri: uri);
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> _downloadAsset(String? relativeUrl, String label) async {
    if (relativeUrl == null || _cancelled) return;
    final l = AppLocalizations.of(context);

    final localPath = _localPath(relativeUrl);
    if (localPath == null) return;

    final file = File(localPath);
    await file.parent.create(recursive: true);

    final existingSize = file.existsSync() ? await file.length() : 0;

    final uri = Uri.parse('$_providerUrl$relativeUrl');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      if (existingSize > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingSize-');
      }

      final response = await request.close();

      // 416 = server says file is already complete
      if (response.statusCode == 416) {
        _appendLog(l.downloadProviderSkipped(label));
        await response.drain<void>();
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }

      final totalBytes = response.contentLength;
      final suffix = totalBytes > 0 ? ' (${_formatBytes(existingSize + totalBytes)})' : '';
      _appendLog(l.downloadProviderDownloading('$label$suffix'));

      final mode = response.statusCode == 206 ? FileMode.append : FileMode.write;
      final sink = file.openWrite(mode: mode);
      await response.pipe(sink);

      _appendLog(l.downloadProviderFileDone(label));
    } finally {
      client.close();
    }
  }

  /// Maps a /files/... URL to the absolute local path inside _consolesDir.
  String? _localPath(String relativeUrl) {
    if (!relativeUrl.startsWith('/files/')) return null;
    final encoded = relativeUrl.substring('/files/'.length);
    final parts   = encoded.split('/').map(Uri.decodeComponent).toList();
    return '$_consolesDir/${parts.join('/')}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _normalizeUrl(String url) {
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    if (uri.hasPort) return url;
    return Uri(
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      host: uri.host,
      port: 3000,
      path: uri.path,
    ).toString();
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _logs.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(80, 80, 80, 32),
            child: Text(
              l.downloadProviderTitle,
              style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: l.downloadProviderIdle
                  .split('\n\n')
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          p,
                          style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80),
            child: Row(
              children: [
                Expanded(
                  child: _UrlField(
                    url: _providerUrl,
                    hint: 'http://192.168.0.x:3000',
                    selected: !_downloading && _selected == _kUrlField,
                    enabled: !_downloading,
                    onTap: _openKeyboard,
                  ),
                ),
                const SizedBox(width: 16),
                _StartButton(
                  label: l.downloadProviderStartDownload,
                  selected: !_downloading && _selected == _kStartButton,
                  loading: _downloading,
                  onTap: _startDownload,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _logs.isEmpty
                    ? const Text(
                        '...',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Text(
                          _logs[i],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'Montserrat',
                            height: 1.5,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 24),
            child: Text(
              _downloading ? l.downloadProviderCancelHint : l.downloadProviderBackHint,
              style: const TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _UrlField extends StatelessWidget {
  const _UrlField({
    required this.url,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String url;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Colors.white : Colors.white24),
        ),
        child: Row(
          children: [
            Icon(Icons.link, color: selected ? Colors.black54 : Colors.white38, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                url.isEmpty ? hint : url,
                style: TextStyle(
                  color: selected
                      ? (url.isEmpty ? Colors.black38 : Colors.black)
                      : (url.isEmpty ? Colors.white24 : Colors.white),
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.edit_outlined, color: selected ? Colors.black38 : Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.label,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: loading
              ? Colors.white10
              : selected
                  ? Colors.greenAccent
                  : Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
              )
            else
              Icon(Icons.download_rounded, color: selected ? Colors.black : Colors.greenAccent, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: loading
                    ? Colors.white24
                    : selected
                        ? Colors.black
                        : Colors.greenAccent,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
