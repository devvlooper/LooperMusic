import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

/// Thrown by [BackupCrypto.decrypt] for a wrong password or a damaged file.
class BackupPasswordException implements Exception {
  const BackupPasswordException();
}

/// Password lock for a backup that carries the signed-in account:
/// PBKDF2-HMAC-SHA256 derives an AES-256-GCM key, so a wrong password or a
/// changed byte fails the GCM tag instead of yielding garbage.
abstract final class BackupCrypto {
  static const marker = 'looperEncryptedBackup';
  static const _iterations = 310000;

  static bool isEncrypted(Object? json) => json is Map && json[marker] == 1;

  static Pbkdf2 _kdf(int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  /// The encrypted envelope for [plaintext], as JSON-ready fields.
  static Future<Map<String, Object>> encrypt(
    String plaintext,
    String password,
  ) => Isolate.run(() async {
    final aes = AesGcm.with256bits();
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _kdf(
      _iterations,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final box = await aes.encrypt(utf8.encode(plaintext), secretKey: key);
    return {
      marker: 1,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'cipher': 'aes-256-gcm',
      'salt': base64.encode(salt),
      'nonce': base64.encode(box.nonce),
      'data': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    };
  });

  /// The plaintext of an [encrypt] envelope. Throws
  /// [BackupPasswordException] when [password] is wrong.
  static Future<String> decrypt(Map envelope, String password) =>
      Isolate.run(() async {
        try {
          final iterations = envelope['iterations'];
          // A crafted file must not stall decryption for hours.
          if (iterations is! int || iterations < 1 || iterations > 5000000) {
            throw const BackupPasswordException();
          }
          final key = await _kdf(iterations).deriveKeyFromPassword(
            password: password,
            nonce: base64.decode(envelope['salt'] as String),
          );
          final clear = await AesGcm.with256bits().decrypt(
            SecretBox(
              base64.decode(envelope['data'] as String),
              nonce: base64.decode(envelope['nonce'] as String),
              mac: Mac(base64.decode(envelope['mac'] as String)),
            ),
            secretKey: key,
          );
          return utf8.decode(clear);
        } on SecretBoxAuthenticationError {
          throw const BackupPasswordException();
        } on FormatException {
          throw const BackupPasswordException();
        }
      });
}
