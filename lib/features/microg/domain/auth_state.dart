import 'package:looper_player/features/microg/data/auth_session.dart';

enum AuthStatus { signedOut, authenticating, signedIn, expired }

class AuthState {
  const AuthState(this.status, {this.session, this.error});
  const AuthState.signedOut() : this(AuthStatus.signedOut);

  final AuthStatus status;

  /// The active session (signedIn), or the one that expired.
  final AuthSession? session;

  /// Why the last sign-in failed, for the UI.
  final String? error;
}
