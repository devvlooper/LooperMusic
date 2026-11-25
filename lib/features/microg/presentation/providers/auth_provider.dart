import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/microg/data/account_auth.dart';
import 'package:looper_player/features/microg/domain/auth_session.dart';
import 'package:looper_player/features/microg/data/microg_platform.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';
import 'package:looper_player/features/online/data/account_data_sync.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/taste_profile_store.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/features/settings/presentation/screens/account_view.dart'
    show saveProfilePhotoFromUrl;

/// Mirrors [AccountAuth] for the UI and runs the sign-in flows.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final source = AccountAuth.instance.state;
    void listener() {
      state = source.value;
      if (source.value.status == AuthStatus.signedIn) {
        unawaited(_syncAccountData());
      }
    }

    source.addListener(listener);
    ref.onDispose(() => source.removeListener(listener));
    unawaited(
      AccountAuth.instance.restore().then((_) {
        if (AccountAuth.instance.signedIn) {
          unawaited(_syncAccountData());
          unawaited(_adoptAccountPhoto());
        }
      }),
    );
    return source.value;
  }

  Future<void> _syncAccountData({bool force = false}) async {
    final artists = await AccountDataSync.sync(force: force);
    ref.read(accountDataRevisionProvider.notifier).bump();
    if (artists.isNotEmpty) {
      await ref
          .read(tasteProvider.notifier)
          .mergeAccountTaste(artists: artists);
      TasteProfileStore.invalidate();
    }
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
      final account = await OnlineApi.account();
      final name = account.name;
      if (name == null) {
        await auth.abort('YouTube did not accept this sign-in');
        return;
      }
      await auth.commit(session.withName(name.isEmpty ? null : name));
      await _syncAccountData(force: true);
      unawaited(_adoptAccountPhoto(account.photo));
    } catch (e) {
      await auth.abort('$e');
      return;
    }
    unawaited(ref.read(onlineHomeProvider.notifier).refresh());
  }

  /// With no profile photo of the user's own, saves the signed-in
  /// account's photo as it ([url] when the caller already has it).
  Future<void> _adoptAccountPhoto([String? url]) async {
    try {
      // Settings start as defaults until loaded: an unloaded empty path
      // would overwrite the user's own photo.
      await ref.read(settingsProvider.notifier).initialization;
      if (ref.read(settingsProvider).userPhotoPath.isNotEmpty) return;
      url ??= (await OnlineApi.account()).photo;
      if (url == null) return;
      await saveProfilePhotoFromUrl(ref.read(settingsProvider.notifier), url);
    } catch (_) {}
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
