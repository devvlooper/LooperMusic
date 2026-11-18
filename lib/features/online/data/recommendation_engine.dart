import 'dart:math' as math;

import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/not_interested_store.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/online_cache.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_profile_engine.dart';
import 'package:looper_player/features/online/data/taste_profile_store.dart';

/// What the user listens to, built from local data only.
class TasteProfile {
  const TasteProfile({
    required this.topArtists,
    required this.topOnlineIds,
    required this.recentSearches,
    required this.genres,
    this.profiles = const [],
  });

  /// Played and stated artists, alternating, best first.
  final List<String> topArtists;

  /// Video ids of the highest-scoring online songs (radio seeds).
  final List<String> topOnlineIds;
  final List<String> recentSearches;
  final List<String> genres;
  final List<TasteProfileCluster> profiles;

  bool get isEmpty =>
      topArtists.isEmpty &&
      topOnlineIds.isEmpty &&
      recentSearches.isEmpty &&
      genres.isEmpty &&
      profiles.isEmpty;
}

/// The suggestion analyser (docs/online/07-recommendations.md and 13-taste-profiles.md).
abstract final class RecommendationEngine {
  static const _tag = 'RecommendationEngine';

  /// Builds or retrieves the cached taste profile snapshot.
  static Future<TasteProfile> buildProfile({bool force = false}) async {
    final snapshot = await TasteProfileStore.getOrBuild(force: force);
    return TasteProfile(
      topArtists: snapshot.topArtists,
      topOnlineIds: snapshot.topOnlineIds,
      recentSearches: snapshot.recentSearches,
      genres: snapshot.genres,
      profiles: snapshot.profiles,
    );
  }

  /// Songs to append when the queue runs low: YouTube's radio for the
  /// current song first, then songs by top artists, ranked by taste.
  static Future<List<Song>> queueContinuation(
    Song current,
    Set<String> excludePaths, {
    int limit = 10,
  }) async {
    await NotInterestedStore.load();
    final snapshot = await TasteProfileStore.getOrBuild();
    final results = <OnlineSong>[];

    int fresh() => results
        .where(
          (s) =>
              !excludePaths.contains(s.path) &&
              !NotInterestedStore.isBlocked(s),
        )
        .length;

    try {
      var seed = current.videoId;
      if (seed == null) {
        // A local song: find it online and use its radio.
        final (found, _) = await OnlineApi.searchSongs(
          '${current.title} ${current.artist ?? ''}'.trim(),
          automatic: true,
        );
        seed = found.firstOrNull?.videoId;
      }
      if (seed != null) {
        // Fan uploads (lyric videos, slowed/lofi edits) are other
        // recordings: their timing breaks album lyrics and they sound off.
        results.addAll(
          (await OnlineApi.radio(
            seed,
            automatic: true,
          )).where((s) => s.videoType != videoTypeFanUpload),
        );
      }
    } catch (e) {
      LoggerHelper.write('$_tag: radio failed', e);
    }

    if (fresh() < limit) {
      for (final artist in (snapshot.topArtists.toList()..shuffle()).take(2)) {
        try {
          final (s, _) = await OnlineApi.searchSongs(
            '$artist songs',
            automatic: true,
          );
          results.addAll(s);
        } catch (_) {}
        if (fresh() >= limit) break;
      }
    }

    final recentPlays = await _recentSongPaths(days: 3);
    final ranked = rankCandidates(
      results,
      snapshot,
      recentPaths: recentPlays,
      blockedArtists: NotInterestedStore.blockedArtists,
      hiddenSongs: NotInterestedStore.hiddenSongIds,
      limit: limit * 2,
    );

    final seen = <String>{};
    return ranked
        .where((s) => !excludePaths.contains(s.path) && seen.add(s.videoId))
        .take(limit)
        .map((s) => s.toSong())
        .toList();
  }

  /// "For you": interleaves radio from a favourite online song, songs by
  /// top artists (or picked genres) and recent searches, then ranks by taste.
  static Future<List<OnlineSong>> forYou(TasteProfile p) async {
    await NotInterestedStore.load();
    final snapshot = await TasteProfileStore.getOrBuild();
    final forYouTraits = snapshot.traitQueries(max: 2);

    final sources = <Future<List<OnlineSong>>>[
      if (p.topOnlineIds.isNotEmpty)
        _safe(
          () => OnlineApi.radio(
            p.topOnlineIds[math.Random().nextInt(
              math.min(3, p.topOnlineIds.length),
            )],
            automatic: true,
          ),
        ),
      // Learned genres, moods and kinds of song ("hindi lofi songs") take
      // artist slots rather than adding requests.
      for (final q in forYouTraits) _songs(q),
      for (final a in p.topArtists.take(5 - forYouTraits.length))
        _songs('$a songs'),
      if (p.topArtists.isEmpty)
        for (final g in p.genres.take(3)) _songs('$g songs'),
      for (final q in p.recentSearches.take(2)) _songs(q),
    ];

    final unranked = _interleave(await Future.wait(sources), 60);
    final recentPlays = await _recentSongPaths(days: 3);

    return rankCandidates(
      unranked,
      snapshot,
      recentPaths: recentPlays,
      blockedArtists: NotInterestedStore.blockedArtists,
      hiddenSongs: NotInterestedStore.hiddenSongIds,
      limit: 30,
    );
  }

  /// "Discover": songs the user has not heard, from new releases of their
  /// artists and radios that reach sideways. Known songs are dropped.
  static Future<List<OnlineSong>> discover(TasteProfile p) async {
    await NotInterestedStore.load();
    final snapshot = await TasteProfileStore.getOrBuild();
    final discoverTraits = snapshot.traitQueries(max: 1);

    final known =
        (await DbService.isar.songs
                .filter()
                .pathStartsWith('yt:')
                .pathProperty()
                .findAll())
            .toSet();

    final sources = <Future<List<OnlineSong>>>[
      for (final a in p.topArtists.take(5 - discoverTraits.length))
        _songs('$a latest songs'),
      for (final q in discoverTraits) _songs('new $q'),
      for (final id in p.topOnlineIds.skip(1).take(2))
        _safe(() => OnlineApi.radio(id, automatic: true)),
      for (final g in p.genres.take(2)) _songs('new $g songs'),
      if (p.isEmpty) _songs('new music'),
    ];

    final unranked = _interleave(
      await Future.wait(sources),
      60,
    ).where((s) => !known.contains(s.path)).toList();

    final recentPlays = await _recentSongPaths(days: 3);

    return rankCandidates(
      unranked,
      snapshot,
      recentPaths: recentPlays,
      blockedArtists: NotInterestedStore.blockedArtists,
      hiddenSongs: NotInterestedStore.hiddenSongIds,
      limit: 30,
    );
  }

  /// Home shows one shelf per profile ("Mix: Rock", localized "Mix: %s"),
  /// seeded by 2 of its artists plus a radio of its best online song.
  static Future<List<OnlineShelf>> buildMixShelves(
    List<TasteProfileCluster> profiles,
  ) async {
    if (profiles.isEmpty) return const [];
    await NotInterestedStore.load();
    final snapshot = await TasteProfileStore.getOrBuild();
    final recentPlays = await _recentSongPaths(days: 3);

    final shelves = <OnlineShelf>[];

    for (final cluster in profiles) {
      final sources = <Future<List<OnlineSong>>>[
        for (final artist in cluster.topArtists.take(2))
          _songs('$artist songs'),
        if (cluster.topOnlineSeedIds.isNotEmpty)
          _safe(
            () => OnlineApi.radio(
              cluster.topOnlineSeedIds.first,
              automatic: true,
            ),
          ),
      ];

      final unranked = _interleave(await Future.wait(sources), 30);
      final ranked = rankCandidates(
        unranked,
        snapshot,
        recentPaths: recentPlays,
        blockedArtists: NotInterestedStore.blockedArtists,
        hiddenSongs: NotInterestedStore.hiddenSongIds,
        limit: 15,
      );

      if (ranked.isNotEmpty) {
        shelves.add(OnlineShelf(cluster.displayTitle, songs: ranked));
      }
    }

    return shelves;
  }

  /// Re-orders already fetched suggestions against the latest profile, with
  /// no network: plays apply to what Home shows right away.
  static Future<List<OnlineSong>> rerank(List<OnlineSong> songs) async {
    if (songs.isEmpty) return songs;
    await NotInterestedStore.load();
    final snapshot = await TasteProfileStore.getOrBuild();
    return rankCandidates(
      songs,
      snapshot,
      recentPaths: await _recentSongPaths(days: 1),
      blockedArtists: NotInterestedStore.blockedArtists,
      hiddenSongs: NotInterestedStore.hiddenSongIds,
      limit: songs.length,
    );
  }

  static Future<Set<String>> _recentSongPaths({int days = 3}) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final recent = await DbService.isar.playEvents
          .filter()
          .playedAtGreaterThan(since)
          .songPathProperty()
          .findAll();
      return recent.toSet();
    } catch (_) {
      return const {};
    }
  }

  /// How old a saved background search may be. Home sets it per load:
  /// 6 h normally, 30 min on pull-to-refresh.
  static Duration searchMaxAge = const Duration(hours: 6);

  static const _searchCacheKey = 'rec_search_cache_v1';
  static const _searchCacheMax = 120;
  static Map<String, dynamic>? _searchCache;
  static final _inFlight = <String, Future<List<OnlineSong>>>{};

  /// A background search, answered from disk while fresh: "Artist songs"
  /// and the trait queries barely change in hours, and every request
  /// YouTube sees counts toward its bot check. Searches already running
  /// (For you and a Mix asking for the same artist) are shared.
  static Future<List<OnlineSong>> _songs(String q) {
    final key = q.trim().toLowerCase();
    return _inFlight[key] ??=
        _safe(() async {
          final cache = _searchCache ??= Map<String, dynamic>.from(
            (await LocalJsonStore.read(_searchCacheKey)) as Map? ?? const {},
          );
          final hit = cache[key];
          if (hit is Map && hit['at'] is int) {
            final at = DateTime.fromMillisecondsSinceEpoch(hit['at'] as int);
            if (DateTime.now().difference(at) < searchMaxAge) {
              return [
                for (final s in (hit['s'] as List? ?? const []))
                  ?OnlineSong.fromJson(s),
              ];
            }
          }
          final (songs, _) = await OnlineApi.searchSongs(q, automatic: true);
          cache.remove(key);
          cache[key] = {
            'at': DateTime.now().millisecondsSinceEpoch,
            's': [for (final s in songs) s.toJson()],
          };
          // Oldest first (insertion order): drop from the front.
          while (cache.length > _searchCacheMax) {
            cache.remove(cache.keys.first);
          }
          await LocalJsonStore.write(_searchCacheKey, cache);
          return songs;
          // A block, not `=> remove(key)`: remove returns this very future and
          // whenComplete would wait on it, so the search never finished (Home's
          // endless loading line).
        }).whenComplete(() {
          _inFlight.remove(key);
        });
  }

  /// One refused request empties only its own source.
  static Future<List<OnlineSong>> _safe(
    Future<List<OnlineSong>> Function() f,
  ) async {
    try {
      return await f();
    } catch (e) {
      LoggerHelper.write('$_tag: source failed', e);
      return const [];
    }
  }

  static List<OnlineSong> _interleave(List<List<OnlineSong>> lists, int max) {
    final out = <OnlineSong>[];
    final seen = <String>{};
    for (var i = 0; out.length < max; i++) {
      var any = false;
      for (final l in lists) {
        if (i < l.length) {
          any = true;
          if (seen.add(l[i].videoId)) out.add(l[i]);
        }
      }
      if (!any) break;
    }
    return out.take(max).toList();
  }
}
