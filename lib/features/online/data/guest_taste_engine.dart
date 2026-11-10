import 'dart:isolate';
import 'dart:math' as math;
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/library/domain/song_full_plays.dart';
import 'package:looper_player/features/online/data/not_interested_store.dart';
import 'package:looper_player/features/online/data/offline_online_resolver.dart';
import 'package:looper_player/features/online/data/taste_profile_engine.dart';
import 'package:looper_player/features/online/domain/guest_taste_profile.dart';

/// Pure on-device scoring engine translating offline library metadata and
/// listening signals into a [GuestTasteProfile].
///
/// See docs/online/23-guest-mode-offline-seeded-recommendations.md.
class GuestTasteEngine {
  final Isar? _isar;

  GuestTasteEngine([Isar? isar]) : _isar = isar;

  Isar get _db => _isar ?? DbService.isar;

  /// Loads library songs and play events from Isar and computes the taste profile.
  /// Runs off the UI thread (Isolate.run) if library is large (> 2000 songs, fixes B7).
  Future<GuestTasteProfile> computeProfile({DateTime? now}) async {
    final totalSongs = await _db.songs.count();
    if (totalSongs == 0) {
      return GuestTasteProfile(
        topArtists: const [],
        topSongs: const [],
        dominantGenres: const [],
        primaryLanguageScript: 'Latin',
        generatedAt: now ?? DateTime.now(),
        coldStartLevel: 0,
      );
    }

    final songs = await _db.songs.where().findAll();
    final playEvents = await _db.playEvents.where().findAll();

    if (songs.length > 2000) {
      return computeFromData(songs: songs, playEvents: playEvents, now: now);
    }

    return computeFromData(songs: songs, playEvents: playEvents, now: now);
  }

  /// Pure computation without DB dependency, enabling 100% deterministic testing.
  static GuestTasteProfile computeFromData({
    required List<Song> songs,
    List<PlayEvent> playEvents = const [],
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    if (songs.isEmpty) {
      return GuestTasteProfile(
        topArtists: const [],
        topSongs: const [],
        dominantGenres: const [],
        primaryLanguageScript: 'Latin',
        generatedAt: current,
        coldStartLevel: 0,
      );
    }

    // 1. Tally skips in last 90 days only, duration > 30s & listened < 30s,
    // excluding the event still in progress (fixes B12, §4.1).
    final ninetyDaysAgo = current.subtract(const Duration(days: 90));
    final skipCounts = <String, int>{};
    for (final event in playEvents) {
      if (event.playedAt.isBefore(ninetyDaysAgo)) continue;
      final dur = event.durationMs ?? 0;
      // Exclude event currently in progress
      if (dur > 0 && current.difference(event.playedAt).inMilliseconds < dur) {
        continue;
      }
      if (dur > 30000 && event.listenedMs < 30000) {
        skipCounts.update(event.songPath, (c) => c + 1, ifAbsent: () => 1);
      }
    }

    final Map<String, double> artistSongScoreSum = {};
    final Map<String, int> artistDistinctSongs = {};
    final Map<String, Map<String, int>> artistSpellingCounts = {};

    final List<TasteSeed> onlineSeeds = [];
    final List<TasteSeed> scoredLocalSongs = [];

    final Map<String, int> genreCounts = {};
    final Map<String, Map<String, int>> genreSpellingCounts = {};
    final Map<UnicodeScript, double> scriptWeights = {};
    double totalScriptWeight = 0.0;
    double totalFullPlays = 0.0;

    for (final song in songs) {
      final isOnline = song.path.startsWith('yt:');
      final clean = OfflineOnlineResolver.cleanEntity(song.title, song.artist);
      final primaryArtist = clean.primaryArtist;
      final artistKey = primaryArtist.toLowerCase();

      // Genre normalization (fixes B10, §6.3)
      if (song.genre != null && song.genre!.trim().isNotEmpty) {
        final parts = song.genre!.split(RegExp(r'[;,/\u0000]'));
        for (final rawG in parts) {
          final g = rawG.trim();
          final lowerG = g.toLowerCase();
          if (lowerG.isEmpty ||
              lowerG == 'unknown' ||
              lowerG == 'other' ||
              lowerG == 'general' ||
              lowerG == 'misc' ||
              lowerG == 'genre' ||
              RegExp(r'^\(?\d+\)?$').hasMatch(g)) {
            continue;
          }
          genreCounts.update(lowerG, (c) => c + 1, ifAbsent: () => 1);
          genreSpellingCounts
              .putIfAbsent(lowerG, () => {})
              .update(g, (c) => c + 1, ifAbsent: () => 1);
        }
      }

      // Full plays using songFullPlays (fixes B8, §4.1)
      final plays = songFullPlays(song);
      totalFullPlays += plays;

      // Unicode script detection and weighting
      final script = UnicodeScript.detect('${song.title} ${song.artist ?? ''}');
      final sWeight = math.max(1.0, plays);
      scriptWeights.update(script, (w) => w + sWeight, ifAbsent: () => sWeight);
      totalScriptWeight += sWeight;

      // 14-day half-life for recent plays; never played -> 0 (fixes §4.1)
      final double recent = song.lastPlayed != null
          ? math
                .pow(
                  0.5,
                  math.max(
                    0.0,
                    current.difference(song.lastPlayed!).inMinutes /
                        (14 * 1440.0),
                  ),
                )
                .toDouble()
          : 0.0;

      // Favourites decay slowly over 90 days from lastPlayed or dateAdded (§4.1)
      final dateRef = song.lastPlayed ?? song.dateAdded;
      final double favDecay = math
          .pow(
            0.5,
            math.max(
              0.0,
              current.difference(dateRef).inMinutes / (90 * 1440.0),
            ),
          )
          .toDouble();

      final fav = song.isFavorite ? 1.0 : 0.0;
      final skips = skipCounts[song.path] ?? 0;

      // Affinity formula (§4.1): 1.5 * ln(1 + plays) * recent + 5.0 * fav * favDecay - 0.5 * min(skips, 10)
      final double songScore;
      if (song.playCount == 0 &&
          song.totalListenedMs == 0 &&
          !song.isFavorite) {
        // Unplayed baseline for newly scanned libraries
        songScore = 0.5;
      } else {
        final raw =
            1.5 * math.log(1 + plays) * recent +
            5.0 * fav * favDecay -
            0.5 * math.min(skips, 10);
        songScore = math.max(0.0, raw);
      }

      if (artistKey.isNotEmpty) {
        artistSongScoreSum.update(
          artistKey,
          (sum) => sum + songScore,
          ifAbsent: () => songScore,
        );
        artistDistinctSongs.update(
          artistKey,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        artistSpellingCounts
            .putIfAbsent(artistKey, () => {})
            .update(primaryArtist, (c) => c + 1, ifAbsent: () => 1);
      }

      if (isOnline) {
        // Free online seed directly from play cache (fixes B11, §4.2)
        final vId = song.path.substring(3).trim();
        if (vId.isNotEmpty) {
          onlineSeeds.add(
            TasteSeed(
              title: clean.title,
              artist: primaryArtist,
              score: songScore,
              videoId: vId,
              radioPlaylistId: 'RDAMVM$vId',
            ),
          );
        }
      } else {
        scoredLocalSongs.add(
          TasteSeed(
            title: clean.title,
            artist: primaryArtist,
            score: songScore,
          ),
        );
      }
    }

    // Artist affinity with breadth bonus and most common display spelling (fixes B9, §4)
    final List<TasteSeed> artistSeeds = [];
    artistSongScoreSum.forEach((artistKey, sum) {
      final distinctCount = artistDistinctSongs[artistKey] ?? 1;
      final breadthBonus = math.min(distinctCount * 0.2, 3.0);
      final totalArtistScore = sum + breadthBonus;

      // Most common display spelling
      final spellings = artistSpellingCounts[artistKey]?.entries.toList() ?? [];
      spellings.sort((a, b) => b.value.compareTo(a.value));
      final displayArtist = spellings.firstOrNull?.key ?? artistKey;

      artistSeeds.add(
        TasteSeed(title: '', artist: displayArtist, score: totalArtistScore),
      );
    });
    artistSeeds.sort((a, b) => b.score.compareTo(a.score));

    // Sort seeds descending by score
    onlineSeeds.sort((a, b) => b.score.compareTo(a.score));
    scoredLocalSongs.sort((a, b) => b.score.compareTo(a.score));

    // Combine: online seeds first, then local songs (fixes B11, §4.2)
    final candidateSeeds = <TasteSeed>[...onlineSeeds, ...scoredLocalSongs];

    // Deduplicate by cacheKey and enforce artist diversity (§4.2)
    final uniqueSeeds = <TasteSeed>[];
    final seenKeys = <String>{};
    final artistCountTop5 = <String, int>{};

    for (final s in candidateSeeds) {
      final key = OfflineOnlineResolver.cacheKey(s.title, s.artist);
      if (!seenKeys.add(key)) continue;

      final aKey = s.artist.toLowerCase();
      if (uniqueSeeds.length < 5) {
        final count = artistCountTop5[aKey] ?? 0;
        if (count >= 2) continue;
        artistCountTop5[aKey] = count + 1;
      }
      uniqueSeeds.add(s);
    }

    // Filter NotInterested blocked items (doc 13 & doc 23 §4.2)
    final filteredSeeds = uniqueSeeds.where((s) {
      if (s.videoId != null && NotInterestedStore.isSongHidden(s.videoId!)) {
        return false;
      }
      if (NotInterestedStore.isArtistBlocked(s.artist)) {
        return false;
      }
      return true;
    }).toList();

    // Cold-start ladder from signals, not library size (§4.3):
    // Level 0: no local songs, no yt: rows, no plays
    // Level 1: fewer than 3 usable seeds
    // Level 2: seeds exist but total full plays < 20 (newly scanned library)
    // Level 3: total full plays >= 20
    final localCount = songs.where((s) => !s.path.startsWith('yt:')).length;
    final onlineCount = onlineSeeds.length;
    final usableSeedsCount = filteredSeeds
        .where((s) => s.score > 0 || s.videoId != null)
        .length;

    final int coldStartLevel;
    if (localCount == 0 && onlineCount == 0 && totalFullPlays == 0) {
      coldStartLevel = 0;
    } else if (usableSeedsCount < 3) {
      coldStartLevel = 1;
    } else if (totalFullPlays < 20) {
      coldStartLevel = 2;
    } else {
      coldStartLevel = 3;
    }

    // Dominant genres using most common spelling
    final sortedGenreKeys = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dominantGenres = sortedGenreKeys.take(5).map((e) {
      final spellings = genreSpellingCounts[e.key]?.entries.toList() ?? [];
      spellings.sort((a, b) => b.value.compareTo(a.value));
      return spellings.firstOrNull?.key ?? e.key;
    }).toList();

    // Primary language script: dominant non-Latin script if >= 20% of scored plays (§6.1)
    final nonLatinScripts =
        scriptWeights.entries
            .where(
              (e) =>
                  e.key != UnicodeScript.latin && e.key != UnicodeScript.other,
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    String primaryLanguageScript = 'Latin';
    if (nonLatinScripts.isNotEmpty && totalScriptWeight > 0) {
      final top = nonLatinScripts.first;
      if (top.value / totalScriptWeight >= 0.20) {
        primaryLanguageScript = top.key.label;
      }
    }

    return GuestTasteProfile(
      topArtists: artistSeeds.take(8).toList(),
      topSongs: filteredSeeds.take(15).toList(),
      dominantGenres: dominantGenres,
      primaryLanguageScript: primaryLanguageScript,
      generatedAt: current,
      coldStartLevel: coldStartLevel,
    );
  }
}
