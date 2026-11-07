import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _settingsKey = 'apple_animated_artworks_settings_v1';
const String _indexKey = 'apple_animated_artworks_index_v1';

class AnimatedArtworkSettingsNotifier
    extends Notifier<AnimatedArtworkSettings> {
  static AnimatedArtworkSettings current = const AnimatedArtworkSettings();

  @override
  AnimatedArtworkSettings build() {
    _load();
    return current;
  }

  Future<void> _load() async {
    final raw = await LocalJsonStore.read(_settingsKey);
    if (raw is Map) {
      state = current =
          AnimatedArtworkSettings.fromJson(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> update(
    AnimatedArtworkSettings Function(AnimatedArtworkSettings) change,
  ) async {
    state = current = change(state);
    await LocalJsonStore.write(_settingsKey, state.toJson());
  }
}

final animatedArtworkSettingsProvider =
    NotifierProvider<AnimatedArtworkSettingsNotifier, AnimatedArtworkSettings>(
      AnimatedArtworkSettingsNotifier.new,
    );

class AnimatedArtworkService {
  static final AnimatedArtworkService instance = AnimatedArtworkService._();
  AnimatedArtworkService._();

  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

  Directory? _cacheDir;
  final Map<String, Completer<AnimatedArtwork?>> _inFlight = {};

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    try {
      final base = await getApplicationCacheDirectory();
      final dir = Directory(p.join(base.path, 'animated_artwork'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    } catch (_) {
      final temp = Directory.systemTemp;
      final dir = Directory(p.join(temp.path, 'looper_animated_artwork'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    }
  }

  String _cleanMetadata(String text) {
    return text
        .replaceAll(
          RegExp(
            r'\s*[\(\[][^\]\)]*(video|audio|lyrics|official|hq|hd|remastered|feat\.|ft\.)[^\]\)]*[\)\]]',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static final Map<String, AnimatedArtwork> _memoryCache = {};

  String _albumKey(String? artist, String? album) =>
      _trackOrAlbumKey(artist, album, null);

  String _trackOrAlbumKey(String? artist, String? album, String? title) {
    final a = (artist ?? '').trim().toLowerCase();
    final al = (album ?? '').trim().toLowerCase();
    final t = (title ?? '').trim().toLowerCase();
    if (al.isNotEmpty && al != 'unknown album') {
      return 'album:$a:$al';
    }
    return 'track:$a:$t';
  }

  String _artistKey(String? artist) {
    final a = (artist ?? '').trim().toLowerCase();
    return 'artist:$a';
  }

  Future<AnimatedArtwork?> getCached(String key) async {
    final inMem = _memoryCache[key];
    if (inMem != null && !inMem.isExpired) return inMem;

    final index = await LocalJsonStore.read(_indexKey);
    if (index is Map && index.containsKey(key)) {
      final entry = AnimatedArtwork.fromJson(
        Map<String, dynamic>.from(index[key] as Map),
      );
      if (!entry.isExpired) {
        _memoryCache[key] = entry;
        return entry;
      }
    }
    return null;
  }

  Future<void> _saveCache(AnimatedArtwork artwork) async {
    _memoryCache[artwork.key] = artwork;
    final raw = await LocalJsonStore.read(_indexKey);
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    map[artwork.key] = artwork.toJson();
    await LocalJsonStore.write(_indexKey, map);
  }

  /// Whether playback / network download is currently permitted by user settings.
  Future<bool> isNetworkPermitted() async {
    final settings = AnimatedArtworkSettingsNotifier.current;
    if (settings.mode == AnimatedArtworkMode.never) return false;
    if (settings.mode == AnimatedArtworkMode.wifiOnly) {
      final metered = await isNetworkMetered();
      if (metered) return false;
    }
    return true;
  }

  /// Resolve animated artwork for a song (local or online).
  Future<AnimatedArtwork?> resolveForSong(Song song) async {
    final album = (song.album != null && song.album!.isNotEmpty)
        ? song.album
        : null;
    final artist = (song.artist != null && song.artist!.isNotEmpty)
        ? song.artist
        : null;
    return resolveForMetadata(artist: artist, album: album, title: song.title);
  }

  /// Resolve animated artwork for artist / album / title metadata.
  Future<AnimatedArtwork?> resolveForMetadata({
    String? artist,
    String? album,
    String? title,
  }) async {
    if ((artist == null || artist.isEmpty) && (album == null || album.isEmpty)) {
      return null;
    }

    final key = _trackOrAlbumKey(artist, album, title);

    // 1. Check local index
    final cached = await getCached(key);
    if (cached != null) {
      if (!cached.hasMotion) return null;
      _triggerBackgroundDownload(cached);
      return cached;
    }

    // 2. Deduplicate in-flight requests
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!.future;
    }

    final completer = Completer<AnimatedArtwork?>();
    _inFlight[key] = completer;

    try {
      final result = await _performResolve(
        key: key,
        artist: artist,
        album: album,
        title: title,
      );
      completer.complete(result);
      return result;
    } catch (e, s) {
      LoggerHelper.write('Animated artwork resolution failed for $key', e, s);
      completer.complete(null);
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Resolve animated artwork for an artist profile banner.
  Future<AnimatedArtwork?> resolveForArtist(String artistName) async {
    if (artistName.trim().isEmpty) return null;
    final key = _artistKey(artistName);

    final cached = await getCached(key);
    if (cached != null) {
      if (!cached.hasMotion) return null;
      _triggerBackgroundDownload(cached);
      return cached;
    }

    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!.future;
    }

    final completer = Completer<AnimatedArtwork?>();
    _inFlight[key] = completer;

    try {
      final result = await _performArtistResolve(key: key, artist: artistName);
      completer.complete(result);
      return result;
    } catch (e, s) {
      LoggerHelper.write('Artist animated artwork failed for $key', e, s);
      completer.complete(null);
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Resolve animated artwork from a direct Apple Music URL (manual link or custom playlist).
  Future<AnimatedArtwork?> resolveByUrl(String url) async {
    final cleanUrl = url.trim();
    if (!cleanUrl.contains('music.apple.com')) return null;

    final key = 'url:${cleanUrl.toLowerCase()}';
    final cached = await getCached(key);
    if (cached != null) {
      if (!cached.hasMotion) return null;
      _triggerBackgroundDownload(cached);
      return cached;
    }

    try {
      final (square, tall) = await _scrapeAppleMusicPage(cleanUrl);
      final hasMotion = square != null || tall != null;
      final art = AnimatedArtwork(
        key: key,
        urlSquare: square,
        urlTall: tall,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        hasMotion: hasMotion,
      );
      await _saveCache(art);
      if (hasMotion) {
        _triggerBackgroundDownload(art);
        return art;
      }
      return null;
    } catch (e, s) {
      LoggerHelper.write('Failed to resolve animated artwork by URL $cleanUrl', e, s);
      return null;
    }
  }

  Future<AnimatedArtwork?> _performResolve({
    required String key,
    String? artist,
    String? album,
    String? title,
  }) async {
    // Check if network is allowed
    final netOk = await isNetworkPermitted();
    if (!netOk) return null;

    // Direct Apple Music resolver
    final cleanArtist = _cleanMetadata(artist ?? '');
    final cleanAlbum = _cleanMetadata(album ?? '');
    final cleanTitle = _cleanMetadata(title ?? '');

    String? appleMusicUrl = cleanAlbum.isNotEmpty
        ? await _searchAppleMusicUrl(
            artist: cleanArtist,
            album: cleanAlbum,
          )
        : null;

    if (appleMusicUrl == null && cleanTitle.isNotEmpty) {
      // Fallback search with artist + track title as single / album
      appleMusicUrl = await _searchAppleMusicUrl(
        artist: cleanArtist,
        album: cleanTitle,
      );
    }

    if (appleMusicUrl == null && cleanTitle.isNotEmpty) {
      // Fallback 2: Direct song search to locate parent album on Apple Music
      appleMusicUrl = await _searchAppleMusicSongUrl(
        artist: cleanArtist,
        title: cleanTitle,
      );
    }

    if (appleMusicUrl == null) {
      // Negative cache
      final negative = AnimatedArtwork(
        key: key,
        artist: artist,
        album: album,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        hasMotion: false,
      );
      await _saveCache(negative);
      return null;
    }

    final (square, tall) = await _scrapeAppleMusicPage(appleMusicUrl);
    final hasMotion = square != null || tall != null;

    final artwork = AnimatedArtwork(
      key: key,
      artist: artist,
      album: album,
      urlSquare: square,
      urlTall: tall,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      hasMotion: hasMotion,
    );

    await _saveCache(artwork);

    if (hasMotion) {
      _triggerBackgroundDownload(artwork);
      return artwork;
    }
    return null;
  }

  Future<AnimatedArtwork?> _performArtistResolve({
    required String key,
    required String artist,
  }) async {
    final netOk = await isNetworkPermitted();
    if (!netOk) return null;

    final cleanArtist = _cleanMetadata(artist);
    final query = Uri.encodeComponent(cleanArtist);
    final itunesUrl =
        'https://itunes.apple.com/search?term=$query&entity=musicArtist&limit=3';

    try {
      final res = await http.get(
        Uri.parse(itunesUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map;
          final artistViewUrl = first['artistLinkUrl'] as String?;
          if (artistViewUrl != null) {
            final (square, tall) = await _scrapeAppleMusicPage(artistViewUrl);
            final hasMotion = square != null || tall != null;
            final art = AnimatedArtwork(
              key: key,
              artist: artist,
              urlSquare: square,
              urlTall: tall,
              fetchedAt: DateTime.now().millisecondsSinceEpoch,
              hasMotion: hasMotion,
            );
            await _saveCache(art);
            if (hasMotion) {
              _triggerBackgroundDownload(art);
              return art;
            }
          }
        }
      }
    } catch (_) {}

    final negative = AnimatedArtwork(
      key: key,
      artist: artist,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      hasMotion: false,
    );
    await _saveCache(negative);
    return null;
  }

  Future<String?> _searchAppleMusicUrl({
    required String artist,
    required String album,
  }) async {
    final query = Uri.encodeComponent('$artist $album'.trim());

    final itunesUrl =
        'https://itunes.apple.com/search?term=$query&entity=album&limit=5';

    try {
      final res = await http.get(
        Uri.parse(itunesUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final albumLower = album.toLowerCase();
          for (final item in results) {
            final name = (item['collectionName'] as String? ?? '').toLowerCase();
            final viewUrl = item['collectionViewUrl'] as String?;
            if (viewUrl != null &&
                (name.contains(albumLower) || albumLower.contains(name))) {
              return viewUrl;
            }
          }
          final fallbackUrl = results.first['collectionViewUrl'] as String?;
          if (fallbackUrl != null) return fallbackUrl;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _searchAppleMusicSongUrl({
    required String artist,
    required String title,
  }) async {
    final query = Uri.encodeComponent('$artist $title'.trim());
    final itunesUrl =
        'https://itunes.apple.com/search?term=$query&entity=song&limit=5';

    try {
      final res = await http.get(
        Uri.parse(itunesUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map;
          final viewUrl = first['collectionViewUrl'] as String? ??
              first['trackViewUrl'] as String?;
          if (viewUrl != null) return viewUrl;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<(String? square, String? tall)> _scrapeAppleMusicPage(
    String pageUrl,
  ) async {
    try {
      final res = await http.get(
        Uri.parse(pageUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return (null, null);

      final html = res.body;

      String? squareUrl;
      String? tallUrl;

      // Extract JSON scripts
      final scriptRegex = RegExp(
        r'<script[^>]*type=["\x27]application/json["\x27][^>]*>(.*?)</script>',
        dotAll: true,
      );
      final matches = scriptRegex.allMatches(html);

      for (final match in matches) {
        final content = match.group(1);
        if (content == null || !content.contains('mvod.itunes.apple.com')) {
          continue;
        }

        try {
          final parsed = json.decode(content);
          void search(dynamic obj) {
            if (obj is Map) {
              if (obj.containsKey('videoArtwork')) {
                final va = obj['videoArtwork'];
                if (va is Map && va.containsKey('dictionary')) {
                  final dict = va['dictionary'];
                  if (dict is Map && dict.containsKey('motionDetailSquare')) {
                    squareUrl ??= dict['motionDetailSquare']?['video']?.toString();
                  }
                }
              }
              if (obj.containsKey('tallVideoArtwork')) {
                final tva = obj['tallVideoArtwork'];
                if (tva is Map && tva.containsKey('dictionary')) {
                  final dict = tva['dictionary'];
                  if (dict is Map && dict.containsKey('motionDetailTall')) {
                    tallUrl ??= dict['motionDetailTall']?['video']?.toString();
                  }
                }
              }
              if (obj.containsKey('editorialVideo')) {
                final ev = obj['editorialVideo'];
                if (ev is Map) {
                  squareUrl ??= ev['motionDetailSquare']?['video']?.toString();
                  tallUrl ??= ev['motionDetailTall']?['video']?.toString();
                }
              }
              for (final v in obj.values) {
                search(v);
              }
            } else if (obj is List) {
              for (final v in obj) {
                search(v);
              }
            }
          }

          search(parsed);
        } catch (_) {}
      }

      // Regex fallback if JSON walk didn't catch it
      if (squareUrl == null || tallUrl == null) {
        final m3u8Regex = RegExp(
          r'https://mvod\.itunes\.apple\.com/itunes-assets/[^\s"\x27<>]+\.m3u8',
        );
        final found = m3u8Regex.allMatches(html).map((m) => m.group(0)!).toSet();
        for (final u in found) {
          if (u.contains('Square') || squareUrl == null) {
            squareUrl ??= u;
          } else if (u.contains('Tall') || tallUrl == null) {
            tallUrl ??= u;
          }
        }
      }

      return (squareUrl, tallUrl);
    } catch (_) {
      return (null, null);
    }
  }

  /// Extracts the direct MP4 URL from an Apple Music master `.m3u8` manifest.
  /// ponytail: Parse standard HLS stream tags with minimal allocations.
  Future<String?> resolveDirectMp4Url(String m3u8Url) async {
    if (m3u8Url.endsWith('.mp4')) return m3u8Url;
    try {
      final masterRes = await http.get(
        Uri.parse(m3u8Url),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));

      if (masterRes.statusCode != 200) return null;

      final masterBody = masterRes.body;
      final lines = masterBody.split('\n');

      final variants = <(int width, String url)>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
          final w = resMatch != null ? int.parse(resMatch.group(1)!) : 0;
          if (i + 1 < lines.length) {
            final nextLine = lines[i + 1].trim();
            if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
              variants.add((w, nextLine));
            }
          }
        }
      }

      if (variants.isEmpty) return null;

      // Pick variant closest to 768px for balanced mobile fidelity and low bandwidth
      variants.sort((a, b) => (a.$1 - 768).abs().compareTo((b.$1 - 768).abs()));
      final bestVariantUri = variants.first.$2;
      final variantUrl = Uri.parse(m3u8Url).resolve(bestVariantUri).toString();

      final variantRes = await http.get(
        Uri.parse(variantUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));

      if (variantRes.statusCode != 200) return null;

      final variantBody = variantRes.body;
      final mp4Match = RegExp(r'URI="([^"]+\.mp4)"').firstMatch(variantBody) ??
          RegExp(r'([^\s#]+\.mp4)').firstMatch(variantBody);

      if (mp4Match != null) {
        final mp4Relative = mp4Match.group(1)!;
        return Uri.parse(variantUrl).resolve(mp4Relative).toString();
      }
    } catch (_) {}
    return null;
  }

  void _triggerBackgroundDownload(AnimatedArtwork artwork) {
    // Only download if network policy allows
    isNetworkPermitted().then((permitted) {
      if (!permitted) return;
      _downloadArtworkMedia(artwork);
    });
  }

  Future<void> _downloadArtworkMedia(AnimatedArtwork artwork) async {
    try {
      final dir = await _getCacheDir();
      bool modified = false;
      String? localSquare = artwork.localPathSquare;
      String? localTall = artwork.localPathTall;

      if (artwork.urlSquare != null &&
          (localSquare == null || !File(localSquare).existsSync())) {
        final directMp4 = await resolveDirectMp4Url(artwork.urlSquare!);
        if (directMp4 != null) {
          final hash = md5.convert(utf8.encode(directMp4)).toString();
          final file = File(p.join(dir.path, '$hash.mp4'));
          if (!file.existsSync()) {
            final res = await http.get(Uri.parse(directMp4));
            if (res.statusCode == 200) {
              await file.writeAsBytes(res.bodyBytes);
              localSquare = file.path;
              modified = true;
            }
          } else {
            localSquare = file.path;
            modified = true;
          }
        }
      }

      if (artwork.urlTall != null &&
          (localTall == null || !File(localTall).existsSync())) {
        final directMp4 = await resolveDirectMp4Url(artwork.urlTall!);
        if (directMp4 != null) {
          final hash = md5.convert(utf8.encode(directMp4)).toString();
          final file = File(p.join(dir.path, '$hash.mp4'));
          if (!file.existsSync()) {
            final res = await http.get(Uri.parse(directMp4));
            if (res.statusCode == 200) {
              await file.writeAsBytes(res.bodyBytes);
              localTall = file.path;
              modified = true;
            }
          } else {
            localTall = file.path;
            modified = true;
          }
        }
      }

      if (modified) {
        final updated = artwork.copyWith(
          localPathSquare: localSquare,
          localPathTall: localTall,
        );
        await _saveCache(updated);
        await _evictCacheIfOverLimit();
      }
    } catch (e) {
      LoggerHelper.write('Background download for motion artwork error: $e');
    }
  }

  Future<void> _evictCacheIfOverLimit() async {
    try {
      final dir = await _getCacheDir();
      final entities = dir.listSync().whereType<File>().toList();
      int totalBytes = 0;
      for (final f in entities) {
        totalBytes += f.lengthSync();
      }

      final limitBytes =
          AnimatedArtworkSettingsNotifier.current.cacheLimitMB * 1024 * 1024;
      if (totalBytes > limitBytes) {
        // Sort oldest modified first
        entities.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );
        for (final f in entities) {
          if (totalBytes <= limitBytes) break;
          final len = f.lengthSync();
          try {
            f.deleteSync();
            totalBytes -= len;
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> clearCache() async {
    try {
      final dir = await _getCacheDir();
      if (dir.existsSync()) {
        final files = dir.listSync().whereType<File>();
        for (final f in files) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      await LocalJsonStore.delete(_indexKey);
    } catch (_) {}
  }

  Future<int> getCacheSizeBytes() async {
    try {
      final dir = await _getCacheDir();
      if (!dir.existsSync()) return 0;
      int total = 0;
      for (final f in dir.listSync().whereType<File>()) {
        total += f.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}

// --- Riverpod Providers ---

final animatedArtworkForSongProvider =
    FutureProvider.family<AnimatedArtwork?, Song>((ref, song) async {
  final settings = ref.watch(animatedArtworkSettingsProvider);
  if (settings.mode == AnimatedArtworkMode.never) return null;
  return AnimatedArtworkService.instance.resolveForSong(song);
});

final animatedArtworkForCollectionProvider =
    FutureProvider.family<AnimatedArtwork?, ({String? artist, String? album})>(
  (ref, params) async {
    final settings = ref.watch(animatedArtworkSettingsProvider);
    if (settings.mode == AnimatedArtworkMode.never) return null;
    return AnimatedArtworkService.instance.resolveForMetadata(
      artist: params.artist,
      album: params.album,
    );
  },
);

final animatedArtworkForArtistProvider =
    FutureProvider.family<AnimatedArtwork?, String>((ref, artist) async {
  final settings = ref.watch(animatedArtworkSettingsProvider);
  if (settings.mode == AnimatedArtworkMode.never) return null;
  return AnimatedArtworkService.instance.resolveForArtist(artist);
});
