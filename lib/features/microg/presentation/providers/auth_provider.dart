import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/microg/data/account_auth.dart';
import 'package:looper_player/features/microg/data/auth_session.dart';
import 'package:looper_player/features/microg/data/microg_platform.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';
import 'package:looper_player/features/online/data/account_data_sync.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';

/// Mirrors [AccountAuth] for the UI and runs the sign-in flows.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final source = AccountAuth.instance.state;
    void listener() {
      state = source.value;
      if (source.value.status == AuthStatus.signedIn) {
        unawaited(AccountDataSync.sync(ref));
      }
    }
    source.addListener(listener);
    ref.onDispose(() => source.removeListener(listener));
    unawaited(AccountAuth.instance.restore().then((_) {
      if (AccountAuth.instance.signedIn) {
        unawaited(AccountDataSync.sync(ref));
      }
    }));
    return source.value;
  }

  /// Engine A: pick a GmsCore account and get a one-time web sign-in link
  /// for it (GmsCore asks the user to approve Looper the first time). The
  /// screen opens the link in the login WebView, which ends in cookies.
  Future<({String url, String account})?> microgLink(MicrogInfo info) async {
    final type = info.accountType!;
    try {
      final account = await MicrogPlatform.chooseAccount(type);
      if (account == null) return null;
      return (
        url: await MicrogPlatform.webloginUrl(account, type),
        account: account,
      );
    } catch (e) {
      await AccountAuth.instance.abort('$e');
      return null;
    }
  }

  /// Engine B: cookies from the login WebView or a pasted header.
  Future<void> saveWebSession(AuthSession session) => _verify(session);

  /// Saves [session] only when YouTube answers as that account.
  Future<void> _verify(AuthSession session) async {
    final auth = AccountAuth.instance;
    auth.trial(session);
    try {
      final name = await OnlineApi.accountName();
      if (name == null) {
        await auth.abort('YouTube did not accept this sign-in');
        return;
      }
      await auth.commit(session.withName(name.isEmpty ? null : name));
      await AccountDataSync.sync(ref, force: true);
    } catch (e) {
      await auth.abort('$e');
      return;
    }
    unawaited(ref.read(onlineHomeProvider.notifier).refresh());
  }

  Future<void> signOut() async {
    await AccountAuth.instance.signOut();
    await AccountDataSync.clear();
    unawaited(ref.read(onlineHomeProvider.notifier).refresh());
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
