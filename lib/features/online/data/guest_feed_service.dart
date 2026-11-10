import 'dart:math' as math;
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/guest_taste_engine.dart';
import 'package:looper_player/features/online/data/not_interested_store.dart';
import 'package:looper_player/features/online/data/offline_online_resolver.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/domain/guest_taste_profile.dart';

/// Synthesizes personalized YouTube Music shelves for unauthenticated Guest Mode users
/// by converting offline library signals into online radio streams and artist feeds.
///
/// See docs/online/23-guest-mode-offline-seeded-recommendations.md.
class GuestFeedService {
  static const _tag = 'GuestFeedService';

  final GuestTasteEngine _engine;

  GuestFeedService([GuestTasteEngine? engine])
    : _engine = engine ?? GuestTasteEngine();

  /// Builds the complete guest home feed.
  Future<List<OnlineShelf>> buildGuestFeed({
    GuestTasteProfile? profile,
    bool force = false,
  }) async {
    await NotInterestedStore.load();
    final taste = profile ?? await _engine.computeProfile();

    final List<OnlineShelf> rawShelves;
    switch (taste.coldStartLevel) {
      case 0:
        rawShelves = await _buildLevel0ExploreFeed(force: force);
        break;
      case 1:
        rawShelves = await _buildLevel1SeedlingFeed(taste);
        break;
      case 2:
        rawShelves = await _buildLevel2GrowingFeed(taste);
        break;
      case 3:
      default:
        rawShelves = await _buildLevel3ThrivingFeed(taste);
        break;
    }

    return filterAndEnforceExploration(rawShelves);
  }

  /// Level 0: Empty device -> Standard explore/trending fallback.
  Future<List<OnlineShelf>> _buildLevel0ExploreFeed({
    bool force = false,
  }) async {
    try {
      final (shelves, _) = await OnlineApi.home(automatic: !force, pages: 2);
      if (shelves.isNotEmpty) return shelves;
    } catch (e) {
      LoggerHelper.write('$_tag: Level 0 home fallback failed', e);
    }
    return _buildGenreShelf(
      'Top Global Music Charts',
      'top music charts',
      null,
    );
  }

  /// Level 1: fewer than 3 usable seeds -> 1 radio + 1 artist shelf, then public home.
  Future<List<OnlineShelf>> _buildLevel1SeedlingFeed(
    GuestTasteProfile taste,
  ) async {
    final shelves = <OnlineShelf>[];
    final resolvedSongs = await OfflineOnlineResolver.resolveSeeds(
      taste.topSongs.take(3).toList(),
      maxConcurrent: 3,
    );

    // 1. Radio for the primary available track
    if (resolvedSongs.isNotEmpty && resolvedSongs.first.videoId != null) {
      final seed = resolvedSongs.first;
      final radioTracks = await _safe(
        () => OnlineApi.radio(seed.videoId!, automatic: true),
      );
      if (radioTracks.isNotEmpty) {
        shelves.add(
          OnlineShelf(
            'Radio: based on ${seed.title}',
            kind: ShelfKind.guestRadio,
            args: [seed.title],
            songs: radioTracks,
            moreBrowseId: 'RDAMVM${seed.videoId}',
            shelfType: OnlineShelfType.heroSpotlight,
          ),
        );
      }
    }

    // 2. Artist Shelf for the top artist
    if (taste.topArtists.isNotEmpty) {
      final artistName = taste.topArtists.first.artist;
      final artistSongs = await _safe(() => _searchSongs('$artistName songs'));
      if (artistSongs.isNotEmpty) {
        shelves.add(
          OnlineShelf(
            'Because you listen to $artistName',
            kind: ShelfKind.guestBecause,
            args: [artistName],
            songs: artistSongs,
            shelfType: OnlineShelfType.standardCards,
          ),
        );
      }
    }

    return shelves;
  }

  /// Level 2: seeds exist but full plays < 20 -> Quick Picks from favourites + artist + genre shelves.
  Future<List<OnlineShelf>> _buildLevel2GrowingFeed(
    GuestTasteProfile taste,
  ) async {
    final shelves = <OnlineShelf>[];

    final resolvedSongsFuture = OfflineOnlineResolver.resolveSeeds(
      taste.topSongs.take(3).toList(),
      maxConcurrent: 3,
    );
    final topArtist = taste.topArtists.firstOrNull?.artist;

    final results = await Future.wait([
      resolvedSongsFuture,
      topArtist != null
          ? OfflineOnlineResolver.resolveArtistBrowseId(topArtist)
          : Future<String?>.value(null),
    ]);

    final resolvedSongs = results[0] as List<TasteSeed>;
    final artistBrowseId = results[1] as String?;

    // 1. Quick Picks from available seeds
    if (resolvedSongs.isNotEmpty) {
      final quickPicks = await _buildQuickPicksShelf(resolvedSongs);
      if (quickPicks != null) shelves.add(quickPicks);
    }

    // 2. Artist Shelf (fetched once, B13)
    if (topArtist != null && topArtist.isNotEmpty) {
      final (artistShelf, _) = await _fetchArtistShelves(
        topArtist,
        artistBrowseId,
      );
      if (artistShelf != null) shelves.add(artistShelf);
    }

    // 3. Dominant Genre Exploration Shelf (§6.3, B16)
    final genreShelf = await _buildContextualGenreShelf(taste);
    if (genreShelf != null) shelves.add(genreShelf);

    return shelves;
  }

  /// Level 3: full plays >= 20 -> Full 6-shelf synthesized layout (§7.1).
  Future<List<OnlineShelf>> _buildLevel3ThrivingFeed(
    GuestTasteProfile taste,
  ) async {
    final shelves = <OnlineShelf>[];

    // Concurrently resolve up to 5 song seeds and top artist browse ID (fixes B14, pool of 3)
    final resolvedSongsFuture = OfflineOnlineResolver.resolveSeeds(
      taste.topSongs.take(5).toList(),
      maxConcurrent: 3,
    );
    final topArtistSeed = taste.topArtists.firstOrNull;
    final topArtistName = topArtistSeed?.artist;

    final resolvedArtistBrowseIdFuture = topArtistName != null
        ? OfflineOnlineResolver.resolveArtistBrowseId(topArtistName)
        : Future<String?>.value(null);

    final results = await Future.wait([
      resolvedSongsFuture,
      resolvedArtistBrowseIdFuture,
    ]);

    final resolvedSongs = results[0] as List<TasteSeed>;
    final artistBrowseId = results[1] as String?;

    final validSeeds = resolvedSongs.where((s) => s.videoId != null).toList();

    // Fetch seed 1 radio once (fixes B15)
    List<OnlineSong> seed1Radio = const [];
    if (validSeeds.isNotEmpty) {
      seed1Radio = await _safe(
        () => OnlineApi.radio(validSeeds.first.videoId!, automatic: true),
      );
    }

    // Shelf 1: Quick picks from your library (interleaved from seeds 2-4, fixes B15)
    final quickPickSeeds = validSeeds.skip(1).take(3).toList();
    if (quickPickSeeds.isNotEmpty) {
      final quickPicks = await _buildQuickPicksShelf(quickPickSeeds);
      if (quickPicks != null) shelves.add(quickPicks);
    } else if (seed1Radio.length > 5) {
      // Fallback: if only 1 seed is available, take a subset for Quick picks
      shelves.add(
        OnlineShelf(
          'Quick picks from your library',
          kind: ShelfKind.guestQuickPicks,
          songs: seed1Radio.skip(1).take(16).toList(),
          shelfType: OnlineShelfType.multiRowTracks,
        ),
      );
    }

    // Shelf 2: Radio: based on seed #1 (fixes B15)
    if (validSeeds.isNotEmpty && seed1Radio.isNotEmpty) {
      final seed1 = validSeeds.first;
      shelves.add(
        OnlineShelf(
          'Radio: based on ${seed1.title}',
          kind: ShelfKind.guestRadio,
          args: [seed1.title],
          songs: seed1Radio,
          moreBrowseId: 'RDAMVM${seed1.videoId}',
          shelfType: OnlineShelfType.heroSpotlight,
        ),
      );
    }

    // Shelves 3 & 4: Because you listen to [Artist 1] & Similar to [Artist 1] (single page() call, fixes B13)
    if (topArtistName != null && topArtistName.isNotEmpty) {
      final (becauseShelf, similarShelf) = await _fetchArtistShelves(
        topArtistName,
        artistBrowseId,
      );
      if (becauseShelf != null) shelves.add(becauseShelf);
      if (similarShelf != null) shelves.add(similarShelf);
    }

    // Shelf 5: More from [Artist 2]
    if (taste.topArtists.length > 1) {
      final artist2 = taste.topArtists[1].artist;
      final songs = await _safe(() => _searchSongs('$artist2 songs'));
      if (songs.isNotEmpty) {
        shelves.add(
          OnlineShelf(
            'More from $artist2',
            kind: ShelfKind.guestMoreFrom,
            args: [artist2],
            songs: songs.take(15).toList(),
            shelfType: OnlineShelfType.standardCards,
          ),
        );
      }
    }

    // Shelf 6: Trending in [Genre] (§6.3, fixes B16)
    final genreShelf = await _buildContextualGenreShelf(taste);
    if (genreShelf != null) shelves.add(genreShelf);

    return shelves;
  }

  /// Fetches an artist page once and extracts both top songs and similar artists (fixes B13).
  Future<(OnlineShelf?, OnlineShelf?)> _fetchArtistShelves(
    String artistName,
    String? browseId,
  ) async {
    OnlineShelf? becauseShelf;
    OnlineShelf? similarShelf;

    try {
      if (browseId != null && browseId.isNotEmpty) {
        final page = await OnlineApi.page(browseId);
        if (page.songs.isNotEmpty) {
          becauseShelf = OnlineShelf(
            'Because you listen to $artistName',
            kind: ShelfKind.guestBecause,
            args: [artistName],
            songs: page.songs,
            moreBrowseId: browseId,
            shelfType: OnlineShelfType.standardCards,
          );
        }

        // Look for similar artist carousel in the same page
        for (final shelf in page.shelves) {
          final isArtistShelf =
              shelf.collections.isNotEmpty &&
              shelf.collections.every((c) => c.kind == CollectionKind.artist);
          if (isArtistShelf || shelf.title.toLowerCase().contains('similar')) {
            similarShelf = OnlineShelf(
              'Similar to $artistName',
              kind: ShelfKind.guestSimilar,
              args: [artistName],
              collections: shelf.collections,
              shelfType: OnlineShelfType.artistCircles,
            );
            break;
          }
        }
      }

      // Fallbacks if page didn't have songs
      if (becauseShelf == null) {
        final songs = await _searchSongs('$artistName songs');
        if (songs.isNotEmpty) {
          becauseShelf = OnlineShelf(
            'Because you listen to $artistName',
            kind: ShelfKind.guestBecause,
            args: [artistName],
            songs: songs,
            shelfType: OnlineShelfType.standardCards,
          );
        }
      }

      // Fallback if page didn't have similar artists
      if (similarShelf == null) {
        final collections = await OnlineApi.searchCollections(
          artistName,
          CollectionKind.artist,
          automatic: true,
        );
        final artists = collections
            .where(
              (c) =>
                  c.kind == CollectionKind.artist &&
                  !c.title.toLowerCase().contains(artistName.toLowerCase()),
            )
            .take(8)
            .toList();
        if (artists.isNotEmpty) {
          similarShelf = OnlineShelf(
            'Similar to $artistName',
            kind: ShelfKind.guestSimilar,
            args: [artistName],
            collections: artists,
            shelfType: OnlineShelfType.artistCircles,
          );
        }
      }
    } catch (e) {
      LoggerHelper.write('$_tag: fetchArtistShelves failed for $artistName', e);
    }

    return (becauseShelf, similarShelf);
  }

  /// Builds contextual genre shelf using normalized genre or Unicode script fallback (§6.3, fixes B16).
  Future<OnlineShelf?> _buildContextualGenreShelf(
    GuestTasteProfile taste,
  ) async {
    final genre = taste.dominantGenres.firstOrNull;
    if (genre != null && genre.isNotEmpty) {
      final list = await _buildGenreShelf(
        'Trending in $genre',
        '$genre hits',
        genre,
      );
      return list.firstOrNull;
    }

    // Script fallback
    final scriptQuery = switch (taste.primaryLanguageScript) {
      'Devanagari' => 'Hindi hits',
      'Hangul' => 'K-pop hits',
      'Kana/Han' => 'J-pop hits',
      'Arabic' => 'Arabic hits',
      'Cyrillic' => 'Russian hits',
      _ => null,
    };

    if (scriptQuery != null) {
      final list = await _buildGenreShelf(
        'Trending in ${taste.primaryLanguageScript}',
        scriptQuery,
        taste.primaryLanguageScript,
      );
      return list.firstOrNull;
    }

    // With neither, drop the shelf entirely (fixes B16)
    return null;
  }

  /// Builds Quick Picks by interleaving radio streams from seeds.
  Future<OnlineShelf?> _buildQuickPicksShelf(List<TasteSeed> seeds) async {
    final validSeeds = seeds.where((s) => s.videoId != null).take(3).toList();
    if (validSeeds.isEmpty) return null;

    final radioFutures = validSeeds.map(
      (seed) => _safe(() => OnlineApi.radio(seed.videoId!, automatic: true)),
    );
    final radios = await Future.wait(radioFutures);

    final interleaved = _interleave(radios, 16);
    if (interleaved.isEmpty) return null;

    return OnlineShelf(
      'Quick picks from your library',
      kind: ShelfKind.guestQuickPicks,
      songs: interleaved,
      shelfType: OnlineShelfType.multiRowTracks,
    );
  }

  /// Builds a genre shelf with localized ShelfKind.
  Future<List<OnlineShelf>> _buildGenreShelf(
    String title,
    String query,
    String? genreArg,
  ) async {
    final songs = await _safe(() => _searchSongs(query));
    if (songs.isEmpty) return const [];
    return [
      OnlineShelf(
        title,
        kind: ShelfKind.guestTrending,
        args: genreArg != null ? [genreArg] : const [],
        songs: songs.take(15).toList(),
        shelfType: OnlineShelfType.standardCards,
      ),
    ];
  }

  /// Post-build filter pass over all shelves (fixes B17, §7.4) and exploration enforcement (§7.2).
  static List<OnlineShelf> filterAndEnforceExploration(
    List<OnlineShelf> rawShelves,
  ) {
    final seenSongIds = <String>{};
    final filtered = <OnlineShelf>[];

    for (final shelf in rawShelves) {
      // 1. Drop podcasts and NotInterested blocked songs
      final cleanSongs = shelf.songs.where((s) {
        if (s.videoType == videoTypePodcast) return false;
        if (NotInterestedStore.isBlocked(s)) return false;
        // 2. Drop songs already seen in earlier shelves (§7.4)
        return seenSongIds.add(s.videoId);
      }).toList();

      // Drop blocked artist collections
      final cleanCollections = shelf.collections.where((c) {
        return !NotInterestedStore.isArtistBlocked(c.title);
      }).toList();

      final totalItems = cleanSongs.length + cleanCollections.length;
      // 3. Drop shelves left with fewer than 4 items (fixes B17, §7.4)
      if (totalItems >= 4) {
        filtered.add(
          shelf.copyWith(songs: cleanSongs, collections: cleanCollections),
        );
      }
    }

    // 4. Exploration rule (§7.2): Cap personal shelves at 6 and ensure at least
    // one exploration shelf (similar artists or trending) sits in the first 4.
    final capped = filtered.take(6).toList();
    if (capped.length >= 4) {
      final hasExplorationInTop4 = capped
          .take(4)
          .any(
            (s) =>
                s.kind == ShelfKind.guestSimilar ||
                s.kind == ShelfKind.guestTrending,
          );
      if (!hasExplorationInTop4) {
        final exploreIdx = capped.indexWhere(
          (s) =>
              s.kind == ShelfKind.guestSimilar ||
              s.kind == ShelfKind.guestTrending,
        );
        if (exploreIdx != -1) {
          final exploreShelf = capped.removeAt(exploreIdx);
          capped.insert(math.min(3, capped.length), exploreShelf);
        }
      }
    }

    return capped;
  }

  static Future<List<OnlineSong>> _searchSongs(String q) async {
    final (s, _) = await OnlineApi.searchSongs(q, automatic: true);
    return s;
  }

  static Future<List<OnlineSong>> _safe(
    Future<List<OnlineSong>> Function() f,
  ) async {
    try {
      return await f();
    } catch (e) {
      LoggerHelper.write('$_tag: safe fetch failed', e);
      return const [];
    }
  }

  /// Interleaves lists evenly up to [max] items.
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
