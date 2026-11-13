/// One signed-in Google account: music.youtube.com cookies, however they
/// were obtained (login WebView, a microG web sign-in link, or a pasted
/// header).
class AuthSession {
  const AuthSession._(this.cookie, {this.displayName, this.microgAccount});

  /// A session, or null when [header] has no SAPISID (not signed in).
  /// Accepts a bare `a=b; c=d` header or one pasted with its `Cookie:` name.
  static AuthSession? fromCookieHeader(
    String header, {
    String? displayName,
    String? microgAccount,
  }) {
    final cookie = header
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), '');
    final session = AuthSession._(
      cookie,
      displayName: displayName,
      microgAccount: microgAccount,
    );
    return session.sapisid == null ? null : session;
  }

  /// The raw `Cookie` header for music.youtube.com.
  final String cookie;

  /// The YouTube name shown in the UI.
  final String? displayName;

  /// The GmsCore account (an email) when microG signed this session in.
  final String? microgAccount;

  /// SAPISID, or its `__Secure-3PAPISID` twin (same value).
  String? get sapisid {
    String? value(String name) {
      for (final part in cookie.split(';')) {
        final i = part.indexOf('=');
        if (i > 0 && part.substring(0, i).trim() == name) {
          final v = part.substring(i + 1).trim();
          return v.isEmpty ? null : v;
        }
      }
      return null;
    }

    return value('SAPISID') ?? value('__Secure-3PAPISID');
  }

  AuthSession withName(String? name) => AuthSession._(
    cookie,
    displayName: name ?? displayName,
    microgAccount: microgAccount,
  );

  Map<String, dynamic> toJson() => {
    'cookie': cookie,
    'displayName': ?displayName,
    'microgAccount': ?microgAccount,
  };

  static AuthSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final cookie = json['cookie'];
    return cookie is String
        ? fromCookieHeader(
            cookie,
            displayName: json['displayName'] as String?,
            microgAccount: json['microgAccount'] as String?,
          )
        : null;
  }
}
