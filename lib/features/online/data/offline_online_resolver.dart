import 'dart:async';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/domain/guest_taste_profile.dart';

/// Normalized entity containing clean title and primary artist.
class CleanEntity {
  final String title;
  final String primaryArtist;

  const CleanEntity({required this.title, required this.primaryArtist});

  @override
  String toString() => 'CleanEntity(title: $title, artist: $primaryArtist)';
}

/// Cache entry for resolved YouTube Music IDs.
class ResolverCacheEntry {
  final String videoId;
  final String? artistBrowseId;
  final String radioPlaylistId;
  final DateTime resolvedAt;

  const ResolverCacheEntry({
    required this.videoId,
    this.artistBrowseId,
    required this.radioPlaylistId,
    required this.resolvedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(resolvedAt) > const Duration(days: 30);

  Map<String, dynamic> toJson() => {
        'v': videoId,
        if (artistBrowseId != null) 'b': artistBrowseId,
        'r': radioPlaylistId,
        'at': resolvedAt.millisecondsSinceEpoch,
      };

  factory ResolverCacheEntry.fromJson(Map<String, dynamic> json) =>
      ResolverCacheEntry(
        videoId: json['v'] as String? ?? '',
        artistBrowseId: json['b'] as String?,
        radioPlaylistId: json['r'] as String? ??
            (json['v'] != null ? 'RDAMVM${json['v']}' : ''),
        resolvedAt: DateTime.fromMillisecondsSinceEpoch(
          json['at'] as int? ?? 0,
        ),
      );
}

/// Resolves offline library metadata (titles, artists) to YouTube Music entities
/// using public web endpoints, with on-device caching and concurrency throttling.
///
/// See docs/online/23-guest-mode-offline-seeded-recommendations.md.
class OfflineOnlineResolver {
  static const _tag = 'OfflineOnlineResolver';
  static const _cacheStoreKey = 'guest_offline_online_resolver_cache_v1';

  static final Map<String, ResolverCacheEntry> _memoryCache = {};
  static bool _loaded = false;

  // Regex patterns per Section 4.1 of the specification
  static final _tagBracketPattern = RegExp(
    r'\s*[\(\[\{][^\)\]\}]*\b(official|music\s+video|video|audio|lyrics?|remastered|explicit|320kbps|flac|hd|hq|4k|mv|audio\s+track)\b[^\)\]\}]*[\)\]\}]',
    caseSensitive: false,
  );

  static final _trackNumberPattern = RegExp(r'^\d+\s*[-.]\s*');

  static final _fileExtensionPattern = RegExp(
    r'\.(mp3|flac|m4a|wav|opus|ogg|aac|alac)$',
    caseSensitive: false,
  );

  static final _multiArtistDelimiter = RegExp(
    r'\s*(?:feat\.?|ft\.?|featuring|&|,|/|vs\.?|x)\s+',
    caseSensitive: false,
  );

  /// Cleans a song title by stripping file extensions, track numbers, and noise brackets.
  static String cleanTitle(String rawTitle) {
    var title = rawTitle.trim();
    title = title.replaceAll(_fileExtensionPattern, '');
    title = title.replaceAll(_trackNumberPattern, '');
    title = title.replaceAll(_tagBracketPattern, '');
    // Clean up leftover double spaces or punctuation
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? rawTitle.trim() : title;
  }

  /// Extracts the primary artist by taking the first credit before multi-artist delimiters.
  static String cleanArtist(String? rawArtist) {
    if (rawArtist == null) return '';
    var artist = rawArtist.trim();
    if (artist.isEmpty) return '';
    // Strip file extensions or track numbers if dirty
    artist = artist.replaceAll(_fileExtensionPattern, '');
    artist = artist.replaceAll(_trackNumberPattern, '');
    artist = artist.replaceAll(_tagBracketPattern, '');

    final parts = artist.split(_multiArtistDelimiter);
    final primary = parts.first.replaceAll(RegExp(r'\s+'), ' ').trim();
    return primary.isEmpty ? artist : primary;
  }

  /// Sanitizes raw offline metadata into a clean title and primary artist.
  static CleanEntity cleanEntity(String rawTitle, String? rawArtist) {
    // If the title itself contains "Artist - Title", separate them if artist is blank
    var title = cleanTitle(rawTitle);
    var artist = cleanArtist(rawArtist);

    if (artist.isEmpty && title.contains(' - ')) {
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        artist = cleanArtist(parts.first);
        title = cleanTitle(parts.sublist(1).join(' - '));
      }
    }

    return CleanEntity(title: title, primaryArtist: artist);
  }

  /// Cache key generator: lowercase `cleanTitle|cleanArtist`.
  static String cacheKey(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  /// Ensures persisted cache is loaded into memory.
  static Future<void> initCache() async {
    if (_loaded) return;
    try {
      final raw = await LocalJsonStore.read(_cacheStoreKey);
      if (raw is Map) {
        for (final e in raw.entries) {
          if (e.value is Map) {
            _memoryCache[e.key.toString()] = ResolverCacheEntry.fromJson(
              (e.value as Map).cast<String, dynamic>(),
            );
          }
        }
      }
      _loaded = true;
    } catch (e) {
      LoggerHelper.write('$_tag: initCache failed', e);
    }
  }

  /// Saves memory cache to persistent storage.
  static Future<void> _persistCache() async {
    try {
      final data = <String, dynamic>{};
      for (final e in _memoryCache.entries) {
        if (!e.value.isExpired) {
          data[e.key] = e.value.toJson();
        }
      }
      await LocalJsonStore.write(_cacheStoreKey, data);
    } catch (e) {
      LoggerHelper.write('$_tag: persistCache failed', e);
    }
  }

  /// Resolves an offline song to YouTube Music videoId and radio playlist ID.
  static Future<TasteSeed?> resolveSong(
    String rawTitle,
    String? rawArtist, {
    double score = 1.0,
  }) async {
    await initCache();
    final clean = cleanEntity(rawTitle, rawArtist);
    if (clean.title.isEmpty) return null;

    final key = cacheKey(clean.title, clean.primaryArtist);
    final cached = _memoryCache[key];
    if (cached != null && !cached.isExpired) {
      return TasteSeed(
        title: clean.title,
        artist: clean.primaryArtist,
        score: score,
        videoId: cached.videoId,
        artistBrowseId: cached.artistBrowseId,
        radioPlaylistId: cached.radioPlaylistId,
      );
    }

    try {
      final query = '${clean.title} ${clean.primaryArtist}'.trim();
      final (songs, _) = await OnlineApi.searchSongs(query, automatic: true);
      if (songs.isEmpty) return null;

      // Prefer album audio or official release over UGC fan uploads if possible
      final match = songs.firstWhere(
        (s) => s.videoType != videoTypeFanUpload,
        orElse: () => songs.first,
      );

      final entry = ResolverCacheEntry(
        videoId: match.videoId,
        artistBrowseId: null,
        radioPlaylistId: 'RDAMVM${match.videoId}',
        resolvedAt: DateTime.now(),
      );

      _memoryCache[key] = entry;
      unawaited(_persistCache());

      return TasteSeed(
        title: clean.title,
        artist: clean.primaryArtist,
        score: score,
        videoId: match.videoId,
        radioPlaylistId: entry.radioPlaylistId,
      );
    } catch (e) {
      LoggerHelper.write('$_tag: resolveSong failed for $rawTitle', e);
      return null;
    }
  }

  /// Resolves an artist to YouTube Music browseId.
  static Future<String?> resolveArtistBrowseId(String rawArtist) async {
    await initCache();
    final clean = cleanArtist(rawArtist);
    if (clean.isEmpty) return null;

    final key = 'artist|${clean.toLowerCase()}';
    final cached = _memoryCache[key];
    if (cached != null && !cached.isExpired && cached.artistBrowseId != null) {
      return cached.artistBrowseId;
    }

    try {
      final collections = await OnlineApi.searchCollections(
        clean,
        CollectionKind.artist,
        automatic: true,
      );
      final artistCol = collections.firstWhere(
        (c) => c.kind == CollectionKind.artist,
        orElse: () => collections.isNotEmpty &&
                collections.first.kind == CollectionKind.artist
            ? collections.first
            : collections.firstWhere((_) => true,
                orElse: () => const OnlineCollection(
                      browseId: '',
                      title: '',
                      kind: CollectionKind.artist,
                    )),
      );

      if (artistCol.browseId.isNotEmpty) {
        _memoryCache[key] = ResolverCacheEntry(
          videoId: '',
          artistBrowseId: artistCol.browseId,
          radioPlaylistId: '',
          resolvedAt: DateTime.now(),
        );
        unawaited(_persistCache());
        return artistCol.browseId;
      }
    } catch (e) {
      LoggerHelper.write('$_tag: resolveArtistBrowseId failed for $clean', e);
    }
    return null;
  }

  /// Resolves a batch of seeds with concurrency throttled to [maxConcurrent] (default: 3).
  static Future<List<TasteSeed>> resolveSeeds(
    List<TasteSeed> seeds, {
    int maxConcurrent = 3,
  }) async {
    final results = <TasteSeed>[];
    final pool = <Future<void>>[];

    for (final seed in seeds) {
      if (seed.videoId != null) {
        results.add(seed);
        continue;
      }

      final task = resolveSong(seed.title, seed.artist, score: seed.score)
          .then((resolved) {
        if (resolved != null) {
          results.add(resolved);
        }
      });
      pool.add(task);

      if (pool.length >= maxConcurrent) {
        await Future.any(pool);
        pool.removeWhere((f) => f == task); // ponytail: simple concurrency pool
      }
    }

    await Future.wait(pool);
    // Maintain descending score order
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
}
