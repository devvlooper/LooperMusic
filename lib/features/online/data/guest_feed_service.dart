import 'dart:math' as math;
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/guest_taste_engine.dart';
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
    final taste = profile ?? await _engine.computeProfile();

    switch (taste.coldStartLevel) {
      case 0:
        return _buildLevel0ExploreFeed(force: force);
      case 1:
        return _buildLevel1SeedlingFeed(taste);
      case 2:
        return _buildLevel2GrowingFeed(taste);
      case 3:
      default:
        return _buildLevel3ThrivingFeed(taste);
    }
  }

  /// Level 0: Empty device -> Standard explore/trending fallback.
  Future<List<OnlineShelf>> _buildLevel0ExploreFeed({bool force = false}) async {
    try {
      final (shelves, _) = await OnlineApi.home(automatic: !force, pages: 2);
      if (shelves.isNotEmpty) return shelves;
    } catch (e) {
      LoggerHelper.write('$_tag: Level 0 home fallback failed', e);
    }
    // Secondary fallback: search top charts
    return _buildGenreShelf('Top Global Music Charts', 'top music charts');
  }

  /// Level 1: 1 - 9 songs -> Exact search match & direct radios.
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
      final radioTracks = await _safe(() => OnlineApi.radio(seed.videoId!, automatic: true));
      if (radioTracks.isNotEmpty) {
        shelves.add(OnlineShelf(
          'Radio: Inspired by ${seed.title}',
          songs: radioTracks,
          moreBrowseId: 'RDAMVM${seed.videoId}',
        ));
      }
    }

    // 2. Artist Shelf for the top artist
    if (taste.topArtists.isNotEmpty) {
      final artistName = taste.topArtists.first.artist;
      final artistSongs = await _safe(() => _searchSongs('$artistName songs'));
      if (artistSongs.isNotEmpty) {
        shelves.add(OnlineShelf(
          'Because you listen to $artistName',
          songs: artistSongs,
        ));
      }
    }

    // 3. Fallback explore shelf
    final explore = await _buildLevel0ExploreFeed();
    shelves.addAll(explore.take(2));

    return shelves;
  }

  /// Level 2: 10 - 100 songs, low/no play history -> Scanned metadata seeds.
  Future<List<OnlineShelf>> _buildLevel2GrowingFeed(
    GuestTasteProfile taste,
  ) async {
    final shelves = <OnlineShelf>[];

    // Concurrently resolve top seeds
    final resolvedSongsFuture = OfflineOnlineResolver.resolveSeeds(
      taste.topSongs.take(3).toList(),
      maxConcurrent: 3,
    );
    final topArtist = taste.topArtists.firstOrNull?.artist;

    final (resolvedSongs, _) = await (
      resolvedSongsFuture,
      topArtist != null
          ? OfflineOnlineResolver.resolveArtistBrowseId(topArtist)
          : Future.value(null),
    ).wait;

    // 1. Quick Picks (interleaved from top 3 songs)
    if (resolvedSongs.isNotEmpty) {
      final quickPicks = await _buildQuickPicksShelf(resolvedSongs);
      if (quickPicks != null) shelves.add(quickPicks);
    }

    // 2. Artist Shelf
    if (topArtist != null && topArtist.isNotEmpty) {
      final artistShelf = await _buildArtistShelf(topArtist);
      if (artistShelf != null) shelves.add(artistShelf);
    }

    // 3. Dominant Genre Exploration Shelf
    final genre = taste.dominantGenres.firstOrNull ?? 'Trending';
    final genreShelves = await _buildGenreShelf('Trending in $genre', '$genre trending');
    shelves.addAll(genreShelves);

    return shelves;
  }

  /// Level 3: > 100 songs + active play history -> Full 5-shelf synthesized layout.
  Future<List<OnlineShelf>> _buildLevel3ThrivingFeed(
    GuestTasteProfile taste,
  ) async {
    final shelves = <OnlineShelf>[];

    // Concurrently resolve top 3 seeds and top artist browse ID
    final resolvedSongsFuture = OfflineOnlineResolver.resolveSeeds(
      taste.topSongs.take(3).toList(),
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

    // Shelf 1: Quick Picks (Based on your library)
    if (resolvedSongs.isNotEmpty) {
      final quickPicks = await _buildQuickPicksShelf(resolvedSongs);
      if (quickPicks != null) shelves.add(quickPicks);
    }

    // Shelf 2: Radio: Inspired by [Favorite Song]
    final topSong = resolvedSongs.firstOrNull;
    if (topSong != null && topSong.videoId != null) {
      final radioTracks = await _safe(
        () => OnlineApi.radio(topSong.videoId!, automatic: true),
      );
      if (radioTracks.isNotEmpty) {
        shelves.add(OnlineShelf(
          'Radio: Inspired by ${topSong.title}',
          songs: radioTracks,
          moreBrowseId: 'RDAMVM${topSong.videoId}',
        ));
      }
    }

    // Shelf 3: Because you listen to [Top Artist]
    if (topArtistName != null && topArtistName.isNotEmpty) {
      final artistShelf = await _buildArtistShelf(
        topArtistName,
        browseId: artistBrowseId,
      );
      if (artistShelf != null) shelves.add(artistShelf);

      // Shelf 4: Similar to [Top Artist] (Exploration / Serendipity)
      final similarShelf = await _buildSimilarArtistsShelf(
        topArtistName,
        browseId: artistBrowseId,
      );
      if (similarShelf != null) shelves.add(similarShelf);
    }

    // Shelf 5: Trending in [Dominant Genre / Country] (75/25 rule)
    final genre = taste.dominantGenres.firstOrNull ??
        (taste.primaryLanguageScript != 'Latin'
            ? taste.primaryLanguageScript
            : 'Top Hits');
    final genreShelves = await _buildGenreShelf(
      'Trending in $genre',
      '$genre hits',
    );
    shelves.addAll(genreShelves);

    return shelves;
  }

  /// Builds Quick Picks by interleaving radio streams from top songs.
  Future<OnlineShelf?> _buildQuickPicksShelf(List<TasteSeed> seeds) async {
    final validSeeds = seeds.where((s) => s.videoId != null).take(3).toList();
    if (validSeeds.isEmpty) return null;

    final radioFutures = validSeeds.map((seed) => _safe(
          () => OnlineApi.radio(seed.videoId!, automatic: true),
        ));
    final radios = await Future.wait(radioFutures);

    final interleaved = _interleave(radios, 16);
    if (interleaved.isEmpty) return null;

    return OnlineShelf(
      'Quick Picks (Based on your library)',
      songs: interleaved,
    );
  }

  /// Builds artist shelf with top songs and singles.
  Future<OnlineShelf?> _buildArtistShelf(
    String artistName, {
    String? browseId,
  }) async {
    try {
      if (browseId != null && browseId.isNotEmpty) {
        final page = await OnlineApi.page(browseId);
        if (page.songs.isNotEmpty) {
          return OnlineShelf(
            'Because you listen to $artistName',
            songs: page.songs,
            moreBrowseId: browseId,
          );
        }
      }
      final songs = await _searchSongs('$artistName songs');
      if (songs.isNotEmpty) {
        return OnlineShelf(
          'Because you listen to $artistName',
          songs: songs,
        );
      }
    } catch (e) {
      LoggerHelper.write('$_tag: buildArtistShelf failed for $artistName', e);
    }
    return null;
  }

  /// Builds similar artists exploration shelf with circular cards.
  Future<OnlineShelf?> _buildSimilarArtistsShelf(
    String artistName, {
    String? browseId,
  }) async {
    try {
      if (browseId != null && browseId.isNotEmpty) {
        final page = await OnlineApi.page(browseId);
        for (final shelf in page.shelves) {
          final isArtistShelf = shelf.collections.isNotEmpty &&
              shelf.collections.every((c) => c.kind == CollectionKind.artist);
          if (isArtistShelf || shelf.title.toLowerCase().contains('similar')) {
            return OnlineShelf(
              'Similar to $artistName',
              collections: shelf.collections,
            );
          }
        }
      }

      // Search collections for related artists
      final collections = await OnlineApi.searchCollections(
        artistName,
        CollectionKind.artist,
        automatic: true,
      );
      final artists = collections
          .where((c) =>
              c.kind == CollectionKind.artist &&
              !c.title.toLowerCase().contains(artistName.toLowerCase()))
          .take(8)
          .toList();

      if (artists.isNotEmpty) {
        return OnlineShelf(
          'Similar to $artistName',
          collections: artists,
        );
      }
    } catch (e) {
      LoggerHelper.write('$_tag: buildSimilarArtistsShelf failed', e);
    }
    return null;
  }

  /// Builds a genre / trending shelf.
  Future<List<OnlineShelf>> _buildGenreShelf(String title, String query) async {
    final songs = await _safe(() => _searchSongs(query));
    if (songs.isEmpty) return const [];
    return [OnlineShelf(title, songs: songs.take(15).toList())];
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
  static List<OnlineSong> _interleave(
    List<List<OnlineSong>> lists,
    int max,
  ) {
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
