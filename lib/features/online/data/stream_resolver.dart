import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/online_settings.dart';

export 'package:looper_player/features/online/data/innertube.dart'
    show StreamUnavailableException;

/// A playable stream for one song.
class StreamPick {
  StreamPick({
    required this.url,
    required this.userAgent,
    required this.mime,
    required this.bitrate,
    required this.expires,
    required this.source,
    this.itag,
    this.contentLength,
    this.loudnessDb,
  });

  final String url;
  final String userAgent;
  final String mime;
  final int bitrate;
  final int? itag;
  final int? contentLength;

  /// Track loudness above YouTube's -14 LKFS target; null = unknown.
  final double? loudnessDb;
  final DateTime expires;

  /// Which path produced it (visionOS, ANDROID_VR, IOS, yt-dlp).
  final String source;

  bool get valid => DateTime.now().isBefore(expires);
}

/// The video itself cannot be played (removed, region or age blocked).
/// Retrying with another identity does not help.
class UnplayableException implements Exception {
  UnplayableException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

enum OnlineStatus { online, limited, offline }

enum _Answer { playable, refused, unplayable, failed }

/// Video id to playable URL. Chain (docs/online/02-stream-resolution.md):
/// visionOS under our own vetted visitor id, then ANDROID_VR, IOS, and on
/// desktop yt-dlp when installed. Single-flight per song; URLs cached in
/// memory only (a stored URL could carry a refused identity forward).
class StreamResolver {
  StreamResolver._() {
    _it.onHoldChanged = _updateStatus;
  }
  static final instance = StreamResolver._();

  @visibleForTesting
  static Duration resolveBudget = const Duration(seconds: 20);
  static const _maxCached = 128;
  static const _tag = 'StreamResolver';

  final _it = InnerTube.instance;
  final _inflight = <String, Future<StreamPick>>{};
  final _cache = <String, StreamPick>{};

  /// `ei` (one per /player response) -> the visitor id that signed it.
  final _signedBy = <String, String>{};
  DateTime? _botCheckUntil;

  final ValueNotifier<OnlineStatus> statusNotifier =
      ValueNotifier<OnlineStatus>(OnlineStatus.online);

  OnlineStatus get status => statusNotifier.value;

  void _updateStatus([OnlineStatus? override]) {
    if (override != null) {
      statusNotifier.value = override;
      return;
    }
    if (botCheckActive || _it.onHold) {
      statusNotifier.value = OnlineStatus.limited;
    } else {
      statusNotifier.value = OnlineStatus.online;
    }
  }

  bool get botCheckActive =>
      _botCheckUntil != null && DateTime.now().isBefore(_botCheckUntil!);

  /// Resolve [videoId]. [automatic] marks prefetch: refused while YouTube
  /// is throttling us, so the app does not keep poking a refusal.
  Future<StreamPick> resolve(
    String videoId, {
    bool automatic = false,
    OnlineQuality? quality,
    bool preferMp4 = false,
  }) async {
    final q = quality ?? await currentQuality();
    final key = '$videoId:${q.name}${preferMp4 ? ':mp4' : ''}';
    final hit = _cache.remove(key);
    if (hit != null && hit.valid) return _cache[key] = hit;
    if (automatic && (botCheckActive || _it.onHold)) {
      throw OnlineHoldException();
    }
    final running = _inflight[key];
    if (running != null) return running;

    // A timeout does not stop the work; a late answer still lands in the
    // cache for the next caller, but this caller moves on.
    final future =
        (debugResolve?.call(videoId, q, preferMp4) ??
                _resolve(videoId, q, preferMp4: preferMp4))
            .then((pick) {
              _cache[key] = pick;
              while (_cache.length > _maxCached) {
                _cache.remove(_cache.keys.first);
              }
              return pick;
            });
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    }).ignore();
    return future.timeout(resolveBudget);
  }

  /// Tests: replaces the network chain.
  @visibleForTesting
  Future<StreamPick> Function(String id, OnlineQuality q, bool mp4)?
  debugResolve;

  /// Forget cached URLs for [videoId].
  void invalidate(String videoId) =>
      _cache.removeWhere((k, _) => k.startsWith('$videoId:'));

  /// googlevideo refused [url] (403): replace exactly the identity that
  /// signed it and drop the song's cached URLs.
  Future<void> onForbidden(String videoId, String url) async {
    invalidate(videoId);
    final ei = Uri.tryParse(url)?.queryParameters['ei'];
    try {
      await _it.replaceVisitor(signedBy: ei == null ? null : _signedBy[ei]);
    } catch (e) {
      LoggerHelper.write('$_tag: visitor replace failed', e);
    }
  }

  /// The Refresh button.
  Future<void> reset() async {
    _cache.clear();
    _signedBy.clear();
    _botCheckUntil = null;
    await _it.reset();
    _updateStatus();
  }

  Future<StreamPick> _resolve(
    String id,
    OnlineQuality q, {
    bool preferMp4 = false,
  }) async {
    var refusals = 0;

    // 1. visionOS, vetting a fresh identity before trusting it.
    for (var attempt = 0; attempt < 3; attempt++) {
      final String vd;
      try {
        vd = await _it.visitorData();
      } catch (e) {
        LoggerHelper.write('$_tag: visitor mint failed', e);
        break;
      }
      final (answer, body) = await _call(id, InnerTubeClients.visionOs, vd);
      if (answer == _Answer.refused) {
        refusals++;
        try {
          await _it.replaceVisitor(signedBy: vd);
        } catch (_) {
          break;
        }
        continue;
      }
      if (answer != _Answer.playable) break;
      final pick = _pick(
        body!,
        q,
        InnerTubeClients.visionOs,
        vd,
        preferMp4: preferMp4,
      );
      if (pick == null) break;
      if (_it.vetted || await _servesLastByte(pick)) {
        if (!_it.vetted) await _it.markVetted();
        _botCheckUntil = null;
        _updateStatus();
        return pick;
      }
      // About 1 in 10 fresh identities is refused past the opening bytes.
      LoggerHelper.write('$_tag: identity failed the last-byte check');
      try {
        await _it.replaceVisitor(signedBy: vd);
      } catch (_) {
        break;
      }
    }

    // 2. ANDROID_VR then IOS: may stop serving past ~1 MiB, last resort.
    for (final c in [InnerTubeClients.androidVr, InnerTubeClients.ios]) {
      String vd;
      try {
        vd = await _it.visitorData();
      } catch (_) {
        break;
      }
      final (answer, body) = await _call(id, c, vd);
      if (answer == _Answer.refused) refusals++;
      if (answer != _Answer.playable) continue;
      final pick = _pick(body!, q, c, vd, preferMp4: preferMp4);
      if (pick != null) {
        _botCheckUntil = null;
        _updateStatus();
        return pick;
      }
    }

    // 3. yt-dlp on desktop.
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final pick = await _ytDlp(id, q, preferMp4: preferMp4);
      if (pick != null) {
        _botCheckUntil = null;
        _updateStatus();
        return pick;
      }
    }

    if (refusals > 0) {
      _botCheckUntil = DateTime.now().add(const Duration(minutes: 3));
      _updateStatus();
    }
    throw StreamUnavailableException(
      refusals > 0
          ? 'YouTube refused this device for now'
          : 'No playable stream found',
    );
  }

  Future<(_Answer, Map<String, dynamic>?)> _call(
    String id,
    PlayerClient c,
    String vd,
  ) async {
    try {
      final (status, body) = await _it.player(id, c, vd);
      if (status != 200 || body == null) {
        LoggerHelper.write('$_tag: ${c.name} HTTP $status for $id');
        return (_Answer.failed, null);
      }
      final ps = body['playabilityStatus'] as Map?;
      final st = ps?['status'] as String? ?? 'OK';
      if (st == 'LOGIN_REQUIRED') return (_Answer.refused, body);
      if (st != 'OK') {
        final reason = ps?['reason'] as String? ?? st;
        LoggerHelper.write('$_tag: ${c.name} $st for $id: $reason');
        // Only visionOS speaks for the video; other clients' refusals are
        // client quirks, so they fall through to the next path.
        if (identical(c, InnerTubeClients.visionOs)) {
          throw UnplayableException(reason);
        }
        return (_Answer.unplayable, body);
      }
      if (body['streamingData'] is! Map) return (_Answer.refused, body);
      return (_Answer.playable, body);
    } on UnplayableException {
      rethrow;
    } catch (e) {
      LoggerHelper.write('$_tag: ${c.name} call failed for $id', e);
      return (_Answer.failed, null);
    }
  }

  StreamPick? _pick(
    Map<String, dynamic> body,
    OnlineQuality q,
    PlayerClient c,
    String vd, {
    bool preferMp4 = false,
  }) {
    final sd = body['streamingData'] as Map;
    final adaptive = [
      for (final f in (sd['adaptiveFormats'] as List? ?? const []))
        if (f is Map &&
            (f['mimeType'] as String? ?? '').startsWith('audio/') &&
            (f['url'] as String? ?? '').isNotEmpty)
          f,
    ];
    // Dubbed videos carry several audio tracks: keep the original.
    final original = adaptive
        .where((f) => (f['audioTrack'] as Map?)?['audioIsDefault'] != false)
        .toList();
    final allAudio = original.isEmpty ? adaptive : original;

    final audio = preferMp4
        ? (allAudio.where((f) {
            final m = (f['mimeType'] as String? ?? '').toLowerCase();
            return m.contains('mp4') || m.contains('m4a') || m.contains('aac');
          }).toList())
        : allAudio;
    final candidates = audio.isNotEmpty ? audio : allAudio;
    int br(Map f) => f['bitrate'] as int? ?? 0;

    Map? chosen;
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => br(a).compareTo(br(b)));
      chosen = switch (q) {
        OnlineQuality.low => candidates.first,
        OnlineQuality.high => candidates.last,
        OnlineQuality.normal => candidates.reduce(
          (a, b) => (br(a) - 128000).abs() <= (br(b) - 128000).abs() ? a : b,
        ),
      };
    } else {
      // A muxed file's audio track, never a video-only adaptive format.
      final muxed = [
        for (final f in (sd['formats'] as List? ?? const []))
          if (f is Map && (f['url'] as String? ?? '').isNotEmpty) f,
      ]..sort((a, b) => br(a).compareTo(br(b)));
      chosen = muxed.firstOrNull;
    }
    if (chosen == null) return null;

    final url = chosen['url'] as String;
    final params = Uri.parse(url).queryParameters;
    final ei = params['ei'];
    if (ei != null) {
      _signedBy[ei] = vd;
      while (_signedBy.length > 512) {
        _signedBy.remove(_signedBy.keys.first);
      }
    }
    final expireSecs = int.tryParse(params['expire'] ?? '');
    final expires = expireSecs == null
        ? DateTime.now().add(const Duration(minutes: 15))
        : DateTime.fromMillisecondsSinceEpoch(
            expireSecs * 1000,
          ).subtract(const Duration(minutes: 5));
    return StreamPick(
      url: url,
      userAgent: c.userAgent,
      mime: chosen['mimeType'] as String? ?? 'audio/mp4',
      bitrate: br(chosen),
      itag: chosen['itag'] as int?,
      contentLength:
          int.tryParse('${chosen['contentLength'] ?? params['clen'] ?? ''}'),
      loudnessDb: (chosen['loudnessDb'] as num?)?.toDouble(),
      expires: expires,
      source: c.name,
    );
  }

  /// A refused identity serves the opening bytes and 403s the rest, so ask
  /// for the very last byte.
  Future<bool> _servesLastByte(StreamPick pick) async {
    final len = pick.contentLength;
    if (len == null || len < 2) return true;
    try {
      final res = await _it.client
          .get(
            Uri.parse(pick.url),
            headers: {
              'User-Agent': pick.userAgent,
              'Range': 'bytes=${len - 1}-${len - 1}',
            },
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode != 403;
    } catch (_) {
      return true; // Unknown is not a refusal; playback recovery backs it up.
    }
  }

  Future<StreamPick?> _ytDlp(
    String id,
    OnlineQuality q, {
    bool preferMp4 = false,
  }) async {
    final format = preferMp4
        ? switch (q) {
            OnlineQuality.high => 'bestaudio[ext=m4a]/bestaudio',
            OnlineQuality.normal =>
              'bestaudio[ext=m4a][abr<=140]/bestaudio[ext=m4a]/bestaudio',
            OnlineQuality.low => 'worstaudio[ext=m4a]/worstaudio',
          }
        : switch (q) {
            OnlineQuality.high => 'bestaudio',
            OnlineQuality.normal => 'bestaudio[abr<=140]/bestaudio',
            OnlineQuality.low => 'worstaudio',
          };
    try {
      final r = await Process.run('yt-dlp', [
        '-j',
        '--no-warnings',
        '--no-playlist',
        '-f',
        format,
        'https://music.youtube.com/watch?v=$id',
      ], runInShell: Platform.isWindows).timeout(const Duration(seconds: 25));
      if (r.exitCode != 0) {
        LoggerHelper.write('$_tag: yt-dlp failed: ${r.stderr}');
        return null;
      }
      final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      final url = j['url'] as String?;
      if (url == null) return null;
      final expire = int.tryParse(
        Uri.parse(url).queryParameters['expire'] ?? '',
      );
      return StreamPick(
        url: url,
        userAgent:
            (j['http_headers'] as Map?)?['User-Agent'] as String? ??
            InnerTubeClients.userAgentFor(url),
        mime: 'audio/${j['ext'] ?? 'webm'}',
        bitrate: (((j['abr'] as num?) ?? 0) * 1000).round(),
        itag: int.tryParse('${j['format_id']}'),
        contentLength: (j['filesize'] as num?)?.toInt(),
        expires: expire == null
            ? DateTime.now().add(const Duration(minutes: 15))
            : DateTime.fromMillisecondsSinceEpoch(
                expire * 1000,
              ).subtract(const Duration(minutes: 5)),
        source: 'yt-dlp',
      );
    } catch (e) {
      // Not installed, or timed out.
      LoggerHelper.write('$_tag: yt-dlp unavailable', e);
      return null;
    }
  }
}

/// A ranged GET helper shared by the cache.
Future<http.StreamedResponse> rangedGet(
  StreamPick pick,
  int start,
  int end,
) {
  final req = http.Request('GET', Uri.parse(pick.url))
    ..headers['User-Agent'] = pick.userAgent
    ..headers['Range'] = 'bytes=$start-$end';
  return InnerTube.instance.client.send(req);
}
