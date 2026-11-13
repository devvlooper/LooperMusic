import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/microg/data/account_auth.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_profile_store.dart';
import 'package:looper_player/features/online/data/taste_store.dart';

abstract final class AccountDataSync {
  static const _tag = 'AccountDataSync';
  static const accountPlaylistsCacheKey = 'online_account_playlists_v1';
  static const accountArtistsCacheKey = 'online_account_artists_v1';
  static const accountAlbumsCacheKey = 'online_account_albums_v1';
  static const accountFavoritesCacheKey = 'online_account_favorites_v1';
  static const accountHistoryCacheKey = 'online_account_history_v1';

  static bool _syncing = false;

  /// Fetches real user account data from YouTube Music when signed in:
  /// - Subscribed / followed artists (`FEmusic_library_corpus_artists`)
  /// - User and saved playlists (`FEmusic_liked_playlists`)
  /// - Saved albums (`FEmusic_liked_albums`)
  /// - Liked music / favorites (`FEmusic_liked_videos` or `LM`)
  /// - History (`FEmusic_history`)
  ///
  /// Returns the synced account artists so recommendations and taste can be
  /// updated by the caller.
  static Future<List<TasteArtist>> sync({bool force = false}) async {
    final auth = await AccountAuth.instance.headers();
    if (auth.isEmpty) return const [];
    if (_syncing) return const [];
    _syncing = true;

    try {
      final results = await Future.wait([
        OnlineApi.listItems(
          'FEmusic_library_corpus_artists',
          'Artists',
          pages: 2,
          automatic: true,
        ).catchError((_) => const OnlineShelf('Artists')),
        OnlineApi.listItems(
          'FEmusic_liked_playlists',
          'Playlists',
          pages: 2,
          automatic: true,
        ).catchError((_) => const OnlineShelf('Playlists')),
        OnlineApi.listItems(
          'FEmusic_liked_albums',
          'Albums',
          pages: 2,
          automatic: true,
        ).catchError((_) => const OnlineShelf('Albums')),
        OnlineApi.listItems(
          'FEmusic_liked_videos',
          'Liked Music',
          pages: 2,
          automatic: true,
        ).catchError((_) async {
          return OnlineApi.listItems(
            'LM',
            'Liked Music',
            pages: 2,
            automatic: true,
          ).catchError((_) => const OnlineShelf('Liked Music'));
        }),
        OnlineApi.listItems(
          'FEmusic_history',
          'History',
          pages: 2,
          automatic: true,
        ).catchError((_) => const OnlineShelf('History')),
      ]);

      final artistsShelf = results[0];
      final playlistsShelf = results[1];
      final albumsShelf = results[2];
      final favoritesShelf = results[3];
      final historyShelf = results[4];

      // Cache account collections
      if (playlistsShelf.collections.isNotEmpty) {
        await LocalJsonStore.write(accountPlaylistsCacheKey, [
          for (final c in playlistsShelf.collections) c.toJson(),
        ]);
      }
      if (artistsShelf.collections.isNotEmpty) {
        await LocalJsonStore.write(accountArtistsCacheKey, [
          for (final c in artistsShelf.collections) c.toJson(),
        ]);
      }
      if (albumsShelf.collections.isNotEmpty) {
        await LocalJsonStore.write(accountAlbumsCacheKey, [
          for (final c in albumsShelf.collections) c.toJson(),
        ]);
      }
      if (favoritesShelf.songs.isNotEmpty) {
        await LocalJsonStore.write(accountFavoritesCacheKey, [
          for (final s in favoritesShelf.songs) s.toJson(),
        ]);
      }
      if (historyShelf.songs.isNotEmpty) {
        await LocalJsonStore.write(accountHistoryCacheKey, [
          for (final s in historyShelf.songs) s.toJson(),
        ]);
      }

      if (artistsShelf.collections.isNotEmpty) {
        return [
          for (final c in artistsShelf.collections)
            TasteArtist(c.title, browseId: c.browseId, thumbnail: c.thumbnail),
        ];
      }
      return const [];
    } catch (e) {
      LoggerHelper.write('$_tag: sync failed', e);
      return const [];
    } finally {
      _syncing = false;
    }
  }

  static Future<List<OnlineCollection>> getAccountPlaylists() async {
    final raw = await LocalJsonStore.read(accountPlaylistsCacheKey);
    if (raw is! List) return const [];
    return [
      for (final j in raw) ?OnlineCollection.fromJson(j),
    ];
  }

  static Future<List<OnlineCollection>> getAccountArtists() async {
    final raw = await LocalJsonStore.read(accountArtistsCacheKey);
    if (raw is! List) return const [];
    return [
      for (final j in raw) ?OnlineCollection.fromJson(j),
    ];
  }

  static Future<List<OnlineCollection>> getAccountAlbums() async {
    final raw = await LocalJsonStore.read(accountAlbumsCacheKey);
    if (raw is! List) return const [];
    return [
      for (final j in raw) ?OnlineCollection.fromJson(j),
    ];
  }

  static Future<List<OnlineSong>> getAccountFavorites() async {
    final raw = await LocalJsonStore.read(accountFavoritesCacheKey);
    if (raw is! List) return const [];
    return [
      for (final j in raw) ?OnlineSong.fromJson(j),
    ];
  }

  static Future<List<OnlineSong>> getAccountHistory() async {
    final raw = await LocalJsonStore.read(accountHistoryCacheKey);
    if (raw is! List) return const [];
    return [
      for (final j in raw) ?OnlineSong.fromJson(j),
    ];
  }

  /// Clears account data caches when signed out.
  static Future<void> clear() async {
    await LocalJsonStore.delete(accountPlaylistsCacheKey);
    await LocalJsonStore.delete(accountArtistsCacheKey);
    await LocalJsonStore.delete(accountAlbumsCacheKey);
    await LocalJsonStore.delete(accountFavoritesCacheKey);
    await LocalJsonStore.delete(accountHistoryCacheKey);
  }
}
