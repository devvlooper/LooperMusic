import 'dart:io';

import 'package:flutter/material.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/microg/domain/auth_session.dart';
import 'package:looper_player/features/microg/data/microg_platform.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Engine B. Android shows Google's own sign-in page in a WebView and keeps
/// the music.youtube.com cookies once Google lands there. Desktop has no
/// WebView, so the user pastes the Cookie header of a music.youtube.com
/// request. With [startUrl] (a microG web sign-in link) Google signs the
/// WebView in without a password. Pops with an [AuthSession], or null.
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key, this.startUrl, this.microgAccount});

  final String? startUrl;

  /// The GmsCore account behind [startUrl], kept on the session.
  final String? microgAccount;

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  static const _loginUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube&passive=true'
      '&continue=https%3A%2F%2Fmusic.youtube.com%2F';
  static const _targetHost = 'music.youtube.com';

  WebViewController? _web;
  final _paste = TextEditingController();
  String? _pasteError;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _startWeb();
  }

  Future<void> _startWeb() async {
    // Start from a clean cookie store so Google asks which account to use.
    await MicrogPlatform.clearWebCookies();
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: _check));
    await web.loadRequest(Uri.parse(widget.startUrl ?? _loginUrl));
    if (mounted) setState(() => _web = web);
  }

  Future<void> _check(String url) async {
    if (_done || Uri.tryParse(url)?.host != _targetHost) return;
    final header = await MicrogPlatform.webCookies('https://$_targetHost');
    final session = AuthSession.fromCookieHeader(
      header ?? '',
      microgAccount: widget.microgAccount,
    );
    if (session == null || _done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(session);
  }

  void _savePaste() {
    final session = AuthSession.fromCookieHeader(_paste.text);
    if (session == null) {
      setState(
        () => _pasteError = AppLocalizations.of(context)!.accountNoSapisid,
      );
      return;
    }
    Navigator.of(context).pop(session);
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final web = _web;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          Platform.isAndroid ? l10n.accountSignInWeb : l10n.accountPasteCookies,
          style: AppFonts.jostStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Platform.isAndroid
          ? web == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: web)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.accountPasteHelp,
                  style: AppFonts.jostStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _paste,
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.accountCookieHeader,
                    errorText: _pasteError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _savePaste,
                    child: Text(l10n.save),
                  ),
                ),
              ],
            ),
    );
  }
}
