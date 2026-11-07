import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show appFlavor;
import 'package:http/http.dart' as http;
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/features/microg/data/account_auth.dart';
import 'package:looper_player/features/online/data/online_settings.dart';

/// Online streaming ships only outside the Play build (personal use; it
/// talks to YouTube's private API). Desktop builds have no flavor. Widget
/// tests never reach the network.
final bool onlineAvailable =
    appFlavor != 'play' && !Platform.environment.containsKey('FLUTTER_TEST');

/// One InnerTube client identity. A stream URL is bound to the client that
/// resolved it (`c=` on the URL), so fetches send that client's User-Agent.
class PlayerClient {
  const PlayerClient(
    this.name,
    this.version,
    this.id,
    this.userAgent,
    this.fields, {
    this.sendsNonce = false,
  });
  final String name;
  final String version;
  final int id;
  final String userAgent;
  final Map<String, Object> fields;
  final bool sendsNonce;
}

/// Client constants, copied from Koda (verified Sept-Oct 2026). YouTube
/// rejects old versions after a few months: HTTP 400 on browse is the sign.
abstract final class InnerTubeClients {
  static const apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const webVersion = '2.20260903.01.00';
  static const remixVersion = '1.20260901.12.00';
  static const browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const visionOs = PlayerClient(
    'VISIONOS',
    '1.02',
    101,
    'com.google.visionos.youtube/1.02(RealityDevice14,1; U; CPU visionOS '
        '25_6_0 like Mac OS X; GB)',
    {
      'clientScreen': 'WATCH',
      'platform': 'MOBILE',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice14,1',
      'osName': 'visionOS',
      'osVersion': '25.6.0.23O471',
    },
    sendsNonce: true,
  );

  static const androidVr = PlayerClient(
    'ANDROID_VR',
    '1.65.10',
    28,
    'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android '
        '12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {
      'androidSdkVersion': 32,
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
    },
  );

  static const ios = PlayerClient(
    'IOS',
    '21.02.3',
    5,
    'com.google.ios.youtube/21.02.3 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)',
    {
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.1.0.22B83',
    },
  );

  /// The User-Agent a fetch of [url] must send, from its `c=` client.
  static String userAgentFor(String url) {
    final c = Uri.tryParse(url)?.queryParameters['c']?.toUpperCase();
    return switch (c) {
      'VISIONOS' => visionOs.userAgent,
      'ANDROID_VR' => androidVr.userAgent,
      'IOS' => ios.userAgent,
      _ => browserUa,
    };
  }
}

class InnerTubeException implements Exception {
  InnerTubeException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => 'InnerTubeException($status): $message';
}

/// Thrown for background work while YouTube asked us to slow down (429).
class OnlineHoldException implements Exception {
  @override
  String toString() => 'Online requests are on hold (rate limited)';
}

class StreamUnavailableException implements Exception {
  StreamUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The shared InnerTube transport: one HTTP client, the visitor identity
/// (YouTube's anti-bot id, sent on every call) and the 429 hold.
class InnerTube {
  InnerTube._();
  static final instance = InnerTube._();

  static const _storeKey = 'online_visitor';
  static const _visitorTtl = Duration(hours: 6);
  static const _timeout = Duration(seconds: 20);

  http.Client client = http.Client();
  void Function()? onHoldChanged;
  final _random = Random.secure();

  String? _visitor;
  DateTime? _visitorAt;
  bool vetted = false;
  bool _loaded = false;
  Future<String>? _minting;
  final _replacements = <DateTime>[];
  DateTime? _holdUntil;

  String get _country {
    final parts = Platform.localeName.split(RegExp('[_.-]'));
    return parts.length > 1 && parts[1].length == 2
        ? parts[1].toUpperCase()
        : 'US';
  }

  String get _language => Platform.localeName.split(RegExp('[_.-]')).first;

  /// The visitor id that signed the most recent call, without minting.
  String? get currentVisitor => _visitor;

  bool get onHold => _holdUntil != null && DateTime.now().isBefore(_holdUntil!);

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await LocalJsonStore.read(_storeKey);
    if (raw is Map) {
      _visitor = raw['vd'] as String?;
      _visitorAt = DateTime.tryParse(raw['at'] as String? ?? '');
      vetted = raw['vetted'] == true;
    }
  }

  Future<void> _save() => LocalJsonStore.write(_storeKey, {
    'vd': _visitor,
    'at': _visitorAt?.toIso8601String(),
    'vetted': vetted,
  });

  /// The current visitor id, minting one when missing or older than 6h.
  Future<String> visitorData() async {
    if (!OnlineSettingsNotifier.current.enabled) {
      throw StreamUnavailableException('online music is turned off');
    }
    await _load();
    final at = _visitorAt;
    if (_visitor != null &&
        at != null &&
        DateTime.now().difference(at) < _visitorTtl) {
      return _visitor!;
    }
    return _minting ??= _mint().whenComplete(() => _minting = null);
  }

  Future<String> _mint() async {
    final res = await client
        .post(
          Uri.parse(
            'https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false',
          ),
          headers: {
            'User-Agent': InnerTubeClients.browserUa,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': InnerTubeClients.webVersion,
                'hl': 'en',
                'gl': _country,
              },
            },
          }),
        )
        .timeout(_timeout);
    final vd =
        (jsonDecode(res.body) as Map?)?['responseContext']?['visitorData'];
    if (res.statusCode != 200 || vd is! String || vd.isEmpty) {
      throw InnerTubeException(
        'visitor_id mint failed',
        status: res.statusCode,
      );
    }
    _visitor = vd;
    _visitorAt = DateTime.now();
    vetted = false;
    await _save();
    return vd;
  }

  /// Replace the visitor id after a refusal. [signedBy] is the id that
  /// signed the refused URL: if it was already replaced, keep the current
  /// one, so two refusals arriving together mint once. At most 4 new ids
  /// per 10 minutes.
  Future<String> replaceVisitor({String? signedBy}) async {
    if (!OnlineSettingsNotifier.current.enabled) {
      throw StreamUnavailableException('online music is turned off');
    }
    await _load();
    if (signedBy != null && _visitor != null && signedBy != _visitor) {
      return _visitor!;
    }
    if (_minting != null) return _minting!;
    final now = DateTime.now();
    _replacements.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 10),
    );
    if (_replacements.length >= 4) {
      throw InnerTubeException('visitor replacement budget used up');
    }
    _replacements.add(now);
    return _minting ??= _mint().whenComplete(() => _minting = null);
  }

  Future<void> markVetted() async {
    vetted = true;
    await _save();
  }

  /// The Refresh button: forget the identity and the hold so the next
  /// request starts clean.
  Future<void> reset() async {
    await _load();
    _visitor = null;
    _visitorAt = null;
    vetted = false;
    _holdUntil = null;
    _replacements.clear();
    await _save();
    onHoldChanged?.call();
  }

  void _noteStatus(http.Response res) {
    if (res.statusCode != 429) return;
    final retry = int.tryParse(res.headers['retry-after'] ?? '') ?? 300;
    final until = DateTime.now().add(Duration(seconds: retry.clamp(30, 1800)));
    // A second 429 can only lengthen the hold.
    if (_holdUntil == null || until.isAfter(_holdUntil!)) {
      _holdUntil = until;
      onHoldChanged?.call();
    }
  }

  /// POST to music.youtube.com as WEB_REMIX, signed in when an account is.
  /// [automatic] marks background work, which is refused during a 429 hold;
  /// user actions always go out.
  Future<Map<String, dynamic>> music(
    String endpoint,
    Map<String, dynamic> body, {
    bool automatic = false,
  }) async {
    if (!OnlineSettingsNotifier.current.enabled) {
      throw StreamUnavailableException('online music is turned off');
    }
    if (automatic && onHold) throw OnlineHoldException();
    final vd = await visitorData();
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': InnerTubeClients.remixVersion,
          'hl': _language,
          'gl': _country,
          'visitorData': vd,
        },
      },
      ...body,
    };
    // Signed in, the account's headers ride along; a 401 gets one retry
    // after the account refreshes its token.
    for (var retried = false; ; retried = true) {
      final auth = await AccountAuth.instance.headers();
      final res = await client
          .post(
            Uri.parse(
              'https://music.youtube.com/youtubei/v1/$endpoint?prettyPrint=false',
            ),
            headers: {
              'User-Agent': InnerTubeClients.browserUa,
              'Content-Type': 'application/json',
              'Origin': 'https://music.youtube.com',
              'X-Goog-Visitor-Id': vd,
              'X-YouTube-Client-Name': '67',
              'X-YouTube-Client-Version': InnerTubeClients.remixVersion,
              ...auth,
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      _noteStatus(res);
      if (res.statusCode == 401 &&
          auth.isNotEmpty &&
          !retried &&
          await AccountAuth.instance.recover()) {
        continue;
      }
      if (res.statusCode != 200) {
        throw InnerTubeException(
          '$endpoint: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}',
          status: res.statusCode,
        );
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
  }

  String _nonce(int n) {
    const abc =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    return String.fromCharCodes(
      List.generate(n, (_) => abc.codeUnitAt(_random.nextInt(abc.length))),
    );
  }

  /// One `/player` call. Returns the decoded body and HTTP status; the
  /// caller decides what the answer means.
  Future<(int, Map<String, dynamic>?)> player(
    String videoId,
    PlayerClient c,
    String visitor,
  ) async {
    if (!OnlineSettingsNotifier.current.enabled) {
      throw StreamUnavailableException('online music is turned off');
    }
    final res = await client
        .post(
          Uri.parse(
            'https://youtubei.googleapis.com/youtubei/v1/player'
            '?key=${InnerTubeClients.apiKey}&prettyPrint=false',
          ),
          headers: {
            'User-Agent': c.userAgent,
            'Content-Type': 'application/json',
            'X-Goog-Api-Format-Version': '2',
            'X-YouTube-Client-Name': '${c.id}',
            'X-YouTube-Client-Version': c.version,
            'Origin': 'https://www.youtube.com',
            'X-Goog-Visitor-Id': visitor,
          },
          body: jsonEncode({
            'videoId': videoId,
            'context': {
              'client': {
                'clientName': c.name,
                'clientVersion': c.version,
                'hl': 'en',
                'gl': _country,
                'utcOffsetMinutes': 0,
                'visitorData': visitor,
                ...c.fields,
              },
            },
            if (c.sendsNonce) 'contentPlaybackNonce': _nonce(16),
            if (c.sendsNonce) 't': _nonce(12),
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(_timeout);
    _noteStatus(res);
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return (res.statusCode, body);
  }
}
