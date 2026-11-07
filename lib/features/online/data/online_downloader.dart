import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/library/data/services/artist_catalog.dart';
import 'package:looper_player/features/library/data/scanner/scanner.dart';
import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/online_cache.dart';
import 'package:looper_player/features/online/data/online_playback.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';
import 'package:looper_player/features/playback/data/lyrics_cache.dart';
import 'package:looper_player/features/playback/data/lyrics_fetcher.dart';
import 'package:isar_community/isar.dart';

String sanitizeFileName(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (cleaned.isEmpty || cleaned.replaceAll('_', '').trim().isEmpty) {
    return 'Unknown';
  }
  return cleaned;
}

String getTargetFileName(String artist, String title) {
  final cleanArtist = sanitizeFileName(artist.isEmpty ? 'Unknown Artist' : artist);
  final cleanTitle = sanitizeFileName(title.isEmpty ? 'Unknown Title' : title);
  return '$cleanArtist - $cleanTitle.m4a';
}

File resolveUniqueFile(Directory dir, String baseName) {
  var file = File(p.join(dir.path, baseName));
  if (!file.existsSync()) return file;

  final ext = p.extension(baseName);
  final name = p.basenameWithoutExtension(baseName);
  var counter = 2;
  while (true) {
    file = File(p.join(dir.path, '$name ($counter)$ext'));
    if (!file.existsSync()) return file;
    counter++;
  }
}

extension SongToOnlineSong on Song {
  OnlineSong toOnlineSong() => OnlineSong(
    videoId: videoId ?? (path.startsWith('yt:') ? path.substring(3) : ''),
    title: title,
    artist: artist,
    album: album,
    durationMs: duration,
    thumbnail: artPath,
  );
}

enum DownloadStatus { queued, downloading, completed, failed }

class DownloadItem {
  const DownloadItem({
    required this.song,
    required this.status,
    this.progress = 0.0,
    this.error,
  });

  final OnlineSong song;
  final DownloadStatus status;
  final double progress;
  final String? error;

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
  }) => DownloadItem(
    song: song,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    error: error ?? this.error,
  );
}

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, Map<String, DownloadItem>>(
  DownloadsNotifier.new,
);

class DownloadsNotifier extends Notifier<Map<String, DownloadItem>> {
  static const _maxConcurrent = 2;
  static const _tag = 'OnlineDownloader';

  final _queue = <String>[];
  final _active = <String>{};

  @override
  Map<String, DownloadItem> build() => {};

  Future<void> enqueue(OnlineSong song) async {
    final id = song.videoId;
    if (state.containsKey(id) &&
        (state[id]!.status == DownloadStatus.downloading ||
            state[id]!.status == DownloadStatus.queued)) {
      return;
    }

    final item = DownloadItem(song: song, status: DownloadStatus.queued);
    state = {...state, id: item};
    _queue.add(id);
    _pumpQueue();
  }

  Future<void> enqueueAll(List<OnlineSong> songs) async {
    for (final song in songs) {
      await enqueue(song);
    }
  }

  void cancel(String id) {
    _queue.remove(id);
    _active.remove(id);
    state = Map.from(state)..remove(id);
    _pumpQueue();
  }

  /// Online music switched off: stop everything that has not finished.
  void cancelAll() {
    for (final id in [
      for (final e in state.entries)
        if (e.value.status == DownloadStatus.queued ||
            e.value.status == DownloadStatus.downloading)
          e.key,
    ]) {
      cancel(id);
    }
  }

  void clearFailed() {
    state = {
      for (final e in state.entries)
        if (e.value.status != DownloadStatus.failed) e.key: e.value,
    };
  }

  void _pumpQueue() {
    while (_active.length < _maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final item = state[id];
      if (item != null && item.status == DownloadStatus.queued) {
        _active.add(id);
        state = {
          ...state,
          id: item.copyWith(status: DownloadStatus.downloading, progress: 0.1),
        };
        unawaited(_executeDownload(item.song));
      }
    }
  }

  /// Reads tags and covers of new library rows (the scanner's pass 2).
  @visibleForTesting
  static Future<void> Function() enrichLibrary = () =>
      LibraryScanner().enrichPendingSongs();

  static Future<OnlineSong?> _details(String id) async {
    try {
      return await OnlineApi.details(id).timeout(const Duration(seconds: 10));
    } catch (e) {
      LoggerHelper.write('$_tag: song details failed', e);
      return null;
    }
  }

  /// Kept with the scanner's covers, so the library shows it at once.
  static Future<String?> _saveCover(String id, Cover cover) async {
    try {
      final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'album_art'),
      );
      await dir.create(recursive: true);
      final ext = cover.mimeType == 'image/png' ? 'png' : 'jpg';
      final file = File(p.join(dir.path, 'online_$id.$ext'));
      await file.writeAsBytes(cover.bytes);
      return file.path;
    } catch (e) {
      LoggerHelper.write('$_tag: cover save failed', e);
      return null;
    }
  }

  /// Updates [id]'s entry only while it is still wanted (not cancelled).
  void _set(String id, DownloadItem Function(DownloadItem) change) {
    final item = state[id];
    if (item == null || !_active.contains(id)) return;
    state = {...state, id: change(item)};
  }

  Future<void> _executeDownload(OnlineSong song) async {
    final id = song.videoId;
    File? partialFile;
    bool cancelled() => !_active.contains(id);

    try {
      final settings = OnlineSettingsNotifier.current;
      final dir = await getDownloadDirectory();

      final baseName = getTargetFileName(song.artist ?? '', song.title);
      final finalFile = resolveUniqueFile(dir, baseName);
      partialFile = File('${finalFile.path}.partial');

      _set(id, (i) => i.copyWith(progress: 0.15));

      // Only an M4A takes tags, so a WebM copy in the cache is not reused.
      final downloadedPath = await OnlineCache.instance.download(
        id,
        song: song.toSong(),
        automatic: false,
        mp4Only: true,
        quality: settings.downloadQuality,
        onProgress: (p) => _set(id, (i) => i.copyWith(progress: 0.15 + p * 0.65)),
      );
      if (downloadedPath == null || !await File(downloadedPath).exists()) {
        throw Exception('no M4A stream could be downloaded');
      }
      if (cancelled()) return;
      await File(downloadedPath).copy(partialFile.path);
      if (cancelled()) return;

      _set(id, (i) => i.copyWith(progress: 0.8));

      // Fuller credits: album tracks name their album and year in `next`.
      final isar = DbService.isar;
      final onlineRow = await isar.songs
          .filter()
          .pathEqualTo('yt:$id')
          .findFirst();
      final info = mergeDownloadInfo(
        song,
        await _details(id),
        onlineRow,
      );

      var lyrics = onlineRow?.lyrics;
      if (lyrics == null || lyrics.isEmpty || lyrics == LyricsFetcher.notFound) {
        final s = onlineRow ?? song.toSong();
        lyrics = await LyricsCache.get(
          LyricsFetcher.cleanArtist(s),
          LyricsFetcher.cleanTitle(s),
        );
        if (lyrics == LyricsFetcher.notFound) lyrics = null;
      }

      final cover = await downloadCover(id, info.thumbnail);
      final artPath = cover == null ? null : await _saveCover(id, cover);

      if (cancelled()) return;
      await partialFile.rename(finalFile.path);
      partialFile = null;

      // Tagged after the rename: the tagger detects the format by extension.
      try {
        await MetadataGod.writeMetadata(
          file: finalFile.path,
          metadata: Metadata(
            title: info.title,
            artist: info.artist,
            albumArtist: info.artist,
            album: info.album,
            year: info.year,
            picture: cover == null
                ? null
                : Picture(data: cover.bytes, mimeType: cover.mimeType),
          ),
        );
      } catch (e) {
        LoggerHelper.write('$_tag: tag write failed', e);
      }

      // Into the library at once; the scanner's second pass then reads the
      // tags like any local file (album and artist entries, cover).
      final newSong = Song()
        ..path = finalFile.path
        ..title = info.title
        ..artist = info.artist
        ..album = info.album
        ..year = info.year
        ..artPath = artPath
        ..lyrics = lyrics
        ..duration = info.durationMs
        ..needsEnrichment = true
        ..dateAdded = DateTime.now();

      await isar.writeTxn(() async {
        await isar.songs.put(newSong);
        await ArtistCatalog.syncInTxn();
      });
      await DownloadFolders.remember(dir.path);
      unawaited(
        enrichLibrary().catchError(
          (Object e) => LoggerHelper.write('$_tag: library read failed', e),
        ),
      );

      if (Platform.isAndroid) {
        try {
          await const MethodChannel('com.looper.player/broadcast')
              .invokeMethod('rescanMedia', {'path': finalFile.path});
        } catch (_) {}
      }

      _set(
        id,
        (i) => i.copyWith(status: DownloadStatus.completed, progress: 1.0),
      );
    } catch (e) {
      LoggerHelper.write('$_tag: download failed for ${song.title}', e);
      _set(
        id,
        (i) => i.copyWith(status: DownloadStatus.failed, error: e.toString()),
      );
    } finally {
      // Cancelled or failed: never leave a half-written song behind.
      final leftover = partialFile;
      if (leftover != null) {
        try {
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }
      _active.remove(id);
      _pumpQueue();
    }
  }

  /// Where downloads go when the folder works: the chosen folder, else
  /// Music/Looper. Creates nothing.
  static String preferredDownloadPath() {
    final chosen = OnlineSettingsNotifier.current.downloadDir?.trim();
    if (chosen != null && chosen.isNotEmpty) return chosen;
    if (Platform.isAndroid) return '/storage/emulated/0/Music/Looper';
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return p.join(home, 'Music', 'Looper');
  }

  static Future<Directory> getDownloadDirectory() async {
    var downloadDir = OnlineSettingsNotifier.current.downloadDir;
    if (downloadDir == null || downloadDir.trim().isEmpty) {
      try {
        final raw = await LocalJsonStore.read('online_settings');
        if (raw is Map && raw['downloadDir'] is String) {
          downloadDir = raw['downloadDir'] as String;
        }
      } catch (_) {}
    }

    if (downloadDir != null && downloadDir.trim().isNotEmpty) {
      final dir = Directory(downloadDir.trim());
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return dir;
      } catch (e) {
        LoggerHelper.write('$_tag: custom downloadDir $downloadDir failed to create/open: $e');
      }
    }

    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Music/Looper');
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return dir;
      } catch (_) {
        final extDirs = await getExternalStorageDirectories(
          type: StorageDirectory.music,
        );
        final fallback = extDirs?.firstOrNull ??
            (await getApplicationDocumentsDirectory());
        return fallback;
      }
    } else {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      final dir = Directory(p.join(home, 'Music', 'Looper'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
  }
}


/// What a download is tagged with: the listing, filled in from the song's
/// details and the saved online row. A field nobody states stays null.
OnlineSong mergeDownloadInfo(OnlineSong listed, OnlineSong? details, Song? row) =>
    OnlineSong(
      videoId: listed.videoId,
      title: listed.title,
      artist: listed.artist ?? details?.artist ?? row?.artist,
      album: listed.album ?? details?.album ?? row?.album,
      durationMs: listed.durationMs ?? details?.durationMs ?? row?.duration,
      // Details carry the largest picture; a listing's can be a small one.
      thumbnail: details?.thumbnail ?? listed.thumbnail ?? row?.artPath,
      videoType: listed.videoType ?? details?.videoType,
      year: listed.year ?? details?.year ?? row?.year,
    );

/// Cover URLs to try, best first: googleusercontent art asked at 1200 px;
/// for a video, its largest frame, then whatever the listing had.
List<String> coverCandidates(String videoId, String? thumbnail) {
  final t = thumbnail;
  if (t != null && t.contains('googleusercontent.com')) {
    final big = t.replaceFirst(RegExp(r'=w\d+-h\d+[^/?#]*'), '=w1200-h1200-l90-rj');
    return {big, t}.toList();
  }
  return {
    'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg',
    'https://i.ytimg.com/vi/$videoId/hq720.jpg',
    if (t != null && t.startsWith('http')) t,
  }.toList();
}

class Cover {
  const Cover(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

/// The song's cover, square (a 16:9 video frame is cropped to its
/// centre), or null when none could be fetched.
Future<Cover?> downloadCover(String videoId, String? thumbnail) async {
  for (final url in coverCandidates(videoId, thumbnail)) {
    try {
      final res = await InnerTube.instance.client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.bodyBytes.length < 1024) continue;
      return await squareCover(res.bodyBytes);
    } catch (_) {}
  }
  return null;
}

/// [bytes] as a square picture: unchanged when already square, else the
/// centre square as PNG.
Future<Cover> squareCover(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    final w = image.width, h = image.height;
    if ((w - h).abs() <= 2) return Cover(bytes, _mimeOf(bytes));
    final side = math.min(w, h);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH((w - side) / 2, (h - side) / 2, side.toDouble(), side.toDouble()),
      ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final square = await recorder.endRecording().toImage(side, side);
    final png = await square.toByteData(format: ui.ImageByteFormat.png);
    square.dispose();
    return Cover(png!.buffer.asUint8List(), 'image/png');
  } finally {
    image.dispose();
  }
}

String _mimeOf(Uint8List b) =>
    b.length > 3 && b[0] == 0x89 && b[1] == 0x50 ? 'image/png' : 'image/jpeg';

/// Folders downloads went to. The Downloads list, the library clean-up
/// and taste scoring all ask here; on Android without All Files Access a
/// download can land in the app's own music folder instead of Music/Looper.
abstract final class DownloadFolders {
  static const _key = 'online_download_dirs';
  static final Set<String> _dirs = {};
  static bool _loaded = false;

  static Future<Set<String>> all() async {
    if (!_loaded) {
      _loaded = true;
      final raw = await LocalJsonStore.read(_key);
      if (raw is List) _dirs.addAll(raw.whereType<String>());
    }
    return {..._dirs, DownloadsNotifier.preferredDownloadPath()};
  }

  static Future<void> remember(String dir) async {
    await all();
    if (_dirs.add(dir)) await LocalJsonStore.write(_key, _dirs.toList());
  }

  /// Whether [path] is a file inside one of [dirs].
  static bool contains(String path, Iterable<String> dirs) =>
      !path.startsWith('yt:') &&
      dirs.any((d) => d.isNotEmpty && p.isWithin(d, path));

  @visibleForTesting
  static void resetForTesting() {
    _dirs.clear();
    _loaded = false;
  }
}
