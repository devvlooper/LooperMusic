import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/parsers.dart';

/// YouTube Music reads. Search filter params verified November 2026.
abstract final class OnlineApi {
  static const _songs = 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D';
  static const _albums = 'EgWKAQIYAWoKEAkQAxAEEAkQBQ%3D%3D';
  static const _artists = 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D';
  static const _playlists = 'EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D';

  /// Cap for long playlist walks (100 rows a page).
  static const _maxPages = 50;

  static InnerTube get _it => InnerTube.instance;

  static Future<(List<OnlineSong>, String?)> searchSongs(
    String query, {
    String? continuation,
    bool automatic = false,
  }) async => parseSongSearch(
    await _it.music(
      'search',
      continuation == null
          ? {'query': query, 'params': _songs}
          : {'continuation': continuation},
      automatic: automatic,
    ),
  );

  static Future<List<OnlineCollection>> searchCollections(
    String query,
    CollectionKind kind, {
    bool automatic = false,
  }) async =>
      (await searchCollectionsPage(query, kind, automatic: automatic)).$1;

  /// One page of a filtered album / artist / playlist search and its
  /// next-page token.
  static Future<(List<OnlineCollection>, String?)> searchCollectionsPage(
    String query,
    CollectionKind kind, {
    String? continuation,
    bool automatic = false,
  }) async {
    final params = switch (kind) {
      CollectionKind.album => _albums,
      CollectionKind.artist => _artists,
      CollectionKind.playlist => _playlists,
    };
    final (cards, token) = parseCollectionSearchPage(
      await _it.music(
        'search',
        continuation == null
            ? {'query': query, 'params': params}
            : {'continuation': continuation},
        automatic: automatic,
      ),
    );
    return (cards.where((c) => c.kind == kind).toList(), token);
  }

  static Future<List<String>> suggestions(String input) async =>
      parseSuggestions(
        await _it.music('music/get_search_suggestions', {'input': input}),
      );

  /// YouTube radio / mix station for any playlist id (RDAMVM, RDAMPL, RDEM, RDAO, RDTMAK).
  static Future<List<OnlineSong>> radioPlaylist(
    String playlistId, {
    String? videoId,
    bool automatic = false,
  }) async {
    final rows = parseRadio(
      await _it.music('next', {
        'playlistId': playlistId,
        'videoId': ?videoId,
        'isAudioOnly': true,
      }, automatic: automatic),
    );
    if (videoId != null) {
      return rows.where((s) => s.videoId != videoId).toList();
    }
    return rows;
  }

  /// YouTube's own "up next" radio for a song (the song itself excluded).
  static Future<List<OnlineSong>> radio(
    String videoId, {
    bool automatic = false,
  }) async =>
      radioPlaylist('RDAMVM$videoId', videoId: videoId, automatic: automatic);

  /// The music video behind a song ([videoId] an audio track), from the
  /// Song / Video toggle of its watch page; null when it has none.
  static Future<String?> videoCounterpart(
    String videoId, {
    bool automatic = true,
  }) async => parseCounterpart(
    await _it.music('next', {'videoId': videoId}, automatic: automatic),
    videoId,
  );

  /// Album, year, credits and type of one song (for downloads' tags).
  static Future<OnlineSong?> details(String videoId) async => parseSongDetails(
    await _it.music('next', {'videoId': videoId, 'isAudioOnly': true}),
    videoId,
  );

  /// YouTube Music home (or one mood of it, by [params]): its shelves in
  /// page order and the mood chips. Signed in, the personal shelves (Speed
  /// dial, Quick picks, Forgotten favourites, Albums for you...) are spread
  /// over several continuation pages, so up to [pages] are read.
  static Future<(List<OnlineShelf>, List<OnlineMood>, String?)> home({
    String? params,
    int pages = 2,
    bool automatic = false,
  }) async {
    final first = await _it.music('browse', {
      'browseId': 'FEmusic_home',
      'params': ?params,
    }, automatic: automatic);
    final shelves = parseShelves(first);
    var token = homeContinuation(first);
    for (var i = 1; i < pages && token != null; i++) {
      try {
        final next = await _it.music('browse', {
          'continuation': token,
        }, automatic: automatic);
        shelves.addAll(parseShelves(next));
        token = homeContinuation(next);
      } catch (_) {
        break; // what loaded is enough to show
      }
    }
    return (shelves, parseMoods(first), token);
  }

  /// The next page of home shelves after [home], with its own next token.
  static Future<(List<OnlineShelf>, String?)> homeMore(
    String continuation, {
    bool automatic = false,
  }) async {
    final json = await _it.music('browse', {
      'continuation': continuation,
    }, automatic: automatic);
    return (parseShelves(json), homeContinuation(json));
  }

  /// A list page walked up to [pages] pages: the account's library lists
  /// (`FEmusic_liked_playlists`, `FEmusic_liked_albums`,
  /// `FEmusic_library_corpus_artists`), Liked Music (`VLLM`) or a shelf's
  /// "More" page. Later pages are paced so bulk reads stay gentle.
  static Future<OnlineShelf> listItems(
    String browseId,
    String title, {
    String? params,
    int pages = 1,
    bool automatic = false,
  }) async {
    var json = await _it.music('browse', {
      'browseId': browseId,
      'params': ?params,
    }, automatic: automatic);
    final songs = <OnlineSong>[];
    final cards = <OnlineCollection>[];
    final seen = <String>{};
    for (var i = 0; ; i++) {
      final page = parseListItems(json, title);
      final before = seen.length;
      songs.addAll(page.songs.where((s) => seen.add(s.videoId)));
      cards.addAll(page.collections.where((c) => seen.add(c.browseId)));
      final token = listContinuation(json);
      // A page that adds nothing means YouTube is repeating itself.
      if (token == null || i + 1 >= pages || seen.length == before) break;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        json = await _it.music('browse', {
          'continuation': token,
        }, automatic: automatic);
      } catch (_) {
        break;
      }
    }
    return OnlineShelf(
      title,
      songs: songs,
      collections: cards,
      moreBrowseId: browseId,
      moreParams: params,
    );
  }

  /// One page of a list or shelf "More" page with its continuation token.
  static Future<(OnlineShelf shelf, String? continuation)> listPage(
    String? browseId,
    String title, {
    String? params,
    String? continuation,
    bool automatic = false,
  }) async {
    final body = <String, dynamic>{
      if (continuation != null)
        'continuation': continuation
      else ...{
        'browseId': ?browseId,
        'params': ?params,
      },
    };
    final json = await _it.music('browse', body, automatic: automatic);
    final shelf = parseListItems(json, title);
    final token = listContinuation(json);
    return (shelf, token);
  }

  /// An album, playlist or artist page, with a long playlist walked to its
  /// end (or [_maxPages]). A failed later page keeps what was loaded.
  static Future<OnlinePage> page(
    String browseId, {
    bool automatic = false,
  }) async {
    final page = parsePage(
      await _it.music('browse', {'browseId': browseId}, automatic: automatic),
    );
    var token = page.continuation;
    if (browseId.startsWith('UC')) {
      // For artists: YouTube Music only puts 5 songs on the overview shelf.
      // Fetch the "Top songs" playlist from bottomEndpoint to load the full list.
      if (page.moreSongsBrowseId != null) {
        try {
          final moreShelf = await listItems(
            page.moreSongsBrowseId!,
            page.title,
            params: page.moreSongsParams,
            pages: _maxPages,
            automatic: true,
          );
          if (moreShelf.songs.isNotEmpty) {
            final seen = {for (final s in page.songs) s.videoId};
            final allSongs = [
              ...page.songs,
              ...moreShelf.songs.where((s) => seen.add(s.videoId)),
            ];
            return OnlinePage(
              title: page.title,
              subtitle: page.subtitle,
              thumbnail: page.thumbnail,
              songs: allSongs,
              shelves: page.shelves,
              continuation: page.continuation,
              moreSongsBrowseId: page.moreSongsBrowseId,
              moreSongsParams: page.moreSongsParams,
            );
          }
        } catch (_) {}
      }
      return page;
    }
    if (token == null) return page;
    final songs = [...page.songs];
    final seen = {for (final s in songs) s.videoId};
    for (var i = 0; i < _maxPages && token != null; i++) {
      try {
        final (more, next) = parsePageContinuation(
          await _it.music('browse', {
            'continuation': token,
          }, automatic: automatic),
          thumbFallback: page.thumbnail,
        );
        // Mixes repeat themselves forever; stop when a page adds nothing.
        final fresh = more.where((s) => seen.add(s.videoId)).toList();
        if (fresh.isEmpty || next == token) break;
        songs.addAll(fresh);
        token = next;
      } catch (_) {
        break;
      }
    }
    return OnlinePage(
      title: page.title,
      subtitle: page.subtitle,
      thumbnail: page.thumbnail,
      songs: songs,
      shelves: page.shelves,
    );
  }

  /// Who YouTube thinks is signed in: a name (null when the call went
  /// through as signed out) and the account's photo URL.
  static Future<({String? name, String? photo})> account() async {
    final json = await _it.music('account/account_menu', {});
    return (name: parseAccountName(json), photo: parseAccountPhoto(json));
  }

  /// The plain lyrics YouTube Music shows for [videoId], or null.
  static Future<String?> lyrics(String videoId) async {
    final browseId = parseLyricsBrowseId(
      await _it.music('next', {
        'videoId': videoId,
        'isAudioOnly': true,
      }, automatic: true),
    );
    if (browseId == null) return null;
    return parseLyrics(
      await _it.music('browse', {'browseId': browseId}, automatic: true),
    );
  }
}
