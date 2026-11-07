import 'dart:math' as math;
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
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

    return computeFromData(
      songs: songs,
      playEvents: playEvents,
      now: now,
    );
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

    // Determine Cold-Start Level:
    // Level 1: 1 - 9 songs
    // Level 2: 10 - 100 songs, or low/no play history
    // Level 3: > 100 songs + active play history
    final hasActivePlayHistory = playEvents.isNotEmpty ||
        songs.any((s) => s.playCount > 0 || s.totalListenedMs > 0);

    final int coldStartLevel;
    if (songs.length < 10) {
      coldStartLevel = 1;
    } else if (songs.length > 100 && hasActivePlayHistory) {
      coldStartLevel = 3;
    } else {
      coldStartLevel = 2;
    }

    // 1. Tally skips per song path (skips < 30s where track duration > 30s)
    final skipCounts = <String, int>{};
    for (final event in playEvents) {
      final dur = event.durationMs ?? 0;
      if (dur > 30000 && event.listenedMs < 30000) {
        skipCounts.update(event.songPath, (c) => c + 1, ifAbsent: () => 1);
      }
    }

    // Weights per Section 3.1
    const wPlay = 1.5;
    const wFav = 5.0;
    const wSkip = 0.5;
    const tau = 14.0; // 14-day half-life
    const lambda = 0.0495105129; // ln(2) / 14

    final Map<String, double> artistSongScoreSum = {};
    final Map<String, int> artistDistinctSongs = {};
    final List<TasteSeed> scoredSongs = [];
    final Map<String, int> genreCounts = {};
    final Map<UnicodeScript, int> scriptCounts = {};

    final isColdLibrary = !hasActivePlayHistory;

    for (final song in songs) {
      final clean = OfflineOnlineResolver.cleanEntity(song.title, song.artist);
      final primaryArtist = clean.primaryArtist;

      // Track genre
      if (song.genre != null && song.genre!.trim().isNotEmpty) {
        final g = song.genre!.trim();
        final lowerG = g.toLowerCase();
        if (lowerG != 'unknown' && lowerG != 'general' && lowerG != 'other') {
          genreCounts.update(g, (c) => c + 1, ifAbsent: () => 1);
        }
      }

      // Track Unicode script from title & artist
      final script = UnicodeScript.detect('${song.title} ${song.artist ?? ''}');
      scriptCounts.update(script, (c) => c + 1, ifAbsent: () => 1);

      final double songScore;
      if (isColdLibrary) {
        // Cold library baseline: track count baseline + explicit favorite boost
        songScore = song.isFavorite ? 5.0 : 1.0;
      } else {
        // Wall-clock completion ratio: totalListenedMs / max(duration, 210000)
        final effectiveDuration = math.max(song.duration ?? 210000, 210000);
        final completionRatio = song.totalListenedMs / effectiveDuration;

        final fav = song.isFavorite ? 1.0 : 0.0;
        final skips = skipCounts[song.path] ?? 0;

        // Exponential decay: delta_t is days since lastPlayed
        final deltaDays = song.lastPlayed != null
            ? current.difference(song.lastPlayed!).inMinutes / 1440.0
            : 30.0;
        final decay = math.exp(-lambda * math.max(0.0, deltaDays));

        // Affinity(s) formula
        final rawScore = (completionRatio * wPlay + fav * wFav - skips * wSkip);
        songScore = math.max(0.0, rawScore) * decay;
      }

      if (primaryArtist.isNotEmpty) {
        artistSongScoreSum.update(
          primaryArtist,
          (sum) => sum + songScore,
          ifAbsent: () => songScore,
        );
        artistDistinctSongs.update(
          primaryArtist,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      if (songScore > 0 || isColdLibrary) {
        scoredSongs.add(TasteSeed(
          title: clean.title,
          artist: primaryArtist,
          score: songScore,
        ));
      }
    }

    // Calculate Artist Affinities with breadth bonus per Section 3.2:
    // Affinity(A) = sum(Affinity(s)) + min(|Songs(A)| * 0.2, 3.0)
    final List<TasteSeed> artistSeeds = [];
    artistSongScoreSum.forEach((artist, sum) {
      final distinctCount = artistDistinctSongs[artist] ?? 1;
      final breadthBonus = math.min(distinctCount * 0.2, 3.0);
      final totalArtistScore = sum + breadthBonus;

      artistSeeds.add(TasteSeed(
        title: '',
        artist: artist,
        score: totalArtistScore,
      ));
    });

    // Sort descending
    artistSeeds.sort((a, b) => b.score.compareTo(a.score));
    scoredSongs.sort((a, b) => b.score.compareTo(a.score));

    // Deduplicate scored songs by title + artist
    final uniqueSongs = <TasteSeed>[];
    final seenSongKeys = <String>{};
    for (final s in scoredSongs) {
      final key = OfflineOnlineResolver.cacheKey(s.title, s.artist);
      if (seenSongKeys.add(key)) {
        uniqueSongs.add(s);
      }
    }

    // Top genres
    final sortedGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dominantGenres = sortedGenres.take(5).map((e) => e.key).toList();

    // Primary language script (prefer top non-Latin script if present)
    final nonLatinScripts = scriptCounts.entries
        .where((e) => e.key != UnicodeScript.latin && e.key != UnicodeScript.other)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final String primaryLanguageScript = nonLatinScripts.isNotEmpty
        ? nonLatinScripts.first.key.label
        : 'Latin';

    return GuestTasteProfile(
      topArtists: artistSeeds.take(8).toList(),
      topSongs: uniqueSongs.take(15).toList(),
      dominantGenres: dominantGenres,
      primaryLanguageScript: primaryLanguageScript,
      generatedAt: current,
      coldStartLevel: coldStartLevel,
    );
  }
}
