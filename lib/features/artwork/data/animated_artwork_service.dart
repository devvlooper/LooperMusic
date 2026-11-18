import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:looper_player/core/services/apple_web_token.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/artwork/data/youtube_video_artwork.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/artwork/domain/media_match.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _settingsKey = 'apple_animated_artworks_settings_v1';
const String _indexKey = 'animated_artwork_index_v2';

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
      state = current = AnimatedArtworkSettings.fromJson(
        Map<String, dynamic>.from(raw),
      );
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
  static const String _tidalToken = 'CzET4vdadNUFQ5JU';

  /// Ranks candidates that already passed [strictMatch]; -1 rejects.
  static int scoreMatch({
    required String wantArtist,
    required String wantAlbum,
    String? wantTitle,
    required String resultArtist,
    required String resultAlbum,
    String? resultTitle,
  }) {
    final normWantA = foldText(wantArtist).trim();
    final normResA = foldText(resultArtist).trim();

    // 1. Artist required: split on standard delimiters
    final artistSeparators = RegExp(
      r'\s*(?:,|&|\bx\b|feat\.?|ft\.?|featuring|with)\s*',
      caseSensitive: false,
    );
    final artists = normWantA
        .split(artistSeparators)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (final a in artists) {
      if (!normResA.contains(a)) {
        return -1; // Missing artist
      }
    }

    int score = 0;

    // 2. Title scoring (if present)
    if (wantTitle != null && resultTitle != null) {
      final tWant = titleKey(wantTitle);
      final tRes = titleKey(resultTitle);
      if (tWant == tRes) {
        score += 15;
      } else if (tWant.contains(tRes) || tRes.contains(tWant)) {
        score += 7;
      } else {
        score -= 10;
      }
    }

    // 3. Album scoring
    final cleanWantAl = titleKey(wantAlbum);
    final cleanResAl = titleKey(resultAlbum);
    if (cleanWantAl == cleanResAl) {
      score += 20;
    } else if (cleanWantAl.contains(cleanResAl) ||
        cleanResAl.contains(cleanWantAl)) {
      score += 10;
    }

    // 4. Edition words present only in result: -3 each
    final wantCombined = foldText('$normWantA $wantAlbum ${wantTitle ?? ""}');
    final resCombined = foldText('$normResA $resultAlbum ${resultTitle ?? ""}');
    if (isOtherTake(resCombined, wantCombined)) score -= 3;

    // 5. Reject compilations
    final compilationWords = [
      'playlist',
      'essentials',
      'dj mix',
      'greatest hits',
      "now that's what i call",
    ];
    for (final cw in compilationWords) {
      if (resCombined.contains(cw) && !wantCombined.contains(cw)) {
        return -1;
      }
    }

    return score;
  }

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

  AnimatedArtwork? getCachedSync(String key) {
    final inMem = _memoryCache[key];
    if (inMem != null && !inMem.isExpired) return inMem;
    return null;
  }

  String keyForSong(Song song) {
    final album = (song.album != null && song.album!.isNotEmpty)
        ? song.album
        : null;
    final artist = (song.artist != null && song.artist!.isNotEmpty)
        ? song.artist
        : null;
    return _trackOrAlbumKey(artist, album, song.title);
  }

  AnimatedArtwork? getCachedSongSync(Song song) {
    final key = keyForSong(song);
    return getCachedSync(key);
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
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    map[artwork.key] = artwork.toJson();
    if (map.length > 2000) {
      final entries = map.entries.toList()
        ..sort((a, b) {
          final atA =
              (a.value is Map ? a.value['fetchedAt'] : null) as num? ?? 0;
          final atB =
              (b.value is Map ? b.value['fetchedAt'] : null) as num? ?? 0;
          return atA.compareTo(atB);
        });
      while (entries.length > 2000) {
        final oldest = entries.removeAt(0);
        map.remove(oldest.key);
      }
    }
    await LocalJsonStore.write(_indexKey, map);
  }

  /// Whether playback / network download is currently permitted by user settings.
  Future<bool> isNetworkPermitted() async {
    if (!OnlineSettingsNotifier.current.enabled) return false;
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
    return resolveForMetadata(
      artist: artist,
      album: album,
      title: song.title,
      duration: msDuration(song.duration),
    );
  }

  /// Resolve animated artwork for artist / album / title metadata.
  Future<AnimatedArtwork?> resolveForMetadata({
    String? artist,
    String? album,
    String? title,
    Duration? duration,
  }) async {
    if ((artist == null || artist.isEmpty) &&
        (album == null || album.isEmpty)) {
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
        duration: duration,
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
      LoggerHelper.write(
        'Failed to resolve animated artwork by URL $cleanUrl',
        e,
        s,
      );
      return null;
    }
  }

  Future<AnimatedArtwork?> _performResolve({
    required String key,
    String? artist,
    String? album,
    String? title,
    Duration? duration,
  }) async {
    final netOk = await isNetworkPermitted();
    if (!netOk) return null;

    final cleanArtist = _cleanMetadata(artist ?? '');
    final cleanAlbum = _cleanMetadata(album ?? '');
    final cleanTitle = _cleanMetadata(title ?? '');

    // 1. Apple Catalog API with editorialVideo
    try {
      final token = await AppleWebToken.getToken();
      if (token != null) {
        final storefront =
            OnlineSettingsNotifier.current.contentRegion?.toLowerCase() ?? 'us';
        final q =
            '$cleanArtist ${cleanAlbum.isNotEmpty ? cleanAlbum : cleanTitle}'
                .trim();
        final type = cleanAlbum.isNotEmpty ? 'albums' : 'songs';
        final uri =
            Uri.parse(
              'https://amp-api.music.apple.com/v1/catalog/$storefront/search',
            ).replace(
              queryParameters: {
                'term': q,
                'types': type,
                'limit': '10',
                'extend': 'editorialVideo',
                if (type == 'songs') 'include': 'albums',
              },
            );
        final res = await http
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Origin': 'https://music.apple.com',
                'Referer': 'https://music.apple.com/',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 401 || res.statusCode == 403) {
          AppleWebToken.invalidate();
        } else if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final items = (data['results']?[type]?['data'] as List? ?? const [])
              .whereType<Map>();
          Map? bestItem;
          int bestScore = -1;
          for (final item in items) {
            final attr = item['attributes'] as Map? ?? const {};
            final rArtist = attr['artistName']?.toString() ?? '';
            final rAlbum =
                (type == 'albums' ? attr['name'] : attr['albumName'])
                    ?.toString() ??
                '';
            final rTitle = type == 'songs' ? attr['name']?.toString() : null;
            if (!strictMatch(
              wantArtist: cleanArtist,
              resultArtist: rArtist,
              wantAlbum: cleanAlbum.isNotEmpty ? cleanAlbum : null,
              resultAlbum: type == 'albums' ? rAlbum : null,
              wantTitle: cleanTitle.isNotEmpty ? cleanTitle : null,
              resultTitle: rTitle,
              wantDuration: duration,
              resultDuration: msDuration(attr['durationInMillis']),
            )) {
              continue;
            }
            final sc = scoreMatch(
              wantArtist: cleanArtist,
              wantAlbum: cleanAlbum.isNotEmpty ? cleanAlbum : cleanTitle,
              wantTitle: cleanTitle.isNotEmpty ? cleanTitle : null,
              resultArtist: rArtist,
              resultAlbum: rAlbum,
              resultTitle: rTitle,
            );
            if (sc >= 0 && sc > bestScore) {
              bestScore = sc;
              bestItem = item;
            }
          }

          if (bestItem != null) {
            final attr = bestItem['attributes'] as Map? ?? const {};
            final ev = attr['editorialVideo'] as Map?;
            if (ev != null) {
              final sq =
                  ev['motionDetailSquare']?['video']?.toString() ??
                  ev['motionSquareVideo1x1']?['video']?.toString();
              final tl =
                  ev['motionDetailTall']?['video']?.toString() ??
                  ev['motionTallVideo3x4']?['video']?.toString();
              if (sq != null || tl != null) {
                final art = AnimatedArtwork(
                  key: key,
                  artist: artist,
                  album: album,
                  urlSquare: sq,
                  urlTall: tl,
                  fetchedAt: DateTime.now().millisecondsSinceEpoch,
                  hasMotion: true,
                );
                await _saveCache(art);
                _triggerBackgroundDownload(art);
                return art;
              }
            }
          }
        }
      }
    } catch (e) {
      LoggerHelper.write('Apple catalog API motion lookup error: $e');
    }

    // 2. Apple Music page scrape fallback
    String? appleMusicUrl = cleanAlbum.isNotEmpty
        ? await _searchAppleMusicUrl(artist: cleanArtist, album: cleanAlbum)
        : null;

    if (appleMusicUrl == null && cleanTitle.isNotEmpty) {
      appleMusicUrl = await _searchAppleMusicSongUrl(
        artist: cleanArtist,
        title: cleanTitle,
        duration: duration,
      );
    }

    if (appleMusicUrl != null) {
      try {
        final (square, tall) = await _scrapeAppleMusicPage(appleMusicUrl);
        if (square != null || tall != null) {
          final artwork = AnimatedArtwork(
            key: key,
            artist: artist,
            album: album,
            urlSquare: square,
            urlTall: tall,
            fetchedAt: DateTime.now().millisecondsSinceEpoch,
            hasMotion: true,
          );
          await _saveCache(artwork);
          _triggerBackgroundDownload(artwork);
          return artwork;
        }
      } catch (_) {}
    }

    // 3. Tidal video covers. Album search has no song length, so exact
    // album matches only.
    if (cleanAlbum.isNotEmpty) {
      try {
        final cc =
            OnlineSettingsNotifier.current.contentRegion?.toUpperCase() ?? 'US';
        final q =
            '$cleanArtist ${cleanAlbum.isNotEmpty ? cleanAlbum : cleanTitle}'
                .trim();
        final uri = Uri.parse('https://api.tidal.com/v1/search').replace(
          queryParameters: {
            'query': q,
            'limit': '10',
            'types': 'ALBUMS',
            'countryCode': cc,
          },
        );
        final res = await http
            .get(uri, headers: {'X-Tidal-Token': _tidalToken})
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final items = (data['albums']?['items'] as List? ?? const [])
              .whereType<Map>();
          for (final item in items) {
            final rArtist = item['artist']?['name']?.toString() ?? '';
            final rAlbum = item['title']?.toString() ?? '';
            if (!strictMatch(
              wantArtist: cleanArtist,
              resultArtist: rArtist,
              wantAlbum: cleanAlbum,
              resultAlbum: rAlbum,
            )) {
              continue;
            }
            final sc = scoreMatch(
              wantArtist: cleanArtist,
              wantAlbum: cleanAlbum.isNotEmpty ? cleanAlbum : cleanTitle,
              wantTitle: cleanTitle.isNotEmpty ? cleanTitle : null,
              resultArtist: rArtist,
              resultAlbum: rAlbum,
            );
            if (sc >= 0) {
              final videoCover = item['videoCover']?.toString();
              if (videoCover != null && videoCover.isNotEmpty) {
                final path = videoCover.replaceAll('-', '/');
                final mp4Url =
                    'https://resources.tidal.com/videos/$path/1280x1280.mp4';
                final art = AnimatedArtwork(
                  key: key,
                  artist: artist,
                  album: album,
                  urlSquare: mp4Url,
                  urlTall: null,
                  fetchedAt: DateTime.now().millisecondsSinceEpoch,
                  hasMotion: true,
                );
                await _saveCache(art);
                _triggerBackgroundDownload(art);
                return art;
              }
            }
          }
        }
      } catch (e) {
        LoggerHelper.write('Tidal video cover lookup error: $e');
      }
    }

    // 4. Clean negative result (not an unhandled error)
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

  /// Artist banner from Apple editorial (doc 26 §3.2). Clean misses are
  /// cached for 10 minutes; network errors are not cached.
  Future<AnimatedArtwork?> _performArtistResolve({
    required String key,
    required String artist,
  }) async {
    final netOk = await isNetworkPermitted();
    if (!netOk) return null;

    final token = await AppleWebToken.getToken();
    if (token == null) return null; // an error, not a miss

    final storefront =
        OnlineSettingsNotifier.current.contentRegion?.toLowerCase() ?? 'us';
    final base = 'https://amp-api.music.apple.com/v1/catalog/$storefront';
    final headers = {
      'Authorization': 'Bearer $token',
      'Origin': 'https://music.apple.com',
      'Referer': 'https://music.apple.com/',
    };

    // Null on any non-200; a 401/403 also drops the token.
    Future<dynamic> getJson(String path, Map<String, String> query) async {
      final res = await http
          .get(
            Uri.parse('$base$path').replace(queryParameters: query),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 401 || res.statusCode == 403) {
        AppleWebToken.invalidate();
      }
      return res.statusCode == 200
          ? jsonDecode(utf8.decode(res.bodyBytes))
          : null;
    }

    try {
      final cleanArtist = _cleanMetadata(artist);
      final search = await getJson('/search', {
        'term': cleanArtist,
        'types': 'artists',
        'limit': '5',
      });
      if (search == null) return null;

      final wanted = titleKey(cleanArtist);
      final id = wanted.isEmpty
          ? null
          : (search['results']?['artists']?['data'] as List? ?? const [])
                .whereType<Map>()
                .where(
                  (a) =>
                      titleKey(a['attributes']?['name']?.toString() ?? '') ==
                      wanted,
                )
                .map((a) => a['id']?.toString())
                .firstOrNull;

      AnimatedArtwork? art;
      if (id != null) {
        final detail = await getJson('/artists/$id', {
          'extend': 'editorialVideo,editorialArtwork,artistBio',
          'views': 'latest-release',
        });
        if (detail == null) return null;
        final attrs =
            (detail['data'] as List?)
                    ?.whereType<Map>()
                    .firstOrNull?['attributes']
                as Map?;
        art = AnimatedArtwork.fromArtistEditorial(
          attrs ?? const {},
          key: key,
          artist: artist,
        );
      }

      final result =
          art ??
          AnimatedArtwork(
            key: key,
            artist: artist,
            fetchedAt: DateTime.now().millisecondsSinceEpoch,
            hasMotion: false,
          );
      await _saveCache(result);
      if (!result.hasMotion) return null;
      _triggerBackgroundDownload(result);
      return result;
    } catch (e) {
      LoggerHelper.write('Artist editorial lookup error: $e');
      return null;
    }
  }

  Future<String?> _searchAppleMusicUrl({
    required String artist,
    required String album,
  }) async {
    final query = Uri.encodeComponent('$artist $album'.trim());

    final itunesUrl =
        'https://itunes.apple.com/search?term=$query&entity=album&limit=5';

    try {
      final res = await http
          .get(Uri.parse(itunesUrl), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['results'] as List?;
        for (final item in (results ?? const []).whereType<Map>()) {
          final viewUrl = item['collectionViewUrl'] as String?;
          if (viewUrl != null &&
              strictMatch(
                wantArtist: artist,
                resultArtist: item['artistName']?.toString() ?? '',
                wantAlbum: album,
                resultAlbum: item['collectionName']?.toString() ?? '',
              )) {
            return viewUrl;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _searchAppleMusicSongUrl({
    required String artist,
    required String title,
    Duration? duration,
  }) async {
    final query = Uri.encodeComponent('$artist $title'.trim());
    final itunesUrl =
        'https://itunes.apple.com/search?term=$query&entity=song&limit=5';

    try {
      final res = await http
          .get(Uri.parse(itunesUrl), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['results'] as List?;
        for (final item in (results ?? const []).whereType<Map>()) {
          final viewUrl =
              item['collectionViewUrl'] as String? ??
              item['trackViewUrl'] as String?;
          if (viewUrl != null &&
              strictMatch(
                wantArtist: artist,
                resultArtist: item['artistName']?.toString() ?? '',
                wantTitle: title,
                resultTitle: item['trackName']?.toString() ?? '',
                wantDuration: duration,
                resultDuration: msDuration(item['trackTimeMillis']),
              )) {
            return viewUrl;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<(String? square, String? tall)> _scrapeAppleMusicPage(
    String pageUrl,
  ) async {
    try {
      final res = await http
          .get(Uri.parse(pageUrl), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

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
                    squareUrl ??= dict['motionDetailSquare']?['video']
                        ?.toString();
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
        final found = m3u8Regex
            .allMatches(html)
            .map((m) => m.group(0)!)
            .toSet();
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
      final masterRes = await http
          .get(Uri.parse(m3u8Url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

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

      final variantRes = await http
          .get(Uri.parse(variantUrl), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (variantRes.statusCode != 200) return null;

      final variantBody = variantRes.body;
      final mp4Match =
          RegExp(r'URI="([^"]+\.mp4)"').firstMatch(variantBody) ??
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

  Future<String?> _downloadFileSafely(String url, Directory dir) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;

      final hash = md5.convert(utf8.encode(url)).toString();
      final partFile = File(p.join(dir.path, '$hash.mp4.part'));
      final finalFile = File(p.join(dir.path, '$hash.mp4'));

      final sink = partFile.openWrite();
      int bytesReceived = 0;
      const maxBytes = 15 * 1024 * 1024; // 15 MB cap
      final headerBytes = <int>[];

      await for (final chunk in res.stream) {
        bytesReceived += chunk.length;
        if (bytesReceived > maxBytes) {
          await sink.close();
          if (partFile.existsSync()) partFile.deleteSync();
          return null; // Cap exceeded
        }
        sink.add(chunk);
        if (headerBytes.length < 8) {
          headerBytes.addAll(chunk.take(8 - headerBytes.length));
        }
      }
      await sink.close();

      // Check for MP4 'ftyp' box in header (bytes 4..7: 'ftyp')
      bool validMp4 = false;
      if (headerBytes.length >= 8) {
        if (headerBytes[4] == 0x66 &&
            headerBytes[5] == 0x74 &&
            headerBytes[6] == 0x79 &&
            headerBytes[7] == 0x70) {
          validMp4 = true;
        }
      }

      if (!validMp4) {
        if (partFile.existsSync()) partFile.deleteSync();
        return null;
      }

      if (finalFile.existsSync()) finalFile.deleteSync();
      await rebaseTimeline(partFile.path);
      await partFile.rename(finalFile.path);
      return finalFile.path;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  final Map<String, Future<String?>> _localFiles = {};
  final Map<String, Future<void>> _rebased = {};

  /// [rebaseTimeline] once per file per session, for videos cached before
  /// downloads were rebased.
  Future<void> ensureTimeline(String path) =>
      _rebased[path] ??= rebaseTimeline(path);

  /// Apple's motion videos are cut from HLS streams and keep the stream's
  /// timestamps (often starting ~10 s in), so a looping player holds the
  /// first frame that long on every loop. Shifts each fragment's decode
  /// time (tfdt) so the video starts at 0. Plain mp4s have no fragments and
  /// are left alone; a file already at 0 is untouched.
  static Future<void> rebaseTimeline(String path) async {
    RandomAccessFile? raf;
    try {
      // append mode opens read/write without truncating; writes follow
      // setPosition.
      raf = await File(path).open(mode: FileMode.append);
      final len = await raf.length();
      int? base;
      var pos = 0;
      while (pos + 8 <= len) {
        await raf.setPosition(pos);
        final head = await raf.read(8);
        final size = ByteData.sublistView(head).getUint32(0);
        // shortcut: no 64-bit / to-end box sizes, which these small files never use.
        if (size < 8) break;
        if (String.fromCharCodes(head, 4, 8) == 'moof') {
          await raf.setPosition(pos);
          final moof = await raf.read(size);
          final view = ByteData.sublistView(moof);
          var changed = false;
          for (final traf in _childBoxes(moof, 8, moof.length, 'traf')) {
            for (final t in _childBoxes(
              moof,
              traf + 8,
              traf + view.getUint32(traf),
              'tfdt',
            )) {
              final v1 = moof[t + 8] == 1;
              final value = v1
                  ? view.getUint64(t + 12)
                  : view.getUint32(t + 12);
              base ??= value;
              if (base == 0) return; // already starts at 0
              v1
                  ? view.setUint64(t + 12, value - base)
                  : view.setUint32(t + 12, value - base);
              changed = true;
            }
          }
          if (changed) {
            await raf.setPosition(pos);
            await raf.writeFrom(moof);
          }
        }
        pos += size;
      }
    } catch (e) {
      LoggerHelper.write('Motion artwork timeline fix failed: $e');
    } finally {
      await raf?.close();
    }
  }

  /// Offsets of the [type] boxes directly inside bytes [start, end).
  static Iterable<int> _childBoxes(
    Uint8List bytes,
    int start,
    int end,
    String type,
  ) sync* {
    final view = ByteData.sublistView(bytes);
    var i = start;
    while (i + 8 <= end) {
      final size = view.getUint32(i);
      if (size < 8) return;
      if (String.fromCharCodes(bytes, i + 4, i + 8) == type) yield i;
      i += size;
    }
  }

  /// A cached copy of the motion video at [url] (mp4 or m3u8), downloaded
  /// once and shared by every caller; null when it can't be fetched.
  Future<String?> localFileFor(String url) {
    return _localFiles[url] ??=
        () async {
          final mp4 = url.endsWith('.mp4')
              ? url
              : await resolveDirectMp4Url(url);
          if (mp4 == null) return null;
          final dir = await _getCacheDir();
          final file = File(
            p.join(dir.path, '${md5.convert(utf8.encode(mp4))}.mp4'),
          );
          if (file.existsSync()) {
            await ensureTimeline(file.path);
            return file.path;
          }
          return _downloadFileSafely(mp4, dir);
        }().then((path) {
          // A failure can be retried next time.
          if (path == null) _localFiles.remove(url);
          return path;
        });
  }

  Future<void> _downloadArtworkMedia(AnimatedArtwork artwork) async {
    try {
      bool modified = false;
      String? localSquare = artwork.localPathSquare;
      String? localTall = artwork.localPathTall;

      if (artwork.urlSquare != null &&
          (localSquare == null || !File(localSquare).existsSync())) {
        final downloaded = await localFileFor(artwork.urlSquare!);
        if (downloaded != null) {
          localSquare = downloaded;
          modified = true;
        }
      }

      // Download tall only when immersiveBackground setting is on (A10)
      final wantTall =
          AnimatedArtworkSettingsNotifier.current.immersiveBackground;
      if (wantTall &&
          artwork.urlTall != null &&
          (localTall == null || !File(localTall).existsSync())) {
        final downloaded = await localFileFor(artwork.urlTall!);
        if (downloaded != null) {
          localTall = downloaded;
          modified = true;
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

final animatedArtworkForSongProvider = FutureProvider.autoDispose
    .family<AnimatedArtwork?, Song>((ref, song) async {
      final settings = ref.watch(animatedArtworkSettingsProvider);
      if (settings.mode == AnimatedArtworkMode.never) return null;
      Future<AnimatedArtwork?> youtube() async {
        if (!settings.source.usesYoutube || !song.isOnline) return null;
        if (!await AnimatedArtworkService.instance.isNetworkPermitted()) {
          return null;
        }
        return YoutubeVideoArtwork.resolve(song);
      }

      if (!settings.source.usesApple) return youtube();
      final cached = AnimatedArtworkService.instance.getCachedSongSync(song);
      if (cached != null) {
        if (cached.hasMotion) {
          AnimatedArtworkService.instance._triggerBackgroundDownload(cached);
          return cached;
        }
        return youtube();
      }
      return await AnimatedArtworkService.instance.resolveForSong(song) ??
          await youtube();
    });

final animatedArtworkForCollectionProvider = FutureProvider.autoDispose
    .family<AnimatedArtwork?, ({String? artist, String? album})>((
      ref,
      params,
    ) async {
      final settings = ref.watch(animatedArtworkSettingsProvider);
      if (settings.mode == AnimatedArtworkMode.never) return null;
      return AnimatedArtworkService.instance.resolveForMetadata(
        artist: params.artist,
        album: params.album,
      );
    });

final animatedArtworkForArtistProvider = FutureProvider.autoDispose
    .family<AnimatedArtwork?, String>((ref, artist) async {
      final settings = ref.watch(animatedArtworkSettingsProvider);
      if (settings.mode == AnimatedArtworkMode.never) return null;
      return AnimatedArtworkService.instance.resolveForArtist(artist);
    });
