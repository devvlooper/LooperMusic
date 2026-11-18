import 'dart:io';

import 'package:flutter/services.dart';

/// Which GmsCore build is installed (Android only).
class MicrogInfo {
  const MicrogInfo(this.variant, {this.accountType});

  /// `revanced`, `microg`, `vanced`, `playServices` or `none`.
  final String variant;
  final String? accountType;

  /// A GmsCore that can hand Looper a YouTube token.
  bool get usable => accountType != null;
}

/// The `com.looper.player/microg` channel (MicrogAuth.kt). Never logs
/// tokens or cookies.
abstract final class MicrogPlatform {
  static const _channel = MethodChannel('com.looper.player/microg');

  /// A one-time link that signs a browser into Google and lands on YouTube
  /// Music. Bearer tokens are refused by music.youtube.com's web API (HTTP
  /// 400 on a live test, November 2026), so microG sign-in ends in cookies.
  static const _weblogin =
      'weblogin:service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F';

  static Future<MicrogInfo> detect() async {
    if (!Platform.isAndroid) return const MicrogInfo('none');
    try {
      final r = await _channel.invokeMapMethod<String, String?>('detect');
      return MicrogInfo(
        r?['variant'] ?? 'none',
        accountType: r?['accountType'],
      );
    } on PlatformException {
      return const MicrogInfo('none');
    } on MissingPluginException {
      return const MicrogInfo('none');
    }
  }

  /// The system account picker for [type]; null when cancelled.
  static Future<String?> chooseAccount(String type) =>
      _channel.invokeMethod<String>('chooseAccount', {'type': type});

  /// A web sign-in link for the account. GmsCore may first show its own
  /// approval dialogs.
  static Future<String> webloginUrl(String name, String type) async {
    final r = await _channel.invokeMapMethod<String, Object?>('token', {
      'name': name,
      'type': type,
      'scope': _weblogin,
    });
    final url = r?['token'];
    if (url is String && url.startsWith('https://')) return url;
    throw MicrogException('${r?['error'] ?? 'GmsCore gave no sign-in link'}');
  }

  /// The WebView cookie store's `Cookie` header for [url].
  static Future<String?> webCookies(String url) =>
      _channel.invokeMethod<String>('webCookies', {'url': url});

  static Future<void> clearWebCookies() async {
    if (Platform.isAndroid) await _channel.invokeMethod('clearWebCookies');
  }

  /// Android Keystore AES-GCM.
  static Future<String> seal(String text) async =>
      (await _channel.invokeMethod<String>('seal', {'text': text}))!;

  /// Null when the key is gone; the session is then lost.
  static Future<String?> open(String text) =>
      _channel.invokeMethod<String>('open', {'text': text});
}

class MicrogException implements Exception {
  MicrogException(this.message);
  final String message;
  @override
  String toString() => message;
}
