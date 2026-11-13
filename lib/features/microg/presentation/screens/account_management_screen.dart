import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/microg/domain/auth_session.dart';
import 'package:looper_player/features/microg/data/microg_platform.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';
import 'package:looper_player/features/microg/presentation/providers/auth_provider.dart';
import 'package:looper_player/features/microg/presentation/screens/web_login_screen.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Settings > Online music > Google account: sign in (microG or Google's
/// page), see who is signed in, sign out.
class AccountManagementScreen extends ConsumerStatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  ConsumerState<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState
    extends ConsumerState<AccountManagementScreen> {
  MicrogInfo? _microg;

  @override
  void initState() {
    super.initState();
    MicrogPlatform.detect().then((m) {
      if (mounted) setState(() => _microg = m);
    });
  }

  TextStyle _title() =>
      AppFonts.jostStyle(color: Colors.white, fontWeight: FontWeight.w500);
  TextStyle _sub() => AppFonts.jostStyle(color: Colors.white54, fontSize: 12);

  Future<void> _microgSignIn(MicrogInfo info) async {
    final link = await ref.read(authProvider.notifier).microgLink(info);
    if (link == null || !mounted) return;
    await _webSignIn(
      WebLoginScreen(startUrl: link.url, microgAccount: link.account),
    );
  }

  Future<void> _webSignIn([
    WebLoginScreen screen = const WebLoginScreen(),
  ]) async {
    final session = await Navigator.of(
      context,
    ).push<AuthSession>(riseRoute(screen));
    if (session != null) {
      await ref.read(authProvider.notifier).saveWebSession(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);
    final busy = auth.status == AuthStatus.authenticating;
    final microg = _microg;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.accountTitle, style: _title()),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (auth.status == AuthStatus.expired)
            _note(l10n.accountExpired, Colors.orangeAccent),
          if (auth.error case final error?)
            _note(l10n.accountSignInFailed(error), Colors.redAccent),
          if (auth.status == AuthStatus.signedIn) ...[
            ListTile(
              leading: const Icon(
                LucideIcons.circleUser,
                color: Colors.white70,
              ),
              title: Text(
                auth.session?.displayName ?? l10n.accountSignedIn,
                style: _title(),
              ),
              subtitle: Text(
                auth.session?.microgAccount != null
                    ? '${auth.session?.microgAccount} · microG'
                    : l10n.accountSignedIn,
                style: _sub(),
              ),
            ),
            ListTile(
              leading: const Icon(LucideIcons.logOut, color: Colors.white70),
              title: Text(l10n.accountSignOut, style: _title()),
              subtitle: Text(l10n.accountSignOutDesc, style: _sub()),
              onTap: notifier.signOut,
            ),
          ] else ...[
            if (microg != null && microg.usable)
              ListTile(
                enabled: !busy,
                leading: const Icon(
                  LucideIcons.shieldCheck,
                  color: Colors.white70,
                ),
                title: Text(l10n.accountSignInMicrog, style: _title()),
                subtitle: Text(l10n.accountSignInMicrogDesc, style: _sub()),
                onTap: () => _microgSignIn(microg),
              ),
            ListTile(
              enabled: !busy,
              leading: Icon(
                Platform.isAndroid
                    ? LucideIcons.logIn
                    : LucideIcons.clipboardPaste,
                color: Colors.white70,
              ),
              title: Text(
                Platform.isAndroid
                    ? l10n.accountSignInWeb
                    : l10n.accountPasteCookies,
                style: _title(),
              ),
              subtitle: Text(
                Platform.isAndroid
                    ? l10n.accountSignInWebDesc
                    : l10n.accountPasteCookiesDesc,
                style: _sub(),
              ),
              onTap: () => _webSignIn(),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.accountRisk, style: _sub()),
          ),
        ],
      ),
    );
  }

  Widget _note(String text, Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, style: AppFonts.jostStyle(color: color, fontSize: 13)),
  );
}
