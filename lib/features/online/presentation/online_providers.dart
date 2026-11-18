import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';
import 'package:looper_player/features/microg/presentation/providers/auth_provider.dart';
import 'package:looper_player/features/online/data/account_data_sync.dart';
import 'package:looper_player/features/online/data/guest_feed_service.dart';
import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/offline_online_resolver.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/recommendation_engine.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/data/taste_profile_store.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:isar_community/isar.dart';

/// Online surfaces show only on the GitHub/desktop build, with online
/// music switched on and the app's Internet mode allowed.
final onlineActiveProvider = Provider<bool>(
  (ref) =>
      onlineAvailable &&
      ref.watch(onlineSettingsProvider.select((s) => s.enabled)) &&
      ref.watch(settingsProvider.select((s) => s.enableInternet)),
);

class OnlineStatusNotifier extends Notifier<OnlineStatus> {
  @override
  OnlineStatus build() {
    final notifier = StreamResolver.instance.statusNotifier;
    void listener() => state = notifier.value;
    notifier.addListener(listener);
    ref.onDispose(() => notifier.removeListener(listener));
    return notifier.value;
  }
}

final onlineStatusProvider =
    NotifierProvider<OnlineStatusNotifier, OnlineStatus>(
      OnlineStatusNotifier.new,
    );

/// Shelf titles that are ours, not YouTube's, localized at display.
const discoverShelf = '@discover';

class OnlineHomeState {
  const OnlineHomeState({
    this.shelves = const [],
    this.forYou = const [],
    this.moods = const [],
    this.activeMood,
    this.loading = false,
    this.error,
    this.continuation,
    this.loadingMore = false,
    this.moreFailed = false,
  });
  final List<OnlineShelf> shelves;
  final List<OnlineSong> forYou;
  final List<OnlineMood> moods;
  final OnlineMood? activeMood;
  final bool loading;
  final Object? error;

  /// Cursor for more YouTube home shelves (load on scroll).
  final String? continuation;
  final bool loadingMore;

  /// The last more-shelves load failed; the footer shows a retry button.
  final bool moreFailed;

  OnlineHomeState copyWith({
    List<OnlineShelf>? shelves,
    List<OnlineSong>? forYou,
    List<OnlineMood>? moods,
    OnlineMood? activeMood,
    bool? loading,
    Object? error,
    bool? loadingMore,
    bool? moreFailed,
  }) => OnlineHomeState(
    shelves: shelves ?? this.shelves,
    forYou: forYou ?? this.forYou,
    moods: moods ?? this.moods,
    activeMood: activeMood ?? this.activeMood,
    loading: loading ?? this.loading,
    error: error,
    continuation: continuation,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// Helper to sort shelves in descending personal/mood relevance:
/// 1. Speed dial
/// 2. For you / Discover / Quick picks / Listen again
/// 3. Trending songs for you
/// 4. Active mood shelves
/// 5. Mixes / My Supermix
/// 6. Forgotten favourites
/// 7. Trending community playlists
/// 8. Albums for you
/// 9. Remaining shelves
int _shelfRelevanceRank(OnlineShelf s, bool hasActiveMood) {
  final t = s.title.toLowerCase().trim();
  if (t.contains('speed dial')) return 0;
  if (s.title == discoverShelf ||
      t.contains('for you') ||
      t.contains('quick picks') ||
      t.contains('listen again')) {
    return 1;
  }
  if (t.contains('radio: inspired') ||
      t.contains('trending song') ||
      (t.contains('trending') && t.contains('for you'))) {
    return 2;
  }
  if (hasActiveMood &&
      !t.contains('community') &&
      !t.contains('album') &&
      !t.contains('forgotten')) {
    return 3;
  }
  if (t.contains('because you listen') ||
      t.contains('supermix') ||
      t.contains('mixes') ||
      t.contains('mix')) {
    return 4;
  }
  if (t.contains('similar to')) {
    return 5;
  }
  if (t.contains('forgotten')) {
    return 6;
  }
  if (t.contains('community playlist') || t.contains('community')) {
    return 7;
  }
  if (t.contains('album')) {
    return 8;
  }
  return 9;
}

/// Online home: "For you" (for Quick picks) and "Discover" from the suggestion
/// analyser, then YouTube Music's own home shelves. Shown from a disk cache at
/// once; a revisit within 10 minutes does not refetch (Koda: repeated home reloads
/// preceded YouTube's bot check).
class OnlineHomeNotifier extends Notifier<OnlineHomeState> {
  static const _cacheKey = 'online_home_cache';
  static const _fresh = Duration(minutes: 10);
  DateTime? _loadedAt;
  Future<void>? _running;

  /// The taste profile relearned since For you was fetched: the next load
  /// may replace it instead of keeping what is on screen.
  bool _tasteChanged = false;

  @override
  OnlineHomeState build() {
    // Riverpod 3 reuses this notifier when the provider is invalidated
    // ("Not interested", taste edits). The state below starts loading, so
    // the next load must really run: a kept _loadedAt skipped it and left
    // the loading line on forever.
    _loadedAt = null;
    void onTaste() => unawaited(_applyTaste());
    TasteProfileStore.revision.addListener(onTaste);
    ref.onDispose(() => TasteProfileStore.revision.removeListener(onTaste));
    ref.listen(tasteProvider, (previous, next) {
      if (previous != null && !identical(previous, next)) {
        TasteProfileStore.invalidate();
        LocalJsonStore.delete('online_artists_for_you_v1');
        ref.invalidate(onlineArtistsForYouProvider);
        if (ref.read(onlineActiveProvider)) {
          unawaited(load(force: true));
        }
      }
    });
    final syncCached = _parseCached(LocalJsonStore.readSync(_cacheKey));
    // After build returns: _boot reads state, which throws while the first
    // build runs, and that silently skipped the first load (endless line).
    unawaited(Future.microtask(_boot));
    return syncCached ?? const OnlineHomeState(loading: true);
  }

  OnlineHomeState? _parseCached(dynamic raw) {
    if (raw is List) {
      final cached = [for (final s in raw) ?OnlineShelf.fromJson(s)];
      if (cached.isNotEmpty) {
        return OnlineHomeState(shelves: cached, loading: true);
      }
    } else if (raw is Map) {
      final cachedShelves = [
        for (final s in (raw['shelves'] as List? ?? const []))
          if (s is Map) ?OnlineShelf.fromJson(s),
      ];
      final cachedForYou = [
        for (final s in (raw['forYou'] as List? ?? const []))
          if (s is Map) ?OnlineSong.fromJson(s),
      ];
      final cachedMoods = [
        for (final m in (raw['moods'] as List? ?? const []))
          if (m is Map) ?OnlineMood.fromJson(m),
      ];
      if (cachedShelves.isNotEmpty ||
          cachedForYou.isNotEmpty ||
          cachedMoods.isNotEmpty) {
        return OnlineHomeState(
          shelves: cachedShelves,
          forYou: cachedForYou,
          moods: cachedMoods,
          loading: true,
        );
      }
    }
    return null;
  }

  /// A new taste profile (a few plays, a liked song, a new time of day):
  /// re-order For you right away, then fetch fresh picks once allowed.
  Future<void> _applyTaste() async {
    if (!ref.read(onlineActiveProvider)) return;
    _tasteChanged = true;
    final current = state.forYou;
    if (current.isNotEmpty) {
      try {
        final ranked = await RecommendationEngine.rerank(current);
        if (identical(state.forYou, current)) {
          state = state.copyWith(forYou: ranked);
        }
      } catch (e) {
        LoggerHelper.write('Online home: re-rank failed', e);
      }
    }
    unawaited(load());
  }

  Future<void> _boot() async {
    if (state.shelves.isEmpty) {
      final raw = await LocalJsonStore.read(_cacheKey);
      final cached = _parseCached(raw);
      if (cached != null) {
        state = cached;
      }
    }
    await load();
  }

  Future<void> selectMood(OnlineMood? mood) async {
    final newMood = state.activeMood == mood ? null : mood;
    if (newMood != null) await TasteProfileStore.recordMoodPick(newMood.title);
    state = state.copyWith(activeMood: newMood, loading: true);
    // A mood only changes the YouTube shelves: reuse saved searches instead
    // of redoing every For you / Discover search, but still a user request.
    await _load(false, mood: newMood, user: true);
  }

  Future<void> load({bool force = false}) {
    final at = _loadedAt;
    if (!force && at != null && DateTime.now().difference(at) < _fresh) {
      return Future.value();
    }
    return _running ??= _load(
      force,
      mood: state.activeMood,
    ).whenComplete(() => _running = null);
  }

  Future<void> _load(bool force, {OnlineMood? mood, bool? user}) async {
    final automatic = !(user ?? force);
    final active = ref.read(onlineActiveProvider);
    if (!active) {
      state = state.copyWith(
        loading: false,
        shelves: const [],
        forYou: const [],
      );
      return;
    }

    state = state.copyWith(loading: true, activeMood: mood);
    try {
      final isConnected = ref.read(isOnlineConnectedProvider);
      List<OnlineShelf> rawShelves;
      List<OnlineSong> forYouSongs = const [];
      List<OnlineMood> youtubeMoods = const [];
      String? homeToken;

      if (!isConnected && mood == null) {
        // Guest mode: Synthesize home feed from offline library signals
        // Both at once: neither needs the other.
        final ytF = OnlineApi.home(automatic: automatic, pages: 1);
        unawaited(ytF.then((_) {}, onError: (_) {}));
        final guestShelves = await GuestFeedService().buildGuestFeed(
          force: force,
        );
        List<OnlineShelf> ytShelves = const [];
        try {
          final yt = await ytF;
          ytShelves = yt.$1;
          youtubeMoods = yt.$2;
          homeToken = yt.$3;
        } catch (_) {}
        // Exploration shelves from public YouTube home (fixes B18, §7.2)
        rawShelves = [...guestShelves, ...ytShelves];
      } else {
        // Pull-to-refresh wants new songs; background reloads reuse saved
        // searches longer.
        RecommendationEngine.searchMaxAge = force
            ? const Duration(minutes: 30)
            : const Duration(hours: 6);
        // YouTube home doesn't need the taste profile: start it first so
        // its pages load while the recommendation searches run.
        final ytF = OnlineApi.home(
          params: mood?.params,
          pages: 3,
          automatic: automatic,
        );
        unawaited(ytF.then((_) {}, onError: (_) {}));
        final profile = await RecommendationEngine.buildProfile(force: force);
        final results = await Future.wait([
          RecommendationEngine.forYou(profile),
          RecommendationEngine.discover(profile),
          RecommendationEngine.buildMixShelves(profile.profiles),
        ]);
        List<OnlineShelf> youtubeShelves = const [];
        try {
          final yt = await ytF;
          youtubeShelves = yt.$1;
          youtubeMoods = yt.$2;
          homeToken = yt.$3;
        } catch (e) {
          LoggerHelper.write('Online home: YouTube shelves failed', e);
        }
        forYouSongs = results[0] as List<OnlineSong>;
        final discoverSongs = results[1] as List<OnlineSong>;
        final mixShelves = results[2] as List<OnlineShelf>;

        rawShelves = [
          if (discoverSongs.isNotEmpty)
            OnlineShelf(discoverShelf, songs: discoverSongs),
          ...mixShelves,
          ...youtubeShelves,
        ];
      }

      // Sort shelves in descending order of personal relevance and mood relation
      final hasActiveMood = mood != null;
      final indexed = [
        for (var i = 0; i < rawShelves.length; i++) (i, rawShelves[i]),
      ];
      indexed.sort((a, b) {
        final rankA = _shelfRelevanceRank(a.$2, hasActiveMood);
        final rankB = _shelfRelevanceRank(b.$2, hasActiveMood);
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.$1.compareTo(b.$1);
      });
      final rankedShelves = [for (final entry in indexed) entry.$2];

      // Dedup first (Doc 22 §6.4): it drops shelves, which would break the
      // style spacing the layout pass sets up (Doc 22 §6.3).
      final shelves = applyFeedLayoutPass(deduplicateShelves(rankedShelves));

      final nextMoods = youtubeMoods.isNotEmpty ? youtubeMoods : state.moods;

      if (shelves.isEmpty && forYouSongs.isEmpty) {
        // Keep what is on screen; an empty answer never replaces it.
        state = state.copyWith(
          loading: false,
          error: StreamUnavailableException('nothing loaded'),
        );
        return;
      }
      _loadedAt = DateTime.now();
      // Keep visible Quick Picks stable during background refresh: if we
      // already have items showing, don't swap them out under the user's
      // fingers. Explicit pull-to-refresh (force: true) still applies right away.
      final keepForYou = !force && !_tasteChanged && state.forYou.isNotEmpty;
      final effectiveForYou = keepForYou
          ? state.forYou
          : (forYouSongs.isNotEmpty ? forYouSongs : state.forYou);
      if (forYouSongs.isNotEmpty) _tasteChanged = false;

      state = OnlineHomeState(
        shelves: shelves,
        forYou: effectiveForYou,
        moods: nextMoods,
        activeMood: mood,
        loading: false,
        continuation: homeToken,
      );
      await LocalJsonStore.write(_cacheKey, {
        'shelves': [for (final s in shelves) s.toJson()],
        'forYou': [
          for (final s
              in (forYouSongs.isNotEmpty ? forYouSongs : effectiveForYou))
            s.toJson(),
        ],
        'moods': [for (final m in nextMoods) m.toJson()],
      });
    } catch (e) {
      LoggerHelper.write('Online home failed', e);
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// More YouTube home shelves, appended as the user scrolls to the end.
  Future<void> loadMore() async {
    final token = state.continuation;
    if (token == null || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true, moreFailed: false);
    try {
      final (more, next) = await OnlineApi.homeMore(token);
      // A reload while this was in flight owns the list now.
      if (state.continuation != token) return;
      final old = state.shelves;
      // Old shelves are already deduped, so they come back unchanged.
      final fresh = applyFeedLayoutPass(
        deduplicateShelves([...old, ...more]).skip(old.length).toList(),
      );
      state = OnlineHomeState(
        shelves: [...old, ...fresh],
        forYou: state.forYou,
        moods: state.moods,
        activeMood: state.activeMood,
        // Nothing new means YouTube is repeating; stop here.
        continuation: fresh.isEmpty ? null : next,
      );
    } catch (e) {
      if (state.continuation != token) return;
      LoggerHelper.write('Online home: more shelves failed', e);
      state = state.copyWith(loadingMore: false, moreFailed: true);
    }
  }

  /// The Refresh button: when online music stops working, start over with
  /// a fresh identity, no cached URLs and no throttle hold, then reload.
  Future<void> refresh() async {
    await StreamResolver.instance.reset();
    await OfflineOnlineResolver.clearNegativeCache();
    await load(force: true);
  }
}

final onlineHomeProvider =
    NotifierProvider<OnlineHomeNotifier, OnlineHomeState>(
      OnlineHomeNotifier.new,
    );

class OnlineSearchState {
  const OnlineSearchState({
    this.query = '',
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.continuation,
    this.cardTokens = const {},
    this.cardsLoading = const {},
  });
  final String query;
  final List<OnlineSong> songs;
  final List<OnlineCollection> artists;
  final List<OnlineCollection> albums;
  final List<OnlineCollection> playlists;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final String? continuation;

  /// Next-page cursors of the artist / album / playlist searches.
  final Map<CollectionKind, String> cardTokens;
  final Set<CollectionKind> cardsLoading;

  List<OnlineCollection> cardsOf(CollectionKind kind) => switch (kind) {
    CollectionKind.artist => artists,
    CollectionKind.album => albums,
    CollectionKind.playlist => playlists,
  };

  bool get isEmpty =>
      songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty;

  OnlineSearchState copyWith({
    List<OnlineSong>? songs,
    bool? loadingMore,
    Object? error,
    String? continuation,
    List<OnlineCollection>? artists,
    List<OnlineCollection>? albums,
    List<OnlineCollection>? playlists,
    Map<CollectionKind, String>? cardTokens,
    Set<CollectionKind>? cardsLoading,
  }) => OnlineSearchState(
    query: query,
    songs: songs ?? this.songs,
    artists: artists ?? this.artists,
    albums: albums ?? this.albums,
    playlists: playlists ?? this.playlists,
    loading: loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
    continuation: continuation,
    cardTokens: cardTokens ?? this.cardTokens,
    cardsLoading: cardsLoading ?? this.cardsLoading,
  );
}

/// Online search, debounced 400 ms. A late answer for an old query is
/// dropped. Results are kept 5 minutes per query.
class OnlineSearchNotifier extends Notifier<OnlineSearchState> {
  Timer? _debounce;
  final _cache = <String, (DateTime, OnlineSearchState)>{};

  @override
  OnlineSearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const OnlineSearchState();
  }

  void search(String raw) {
    final query = raw.trim();
    if (query == state.query) return;
    _debounce?.cancel();
    if (query.length < 2) {
      state = OnlineSearchState(query: query);
      return;
    }
    final hit = _cache[query];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(minutes: 5)) {
      state = hit.$2;
      return;
    }
    state = OnlineSearchState(query: query, loading: true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_run(query)),
    );
  }

  /// Same query again (Retry).
  Future<void> retry() => _run(state.query);

  Future<void> _run(String query) async {
    state = OnlineSearchState(query: query, loading: true);
    final tokens = <CollectionKind, String>{};
    Future<List<OnlineCollection>> cards(CollectionKind k) async {
      try {
        final (list, token) = await OnlineApi.searchCollectionsPage(query, k);
        if (token != null) tokens[k] = token;
        return list;
      } catch (_) {
        return const [];
      }
    }

    try {
      final songsF = OnlineApi.searchSongs(query);
      final artistsF = cards(CollectionKind.artist);
      final albumsF = cards(CollectionKind.album);
      final playlistsF = cards(CollectionKind.playlist);
      final (songs, token) = await songsF;
      final next = OnlineSearchState(
        query: query,
        songs: songs,
        artists: await artistsF,
        albums: await albumsF,
        playlists: await playlistsF,
        continuation: token,
        cardTokens: tokens,
      );
      if (state.query != query) return;
      state = next;
      _cache[query] = (DateTime.now(), next);
      if (_cache.length > 30) _cache.remove(_cache.keys.first);
    } catch (e) {
      if (state.query != query) return;
      state = OnlineSearchState(query: query, error: e);
    }
  }

  /// Next page of songs; the cursor belongs to this query only.
  Future<void> loadMore() async {
    final token = state.continuation;
    if (token == null || state.loadingMore) return;
    final query = state.query;
    state = state.copyWith(loadingMore: true, continuation: token);
    try {
      final (more, next) = await OnlineApi.searchSongs(
        query,
        continuation: token,
      );
      if (state.query != query) return;
      final seen = {for (final s in state.songs) s.videoId};
      state = state.copyWith(
        songs: [...state.songs, ...more.where((s) => seen.add(s.videoId))],
        loadingMore: false,
        continuation: next,
      );
    } catch (e) {
      if (state.query != query) return;
      // Keep the cursor so the user can try again.
      state = state.copyWith(loadingMore: false, continuation: token);
    }
  }

  /// Next page of one card kind (the Artists / Albums / Playlists filters).
  /// Returns false when the load failed, so the caller can offer a retry.
  Future<bool> loadMoreCards(CollectionKind kind) async {
    final token = state.cardTokens[kind];
    if (token == null || state.cardsLoading.contains(kind)) return true;
    final query = state.query;
    state = state.copyWith(
      continuation: state.continuation,
      cardsLoading: {...state.cardsLoading, kind},
    );
    try {
      final (more, next) = await OnlineApi.searchCollectionsPage(
        query,
        kind,
        continuation: token,
      );
      if (state.query != query) return true;
      final seen = {for (final c in state.cardsOf(kind)) c.browseId};
      final merged = [
        ...state.cardsOf(kind),
        ...more.where((c) => seen.add(c.browseId)),
      ];
      final tokens = {...state.cardTokens}..remove(kind);
      // A page that adds nothing means YouTube is repeating; stop.
      if (next != null && merged.length > state.cardsOf(kind).length) {
        tokens[kind] = next;
      }
      state = state.copyWith(
        continuation: state.continuation,
        artists: kind == CollectionKind.artist ? merged : null,
        albums: kind == CollectionKind.album ? merged : null,
        playlists: kind == CollectionKind.playlist ? merged : null,
        cardTokens: tokens,
        cardsLoading: {...state.cardsLoading}..remove(kind),
      );
      _cache[query] = (DateTime.now(), state);
      return true;
    } catch (_) {
      if (state.query != query) return true;
      state = state.copyWith(
        continuation: state.continuation,
        cardsLoading: {...state.cardsLoading}..remove(kind),
      );
      return false;
    }
  }
}

final onlineSearchProvider =
    NotifierProvider<OnlineSearchNotifier, OnlineSearchState>(
      OnlineSearchNotifier.new,
    );

/// An album, playlist or artist page.
final onlinePageProvider = FutureProvider.autoDispose
    .family<OnlinePage, String>((ref, browseId) => OnlineApi.page(browseId));

class OnlineArtistForYou {
  const OnlineArtistForYou({
    required this.name,
    required this.browseId,
    this.thumbnail,
  });

  final String name;
  final String browseId;
  final String? thumbnail;

  Map<String, dynamic> toJson() => {
    'name': name,
    'browseId': browseId,
    'thumbnail': thumbnail,
  };

  factory OnlineArtistForYou.fromJson(Map j) => OnlineArtistForYou(
    name: j['name'] as String? ?? '',
    browseId: j['browseId'] as String? ?? '',
    thumbnail: j['thumbnail'] as String?,
  );
}

final onlineArtistsForYouProvider = FutureProvider<List<OnlineArtistForYou>>((
  ref,
) async {
  if (!ref.watch(onlineActiveProvider)) return const [];
  final taste = ref.watch(tasteProvider);
  const cacheKey = 'online_artists_for_you_v1';
  final raw =
      LocalJsonStore.readSync(cacheKey) ?? await LocalJsonStore.read(cacheKey);
  if (raw is Map) {
    final savedAt = raw['savedAt'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - savedAt < 7 * 86400 * 1000) {
      final list = raw['artists'] as List? ?? const [];
      final cached = [
        for (final a in list)
          if (a is Map) OnlineArtistForYou.fromJson(a),
      ];
      final cachedNames = cached.map((c) => c.name.toLowerCase()).toSet();
      final tasteNames = taste.artists.map((a) => a.name.toLowerCase()).toSet();
      if (cached.isNotEmpty && tasteNames.every(cachedNames.contains)) {
        return cached;
      }
    }
  }

  final profile = await RecommendationEngine.buildProfile();
  // Include subscribed account artists first, then top profile artists up to 20
  final tasteByName = {
    for (final a in taste.artists)
      if (a.browseId != null) a.name.toLowerCase(): a,
  };

  final candidateNames = <String>[];
  for (final a in taste.artists) {
    if (a.browseId != null && !candidateNames.contains(a.name)) {
      candidateNames.add(a.name);
    }
  }
  for (final name in profile.topArtists) {
    if (!candidateNames.any((c) => c.toLowerCase() == name.toLowerCase())) {
      candidateNames.add(name);
    }
  }
  final topArtists = candidateNames.take(20).toList();
  if (topArtists.isEmpty) return const [];

  final resolved = <OnlineArtistForYou>[];
  for (final name in topArtists) {
    final lower = name.toLowerCase();
    final fromTaste = tasteByName[lower];
    if (fromTaste != null) {
      resolved.add(
        OnlineArtistForYou(
          name: fromTaste.name,
          browseId: fromTaste.browseId!,
          thumbnail: fromTaste.thumbnail,
        ),
      );
      continue;
    }

    try {
      final collections = await OnlineApi.searchCollections(
        name,
        CollectionKind.artist,
      );
      final match = collections
          .where((c) => c.title.toLowerCase() == lower)
          .firstOrNull;
      if (match != null) {
        resolved.add(
          OnlineArtistForYou(
            name: match.title,
            browseId: match.browseId,
            thumbnail: match.thumbnail,
          ),
        );
      }
    } catch (_) {}
  }

  if (resolved.isNotEmpty) {
    await LocalJsonStore.write(cacheKey, {
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'artists': [for (final a in resolved) a.toJson()],
    });
  }

  return resolved;
});

final onlineGenresProvider = FutureProvider<List<String>>((ref) async {
  if (!ref.watch(onlineActiveProvider)) return const [];
  final taste = ref.watch(tasteProvider);
  final profile = await RecommendationEngine.buildProfile();

  final picked = taste.genres;
  final localTags = <String>[];
  try {
    final isar = DbService.isar;
    final tags = await isar.songs
        .where()
        .filter()
        .genreIsNotNull()
        .genreProperty()
        .findAll();
    for (final t in tags) {
      if (t != null && t.trim().isNotEmpty) localTags.add(t.trim());
    }
  } catch (_) {}

  final seen = <String>{};
  final result = <String>[];
  for (final g in [...picked, ...profile.genres, ...localTags]) {
    final lower = g.trim().toLowerCase();
    if (lower.isEmpty || seen.contains(lower)) continue;
    seen.add(lower);
    result.add(g.trim());
    if (result.length >= 10) break;
  }
  return result;
});

final onlineGenrePageProvider = FutureProvider.family<OnlinePage, String>((
  ref,
  genre,
) async {
  final results = await Future.wait([
    OnlineApi.searchSongs('$genre songs'),
    OnlineApi.searchCollections(genre, CollectionKind.playlist),
  ]);
  final songs = results[0] as List<OnlineSong>;
  final playlists = results[1] as List<OnlineCollection>;
  return OnlinePage(
    title: genre,
    songs: songs,
    shelves: [
      if (playlists.isNotEmpty) OnlineShelf(genre, collections: playlists),
    ],
  );
});

/// Personalized search autocompletions & query suggestions from YouTube Music.
final onlineSuggestionsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, input) async {
      if (!ref.watch(onlineActiveProvider) || input.trim().isEmpty) {
        return const [];
      }
      try {
        return await OnlineApi.suggestions(input.trim());
      } catch (_) {
        return const [];
      }
    });

/// True only when online features are enabled AND the user has a signed-in Google account.
final isOnlineConnectedProvider = Provider<bool>((ref) {
  final active = ref.watch(onlineActiveProvider);
  final auth = ref.watch(authProvider);
  return active && auth.status == AuthStatus.signedIn;
});

/// Revision counter bumped whenever account data sync writes new cache entries.
class AccountDataRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final accountDataRevisionProvider =
    NotifierProvider<AccountDataRevisionNotifier, int>(
      AccountDataRevisionNotifier.new,
    );

final onlineAccountPlaylistsProvider = FutureProvider<List<OnlineCollection>>((
  ref,
) async {
  if (!ref.watch(isOnlineConnectedProvider)) return const [];
  ref.watch(accountDataRevisionProvider);
  return AccountDataSync.getAccountPlaylists();
});

final onlineAccountArtistsProvider = FutureProvider<List<OnlineCollection>>((
  ref,
) async {
  if (!ref.watch(isOnlineConnectedProvider)) return const [];
  ref.watch(accountDataRevisionProvider);
  return AccountDataSync.getAccountArtists();
});

final onlineAccountAlbumsProvider = FutureProvider<List<OnlineCollection>>((
  ref,
) async {
  if (!ref.watch(isOnlineConnectedProvider)) return const [];
  ref.watch(accountDataRevisionProvider);
  return AccountDataSync.getAccountAlbums();
});

final onlineAccountFavoritesProvider = FutureProvider<List<OnlineSong>>((
  ref,
) async {
  if (!ref.watch(isOnlineConnectedProvider)) return const [];
  ref.watch(accountDataRevisionProvider);
  return AccountDataSync.getAccountFavorites();
});

final onlineAccountHistoryProvider = FutureProvider<List<OnlineSong>>((
  ref,
) async {
  if (!ref.watch(isOnlineConnectedProvider)) return const [];
  ref.watch(accountDataRevisionProvider);
  return AccountDataSync.getAccountHistory();
});

/// Follows [TasteProfileStore.revision]: bumps whenever the profile relearns.
class _TasteRevision extends Notifier<int> {
  @override
  int build() {
    final revision = TasteProfileStore.revision;
    void listener() => state = revision.value;
    revision.addListener(listener);
    ref.onDispose(() => revision.removeListener(listener));
    return revision.value;
  }
}

final _tasteRevisionProvider = NotifierProvider<_TasteRevision, int>(
  _TasteRevision.new,
);

/// The home hero in online mode: For you as Today Mix, and a pool of online
/// songs (For you, the home shelves and the user's own online plays from the
/// last month, with play counts) for the artist pick, Weekly and Surprise
/// Me. Null when online mode is off. Refreshes as the taste profile relearns.
final homeHeroOnlineProvider =
    FutureProvider<({List<Song> mix, List<Song> pool})?>((ref) async {
      if (!ref.watch(onlineActiveProvider)) return null;
      final (forYou, shelves) = ref.watch(
        onlineHomeProvider.select((h) => (h.forYou, h.shelves)),
      );
      ref.watch(_tasteRevisionProvider);

      final pool = <String, Song>{};
      void add(OnlineSong o) => pool.putIfAbsent(o.path, o.toSong);
      forYou.forEach(add);
      for (final shelf in shelves) {
        shelf.songs.forEach(add);
      }

      try {
        final since = DateTime.now().subtract(const Duration(days: 30));
        final events = await DbService.isar.playEvents
            .filter()
            .songPathStartsWith('yt:')
            .playedAtGreaterThan(since)
            .findAll();
        for (final e in events) {
          // Skips are not plays.
          if ((e.durationMs ?? 0) > 0 && e.listenedMs < 30000) continue;
          final s = pool.putIfAbsent(
            e.songPath,
            () => Song()
              ..path = e.songPath
              ..title = e.songTitle
              ..artist = e.artist
              ..album = e.album
              ..duration = e.durationMs
              ..artPath =
                  'https://i.ytimg.com/vi/${e.songPath.substring(3)}/hqdefault.jpg'
              ..dateAdded = e.playedAt,
          );
          s.playCount++;
          final last = s.lastPlayed;
          if (last == null || e.playedAt.isAfter(last)) {
            s.lastPlayed = e.playedAt;
          }
        }
      } catch (e) {
        LoggerHelper.write('Home hero: online plays failed', e);
      }

      return (
        // Guests have no For you: the shelves' songs make the mix instead.
        mix: forYou.isNotEmpty
            ? [for (final o in forYou) pool[o.path]!]
            : pool.values.take(30).toList(),
        pool: pool.values.toList(),
      );
    });
