import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';
import 'package:looper_player/features/playback/data/lyrics_fetcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

extension OnlineSongPath on Song {
  bool get isOnline => path.startsWith('yt:');
  String? get videoId => isOnline ? path.substring(3) : null;
}

/// Whole-song audio cache. A song is fetched in bounded ranges (open-ended
/// googlevideo requests are throttled) into `<id>.partial`, then renamed,
/// so a file with the final name is always complete and plays offline.
/// Least recently played files are evicted past the size limit.
class OnlineCache {
  OnlineCache._() {
    unawaited(_init());
  }
  static final instance = OnlineCache._();

  static const _chunk = 2 * 1024 * 1024;
  static const _exts = ['m4a', 'webm'];
  static const _tag = 'OnlineCache';

  Future<Directory>? _dir;
  final _downloads = <String, Future<String?>>{};
  final _cachedIds = <String>{};

  // One shared future, so the partial cleanup runs once, before any download.
  Future<Directory> _directory() => _dir ??= _init();

  @visibleForTesting
  static void resetForTesting() {
    instance._dir = null;
    instance._cachedIds.clear();
    instance._downloads.clear();
  }

  Future<Directory> _init() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, 'online_audio'));
    await dir.create(recursive: true);
    // Partials left by a killed process have no download to finish them.
    try {
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          if (f.path.endsWith('.partial')) {
            try {
              await f.delete();
            } catch (_) {}
          } else if (f is File) {
            final name = p.basename(f.path);
            for (final ext in _exts) {
              if (name.endsWith('.$ext')) {
                _cachedIds.add(p.basenameWithoutExtension(name));
              }
            }
          }
        }
      }
    } catch (_) {}
    return dir;
  }

  /// Whether [videoId] is known to be cached locally.
  bool isCached(String videoId) => _cachedIds.contains(videoId);

  /// The complete cached file for [videoId], or null. [mp4Only] ignores a
  /// WebM copy (downloads must be M4A to take tags). Touching it marks it
  /// recently used.
  Future<String?> cachedPath(String videoId, {bool mp4Only = false}) async {
    final dir = await _directory();
    for (final ext in mp4Only ? const ['m4a'] : _exts) {
      final f = File(p.join(dir.path, '$videoId.$ext'));
      if (await f.exists()) {
        try {
          await f.setLastModified(DateTime.now());
        } catch (_) {}
        return f.path;
      }
    }
    return null;
  }

  bool isDownloading(String videoId) =>
      _downloads.keys.any((k) => k == videoId || k == '$videoId:mp4');

  /// Download [videoId] whole. Single-flight per (song, format); returns the
  /// file path or null. [mp4Only] asks for an M4A file and never returns a
  /// WebM one; [quality] is kept when a refused URL is fetched again.
  Future<String?> download(
    String videoId, {
    Song? song,
    StreamPick? pick,
    bool automatic = true,
    bool mp4Only = false,
    OnlineQuality? quality,
    void Function(double progress)? onProgress,
  }) {
    final key = mp4Only ? '$videoId:mp4' : videoId;
    return _downloads[key] ??= _download(
      videoId,
      song,
      pick,
      automatic,
      mp4Only: mp4Only,
      quality: quality,
      onProgress: onProgress,
    ).whenComplete(() {
      // A block, not `=>`: remove() returns this same future, and
      // whenComplete would wait on it forever.
      _downloads.remove(key);
    });
  }

  void _fetchLyricsFor(String videoId, Song? song) {
    unawaited(() async {
      try {
        final s = song ??
            await DbService.isar.songs
                .filter()
                .pathEqualTo('yt:$videoId')
                .findFirst();
        if (s != null) {
          await LyricsFetcher.fetchLyrics(s);
        }
      } catch (_) {}
    }());
  }

  static bool _isMp4(StreamPick pick) {
    final m = pick.mime.toLowerCase();
    return !m.contains('webm') &&
        (m.contains('mp4') || m.contains('m4a') || m.contains('aac'));
  }

  Future<String?> _download(
    String videoId,
    Song? song,
    StreamPick? given,
    bool automatic, {
    bool mp4Only = false,
    OnlineQuality? quality,
    void Function(double progress)? onProgress,
  }) async {
    final existing = await cachedPath(videoId, mp4Only: mp4Only);
    if (existing != null) {
      _fetchLyricsFor(videoId, song);
      return existing;
    }
    final dir = await _directory();
    // One partial per format, so a playback cache and an M4A download of
    // the same song never write into the same file.
    final partial = File(
      p.join(dir.path, '$videoId.${mp4Only ? 'mp4' : 'any'}.partial'),
    );
    IOSink? sink;
    Future<StreamPick> fresh() => StreamResolver.instance.resolve(
      videoId,
      automatic: automatic,
      quality: quality,
      preferMp4: mp4Only,
    );
    try {
      var pick = given ?? await fresh();
      if (mp4Only && !_isMp4(pick)) {
        throw const FormatException('no M4A stream for this song');
      }
      sink = partial.openWrite();
      var pos = 0;
      int? total = pick.contentLength;
      var retried403 = false;
      while (total == null || pos < total) {
        // Switching online music off stops downloads (cached files stay).
        if (!OnlineSettingsNotifier.current.enabled) {
          throw StreamUnavailableException('online music is turned off');
        }
        final end = total == null
            ? pos + _chunk - 1
            : math.min(pos + _chunk, total) - 1;
        final res = await rangedGet(
          pick,
          pos,
          end,
        ).timeout(const Duration(seconds: 30));
        if (res.statusCode == 403 && !retried403) {
          // Identity refused mid-file: fresh identity, fresh URL, same byte.
          retried403 = true;
          await res.stream.drain<void>();
          await StreamResolver.instance.onForbidden(videoId, pick.url);
          final next = await fresh();
          if (mp4Only && !_isMp4(next)) {
            throw const FormatException('no M4A stream for this song');
          }
          if (next.itag != pick.itag || next.mime != pick.mime) {
            // Another rendition: its bytes never continue the old file.
            await sink?.close();
            sink = partial.openWrite();
            pos = 0;
            total = next.contentLength;
          }
          pick = next;
          continue;
        }
        if (res.statusCode != 206 && res.statusCode != 200) {
          await res.stream.drain<void>();
          throw HttpException('HTTP ${res.statusCode}');
        }
        if (res.statusCode == 200 && pos > 0) {
          // The server ignored the range and resent the whole file.
          await res.stream.drain<void>();
          throw const HttpException('server ignored the byte range');
        }
        total ??= int.tryParse(
          res.headers['content-range']?.split('/').last ?? '',
        );
        var got = 0;
        await for (final bytes in res.stream.timeout(
          const Duration(seconds: 30),
        )) {
          sink!.add(bytes);
          got += bytes.length;
        }
        if (got == 0) break;
        pos += got;
        if (total != null && total > 0) {
          onProgress?.call((pos / total).clamp(0.0, 1.0));
        }
        if (total == null) break; // Server ignored the range: whole file.
      }
      await sink!.close();
      sink = null;
      if (total != null && pos < total) {
        throw HttpException('incomplete: $pos of $total');
      }
      final ext = pick.mime.contains('webm') ? 'webm' : 'm4a';
      final done = await partial.rename(p.join(dir.path, '$videoId.$ext'));
      _cachedIds.add(videoId);
      _fetchLyricsFor(videoId, song);
      unawaited(_evict());
      return done.path;
    } catch (e) {
      LoggerHelper.write('$_tag: download of $videoId failed', e);
      await sink?.close();
      try {
        await partial.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Preload the next online songs so skips start from disk.
  Future<void> prefetch(Iterable<Song> upcoming) async {
    final s = OnlineSettingsNotifier.current;
    if (!s.enabled || !s.preload) return;
    if (!s.preloadOnMobile && await isNetworkMetered()) return;
    final ids = upcoming
        .map((x) => x.videoId)
        .whereType<String>()
        .take(3)
        .toList();
    for (final id in ids) {
      // One at a time: the current song's stream should keep the bandwidth.
      await download(id);
    }
  }

  Future<int> sizeBytes() async {
    var total = 0;
    final dir = await _directory();
    await for (final f in dir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<void> clear() async {
    final dir = await _directory();
    await for (final f in dir.list()) {
      final name = p.basename(f.path);
      if (_downloads.keys.any((k) => name.startsWith(k.split(':').first))) {
        continue;
      }
      try {
        await f.delete();
        _cachedIds.remove(p.basenameWithoutExtension(name));
      } catch (_) {}
    }
  }

  Future<void> _evict() => evict();

  /// Evicts files exceeding cache limit. Protects favourites and songs played
  /// 3+ times unless cache is over 120% of limit.
  Future<void> evict() async {
    final limit = OnlineSettingsNotifier.current.cacheLimitMB * 1024 * 1024;
    final dir = await _directory();
    final files = <(File, int, DateTime, String)>[];
    var total = 0;
    await for (final f in dir.list()) {
      if (f is! File || f.path.endsWith('.partial')) continue;
      final stat = await f.stat();
      final videoId = p.basenameWithoutExtension(f.path);
      files.add((f, stat.size, stat.modified, videoId));
      total += stat.size;
    }
    if (total <= limit) return;

    final protectedIds = <String>{};
    try {
      final isar = DbService.isar;
      final protectedSongs = await isar.songs
          .filter()
          .pathStartsWith('yt:')
          .and()
          .group((q) => q.isFavoriteEqualTo(true).or().playCountGreaterThan(2))
          .findAll();
      for (final s in protectedSongs) {
        final id = s.videoId;
        if (id != null) protectedIds.add(id);
      }
    } catch (_) {}

    files.sort((a, b) => a.$3.compareTo(b.$3));

    final deleted = <String>{};
    // Pass 1: Evict files whose videoId is NOT protected until total <= limit.
    for (final (f, size, _, id) in files) {
      if (total <= limit) break;
      if (protectedIds.contains(id)) continue;
      try {
        await f.delete();
        deleted.add(id);
        _cachedIds.remove(id);
        total -= size;
      } catch (_) {}
    }

    // Pass 2: If still over 120% of limit, evict protected files until <= 120%.
    final hardLimit = (limit * 1.2).toInt();
    if (total > hardLimit) {
      for (final (f, size, _, id) in files) {
        if (total <= hardLimit) break;
        if (deleted.contains(id)) continue;
        try {
          await f.delete();
          deleted.add(id);
          _cachedIds.remove(id);
          total -= size;
        } catch (_) {}
      }
    }
  }
}
