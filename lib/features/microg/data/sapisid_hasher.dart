import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The `Authorization` header music.youtube.com wants with cookie sessions:
/// `SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> <origin>")>`.
abstract final class SapisidHasher {
  static const origin = 'https://music.youtube.com';

  static String generateHeader(String sapisid, {DateTime? now}) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final hash = sha1.convert(utf8.encode('$ts $sapisid $origin'));
    return 'SAPISIDHASH ${ts}_$hash';
  }
}
