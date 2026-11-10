import 'dart:async';
import 'dart:math' as math;
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

  bool get isNegative =>
      videoId.isEmpty && (artistBrowseId == null || artistBrowseId!.isEmpty);

  bool get isExpired {
    final age = DateTime.now().difference(resolvedAt);
    return isNegative
        ? age > const Duration(days: 7)
        : age > const Duration(days: 30);
  }

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
        radioPlaylistId:
            json['r'] as String? ??
            (((json['v'] as String?)?.isNotEmpty ?? false)
                ? 'RDAMVM${json['v']}'
                : ''),
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
  static const _cacheStoreKey = 'guest_resolver_cache_v2';

  static final Map<String, ResolverCacheEntry> _memoryCache = {};
  static bool _loaded = false;

  // Regex patterns per Section 5.1 of specification (fixes B1, B2)
  static final _tagBracketPattern = RegExp(
    r'\s*[\(\[\{][^\)\]\}]*\b(official|music\s+video|video|audio|lyrics?|'
    r'visuali[sz]er|remaster(ed)?(\s+\d{4})?|explicit|clean|hd|hq|4k|mv|'
    r'\d{3}\s?kbps|flac|mp3)\b[^\)\]\}]*[\)\]\}]',
    caseSensitive: false,
  );

  static final _trackNumberPattern = RegExp(r'^\d{1,3}(?:\s*[-.]\s+|\s+-\s+)');

  static final _fileExtensionPattern = RegExp(
    r'\.(mp3|flac|m4a|wav|opus|ogg|aac|alac|wma)$',
    caseSensitive: false,
  );

  // Word separators need whitespace on both sides; punctuation separators do not (fixes B1).
  static final _multiArtistDelimiter = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring|x|vs\.?)\s+|\s*[,;&]\s*|\s+/\s+',
    caseSensitive: false,
  );

  /// Cleans a song title by stripping file extensions, track numbers, and noise brackets.
  static String cleanTitle(String rawTitle) {
    var title = rawTitle.trim();
    title = title.replaceAll(_fileExtensionPattern, '');
    title = title.replaceAll(_trackNumberPattern, '');
    title = title.replaceAll(_tagBracketPattern, '');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? rawTitle.trim() : title;
  }

  /// Extracts the primary artist by taking the first credit before multi-artist delimiters.
  static String cleanArtist(String? rawArtist) {
    if (rawArtist == null) return '';
    var artist = rawArtist.trim();
    if (artist.isEmpty) return '';
    artist = artist.replaceAll(_fileExtensionPattern, '');
    artist = artist.replaceAll(_trackNumberPattern, '');
    artist = artist.replaceAll(_tagBracketPattern, '');

    // ponytail: bands with & or , in the name split, upgrade with an exceptions list if users report it
    final parts = artist.split(_multiArtistDelimiter);
    final primary = parts.first.replaceAll(RegExp(r'\s+'), ' ').trim();
    return primary.isEmpty ? artist : primary;
  }

  /// Sanitizes raw offline metadata into a clean title and primary artist.
  static CleanEntity cleanEntity(String rawTitle, String? rawArtist) {
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

  /// Ensures persisted cache is loaded into memory, pruning expired entries (capped at 500).
  static Future<void> initCache() async {
    if (_loaded) return;
    try {
      final raw = await LocalJsonStore.read(_cacheStoreKey);
      if (raw is Map) {
        final entries = <MapEntry<String, ResolverCacheEntry>>[];
        for (final e in raw.entries) {
          if (e.value is Map) {
            final entry = ResolverCacheEntry.fromJson(
              (e.value as Map).cast<String, dynamic>(),
            );
            if (!entry.isExpired) {
              entries.add(MapEntry(e.key.toString(), entry));
            }
          }
        }
        // Cap at 500 newest entries
        if (entries.length > 500) {
          entries.sort(
            (a, b) => b.value.resolvedAt.compareTo(a.value.resolvedAt),
          );
          entries.length = 500;
        }
        _memoryCache.clear();
        _memoryCache.addEntries(entries);
      }
      _loaded = true;
    } catch (e) {
      LoggerHelper.write('$_tag: initCache failed', e);
    }
  }

  /// Clears negative resolver entries on refresh so songs get another try (Doc 23 §8).
  static Future<void> clearNegativeCache() async {
    await initCache();
    _memoryCache.removeWhere((_, entry) => entry.isNegative);
    await _persistCache();
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

  /// Bounded worker pool preserving input order (fixes B3, §5.4).
  static Future<List<R>> mapPool<T, R>(
    List<T> items,
    int n,
    Future<R?> Function(T) f,
  ) async {
    final out = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final i = next++;
        try {
          out[i] = await f(items[i]);
        } catch (_) {}
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(n, items.length); w++) worker(),
    ]);
    return out.whereType<R>().toList();
  }

  static String _normalizeForMatch(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), '')
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double _jaccardOverlap(String a, String b) {
    final setA = a.split(' ').where((s) => s.isNotEmpty).toSet();
    final setB = b.split(' ').where((s) => s.isNotEmpty).toSet();
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  /// Evaluates candidates against local metadata (fixes B4, §5.3).
  /// Excludes podcasts, prioritizes ATV > OMV, verifies title overlap/Jaccard,
  /// verifies artist containment, and enforces duration <= 10s difference.
  static OnlineSong? pickBestMatch({
    required List<OnlineSong> candidates,
    required String localTitle,
    required String localArtist,
    int? localDurationMs,
  }) {
    // 1. Exclude podcasts, order: ATV > OMV > anything else (§5.3)
    final filtered =
        candidates.where((s) => s.videoType != videoTypePodcast).toList()
          ..sort((a, b) {
            int priority(OnlineSong s) {
              if (s.videoType == videoTypeAlbum) return 0;
              if (s.videoType == 'MUSIC_VIDEO_TYPE_OMV') return 1;
              return 2;
            }

            return priority(a).compareTo(priority(b));
          });

    final normLocalTitle = _normalizeForMatch(localTitle);
    final normLocalArtist = _normalizeForMatch(localArtist);

    for (final cand in filtered) {
      // 2. Title verification: one contains other or Jaccard token overlap >= 0.6
      final normCandTitle = _normalizeForMatch(cand.title);
      final titlePass =
          normCandTitle.contains(normLocalTitle) ||
          normLocalTitle.contains(normCandTitle) ||
          _jaccardOverlap(normCandTitle, normLocalTitle) >= 0.6;
      if (!titlePass) continue;

      // 3. Artist verification: candidate artist contains primary artist or reverse
      if (normLocalArtist.isNotEmpty) {
        final normCandArtist = _normalizeForMatch(cand.artist ?? '');
        final artistPass =
            normCandArtist.contains(normLocalArtist) ||
            normLocalArtist.contains(normCandArtist);
        if (!artistPass) continue;
      }

      // 4. Duration verification: within 10s if both known
      if (localDurationMs != null &&
          localDurationMs > 0 &&
          cand.durationMs != null &&
          cand.durationMs! > 0) {
        if ((cand.durationMs! - localDurationMs).abs() > 10000) continue;
      }

      return cand;
    }
    return null;
  }

  /// Resolves an offline song to YouTube Music videoId and radio playlist ID
  /// with match verification and negative caching (fixes B4, B5, §5.3).
  static Future<TasteSeed?> resolveSong(
    String rawTitle,
    String? rawArtist, {
    int? durationMs,
    double score = 1.0,
  }) async {
    await initCache();
    final clean = cleanEntity(rawTitle, rawArtist);
    if (clean.title.isEmpty) return null;

    final key = 'song|${cacheKey(clean.title, clean.primaryArtist)}';
    final cached = _memoryCache[key];
    if (cached != null && !cached.isExpired) {
      if (cached.isNegative) return null;
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
      if (songs.isEmpty) {
        _recordNegativeSong(key);
        return null;
      }

      final match = pickBestMatch(
        candidates: songs,
        localTitle: clean.title,
        localArtist: clean.primaryArtist,
        localDurationMs: durationMs,
      );

      if (match == null) {
        _recordNegativeSong(key);
        return null;
      }

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

  static void _recordNegativeSong(String key) {
    _memoryCache[key] = ResolverCacheEntry(
      videoId: '',
      artistBrowseId: null,
      radioPlaylistId: '',
      resolvedAt: DateTime.now(),
    );
    unawaited(_persistCache());
  }

  /// Resolves an artist to YouTube Music browseId with exact match verification (fixes B6).
  static Future<String?> resolveArtistBrowseId(String rawArtist) async {
    await initCache();
    final clean = cleanArtist(rawArtist);
    if (clean.isEmpty) return null;

    final key = 'artist|${clean.toLowerCase()}';
    final cached = _memoryCache[key];
    if (cached != null && !cached.isExpired) {
      return cached.isNegative ? null : cached.artistBrowseId;
    }

    try {
      final collections = await OnlineApi.searchCollections(
        clean,
        CollectionKind.artist,
        automatic: true,
      );

      final normClean = _normalizeForMatch(clean);
      final match = collections.where((c) {
        return c.kind == CollectionKind.artist &&
            _normalizeForMatch(c.title) == normClean;
      }).firstOrNull;

      if (match != null && match.browseId.isNotEmpty) {
        _memoryCache[key] = ResolverCacheEntry(
          videoId: '',
          artistBrowseId: match.browseId,
          radioPlaylistId: '',
          resolvedAt: DateTime.now(),
        );
        unawaited(_persistCache());
        return match.browseId;
      }

      // Negative cache on miss (fixes B5, B6)
      _memoryCache[key] = ResolverCacheEntry(
        videoId: '',
        artistBrowseId: null,
        radioPlaylistId: '',
        resolvedAt: DateTime.now(),
      );
      unawaited(_persistCache());
    } catch (e) {
      LoggerHelper.write('$_tag: resolveArtistBrowseId failed for $clean', e);
    }
    return null;
  }

  /// Resolves a batch of seeds with concurrency throttled via mapPool (fixes B3).
  /// Caps seeds per rebuild: at most 5 song searches and 2 artist searches (§2 Rule 1).
  static Future<List<TasteSeed>> resolveSeeds(
    List<TasteSeed> seeds, {
    int maxConcurrent = 3,
  }) async {
    final capped = seeds.take(5).toList();
    final results = await mapPool<TasteSeed, TasteSeed>(capped, maxConcurrent, (
      seed,
    ) async {
      if (seed.videoId != null) return seed;
      return resolveSong(seed.title, seed.artist, score: seed.score);
    });
    return results;
  }
}
