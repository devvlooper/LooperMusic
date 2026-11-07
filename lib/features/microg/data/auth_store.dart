import 'dart:convert';
import 'dart:io';

import 'package:looper_player/features/microg/data/auth_session.dart';
import 'package:looper_player/features/microg/data/microg_platform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The saved session, outside LocalJsonStore so it never lands in backups.
/// Android: sealed with an Android Keystore key. Desktop: a file only the
/// user can read.
// shortcut: desktop files are not encrypted (no libsecret / DPAPI); move to
// the OS keyring if desktop sign-in sees real use.
abstract final class AuthStore {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'account_session'));
  }

  static Future<AuthSession?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      var text = await file.readAsString();
      if (Platform.isAndroid) {
        final opened = await MicrogPlatform.open(text);
        if (opened == null) return null;
        text = opened;
      }
      return AuthSession.fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AuthSession session) async {
    final file = await _file();
    final text = jsonEncode(session.toJson());
    if (Platform.isAndroid) {
      await file.writeAsString(await MicrogPlatform.seal(text), flush: true);
      return;
    }
    // Lock the file down before the secret is in it.
    if (!await file.exists()) await file.create(recursive: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
    await file.writeAsString(text, flush: true);
  }

  static Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
