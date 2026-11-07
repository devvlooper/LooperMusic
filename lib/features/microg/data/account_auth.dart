import 'package:flutter/foundation.dart';
import 'package:looper_player/features/microg/data/auth_session.dart';
import 'package:looper_player/features/microg/data/auth_store.dart';
import 'package:looper_player/features/microg/data/microg_platform.dart';
import 'package:looper_player/features/microg/data/sapisid_hasher.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';

/// The signed-in Google account that signs every music.youtube.com call
/// (InnerTube.music). Streams (`/player`) never use it.
class AccountAuth {
  AccountAuth._();
  static final instance = AccountAuth._();

  final state = ValueNotifier<AuthState>(const AuthState.signedOut());

  bool get signedIn => state.value.status == AuthStatus.signedIn;

  AuthSession? _session;
  Future<void>? _restoring;

  /// Loads the saved session once.
  Future<void> restore() => _restoring ??= () async {
    final saved = await AuthStore.load();
    if (saved == null || _session != null) return;
    if (state.value.status != AuthStatus.signedOut) return;
    _session = saved;
    state.value = AuthState(AuthStatus.signedIn, session: saved);
  }();

  /// Headers that sign a music.youtube.com call; empty when signed out.
  Future<Map<String, String>> headers() async {
    await restore();
    final s = _session;
    if (s == null) return const {};
    return {
      'Cookie': s.cookie,
      'Authorization': SapisidHasher.generateHeader(s.sapisid!),
      'X-Goog-AuthUser': '0',
    };
  }

  /// After a 401. Cookies cannot be renewed in the background, so the
  /// session expires and the user signs in again; no retry.
  // shortcut: a microG session could be renewed silently with a fresh
  // weblogin link; add that if microG users see expiries often.
  Future<bool> recover() async {
    final s = _session;
    if (s == null) return false;
    _session = null;
    state.value = AuthState(AuthStatus.expired, session: s);
    return false;
  }

  /// Signs requests with [session] without saving it, so sign-in can check
  /// that YouTube accepts it.
  void trial(AuthSession session) {
    _restoring ??= Future.value();
    _session = session;
    state.value = AuthState(AuthStatus.authenticating, session: session);
  }

  Future<void> commit(AuthSession session) async {
    await AuthStore.save(session);
    _session = session;
    state.value = AuthState(AuthStatus.signedIn, session: session);
  }

  /// A failed sign-in: go back to the saved session, if any.
  Future<void> abort(String? error) async {
    final saved = await AuthStore.load();
    _session = saved;
    state.value = saved == null
        ? AuthState(AuthStatus.signedOut, error: error)
        : AuthState(AuthStatus.signedIn, session: saved, error: error);
  }

  Future<void> signOut() async {
    _session = null;
    await AuthStore.clear();
    try {
      await MicrogPlatform.clearWebCookies();
    } catch (_) {}
    state.value = const AuthState.signedOut();
  }
}
