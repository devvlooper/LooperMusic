import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/online/data/account_data_sync.dart';
import 'package:looper_player/features/online/data/online_downloader.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';

enum PagedQueryKind { favorites, history, downloads }

/// Which songs Favorites / History show, like the playlist screen's chips.
enum SongSource { all, onDevice, youtube }

class PagedSongs {
  final List<Song> items;
  final int total;
  final bool loadingMore;

  /// Summed duration of all [total] songs, in milliseconds.
  final int totalMs;

  /// Favorites / History show one page at a time; downloads scroll on.
  final int page;
  final SongSource source;

  const PagedSongs({
    required this.items,
    required this.total,
    this.loadingMore = false,
    this.totalMs = 0,
    this.page = 0,
    this.source = SongSource.all,
  });

  int get pageCount => (total / PagedSongsNotifier.pageSize).ceil();

  PagedSongs copyWith({List<Song>? items, int? total, bool? loadingMore}) =>
      PagedSongs(
        items: items ?? this.items,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
        totalMs: totalMs,
        page: page,
        source: source,
      );
}

final pagedSongsProvider =
    AsyncNotifierProvider.family<
      PagedSongsNotifier,
      PagedSongs,
      PagedQueryKind
    >(PagedSongsNotifier.new);

class PagedSongsNotifier extends AsyncNotifier<PagedSongs> {
  PagedSongsNotifier(this.kind);
  final PagedQueryKind kind;

  static const int pageSize = 100;
  StreamSubscription? _sub;
  Timer? _debounce;
  bool _disposed = false;
  List<String> _downloadDirs = const [];
  SongSource _source = SongSource.all;
  int _page = 0;

  bool get _paged => kind != PagedQueryKind.downloads;

  QueryBuilder<Song, Song, QAfterFilterCondition> _filterQuery({
    String? search,
  }) {
    var q = switch (kind) {
      PagedQueryKind.favorites =>
        DbService.isar.songs.filter().isFavoriteEqualTo(true),
      PagedQueryKind.history =>
        DbService.isar.songs.filter().lastPlayedIsNotNull(),
      // Files inside a folder downloads went to (never a guess by name).
      PagedQueryKind.downloads => DbService.isar.songs.filter().anyOf(
        _downloadDirs.isEmpty ? const ['\u0000none'] : _downloadDirs,
        (q, dir) => q.pathStartsWith(dir.endsWith('/') ? dir : '$dir/'),
      ),
    };
    q = switch (_source) {
      SongSource.all => q,
      SongSource.onDevice => q.and().not().pathStartsWith('yt:'),
      SongSource.youtube => q.and().pathStartsWith('yt:'),
    };
    if (search != null && search.trim().isNotEmpty) {
      final term = search.trim();
      q = q.and().group(
        (g) => g
            .titleContains(term, caseSensitive: false)
            .or()
            .artistContains(term, caseSensitive: false),
      );
    }
    return q;
  }

  QueryBuilder<Song, Song, QAfterSortBy> _sortedQuery({String? search}) {
    final filtered = _filterQuery(search: search);
    return switch (kind) {
      PagedQueryKind.favorites => filtered.sortByTitle(),
      PagedQueryKind.history => filtered.sortByLastPlayedDesc(),
      PagedQueryKind.downloads => filtered.sortByDateAddedDesc(),
    };
  }

  /// Signed-in account favorites / history not already in the local list,
  /// shown after the local songs.
  Future<List<Song>> _onlineExtras() async {
    if (_source == SongSource.onDevice ||
        !ref.read(isOnlineConnectedProvider)) {
      return const [];
    }
    final online = switch (kind) {
      PagedQueryKind.favorites => await AccountDataSync.getAccountFavorites(),
      PagedQueryKind.history => await AccountDataSync.getAccountHistory(),
      PagedQueryKind.downloads => const <OnlineSong>[],
    };
    if (online.isEmpty) return const [];
    // Title and artist: a title alone merges different songs ("Intro").
    String key(String title, String? artist) =>
        '${title.toLowerCase()}|${(artist ?? '').toLowerCase()}';
    final local = _filterQuery();
    final titles = await local.titleProperty().findAll();
    final artists = await local.artistProperty().findAll();
    final seen = {
      for (var i = 0; i < titles.length; i++) key(titles[i], artists[i]),
    };
    return [
      for (final s in online)
        if (seen.add(key(s.title, s.artist)))
          s.toSong()..isFavorite = kind == PagedQueryKind.favorites,
    ];
  }

  /// The current page (Favorites / History) or the first [limit] rows
  /// (downloads).
  Future<PagedSongs> _load({int limit = pageSize}) async {
    if (kind == PagedQueryKind.downloads) {
      _downloadDirs = (await DownloadFolders.all()).toList();
    }
    final localTotal = await _filterQuery().count();
    final extra = await _onlineExtras();
    final total = localTotal + extra.length;
    final totalMs = [
      ...await _filterQuery().durationProperty().findAll(),
      for (final s in extra) s.duration,
    ].fold<int>(0, (sum, d) => sum + (d ?? 0));
    if (!_paged) {
      final items = await _sortedQuery().limit(limit).findAll();
      return PagedSongs(
        items: items,
        total: total,
        totalMs: totalMs,
        source: _source,
      );
    }
    _page = _page.clamp(0, math.max(0, (total - 1) ~/ pageSize));
    final start = _page * pageSize;
    final local = start < localTotal
        ? await _sortedQuery().offset(start).limit(pageSize).findAll()
        : <Song>[];
    final items = [
      ...local,
      ...extra
          .skip(math.max(0, start - localTotal))
          .take(pageSize - local.length),
    ];
    return PagedSongs(
      items: items,
      total: total,
      totalMs: totalMs,
      page: _page,
      source: _source,
    );
  }

  @override
  Future<PagedSongs> build() async {
    // Riverpod 3 keeps this notifier across rebuilds but runs onDispose on
    // each one, so every build must undo it: a stale _disposed made refresh
    // (source chips, paging) a no-op and the DB watch stayed cancelled.
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _debounce?.cancel();
    });

    _sub = DbService.isar.songs.watchLazy().listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (!_disposed) {
          unawaited(refresh());
        }
      });
    });

    // Reload when the account connects / disconnects (cloud extras).
    ref.watch(isOnlineConnectedProvider);
    return _load();
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (_paged ||
        current == null ||
        current.loadingMore ||
        current.items.length >= current.total) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final nextChunk = await _sortedQuery()
          .offset(current.items.length)
          .limit(pageSize)
          .findAll();
      final total = await _filterQuery().count();
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...nextChunk],
          total: total,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  Future<void> refresh() async {
    final loaded = state.value?.items.length ?? pageSize;
    final page = _page, source = _source;
    final next = await _load(limit: math.max(pageSize, loaded));
    // A newer page / filter change already replaced this result.
    if (_disposed || page != _page || source != _source) return;
    state = AsyncData(next);
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setSource(SongSource source) async {
    if (source == _source) return;
    _source = source;
    _page = 0;
    await refresh();
  }

  /// Every song of the current filter, for the play queue.
  Future<List<Song>> fetchAll({String? search}) async {
    final local = await _sortedQuery(search: search).findAll();
    return [...local, ...await _onlineExtras()];
  }
}

/// Backwards compatibility provider for [favorites].
final favoritesProvider = Provider.autoDispose<AsyncValue<List<Song>>>((ref) {
  return ref
      .watch(pagedSongsProvider(PagedQueryKind.favorites))
      .whenData((p) => p.items);
});

/// Backwards compatibility provider for [recentlyPlayedScreen].
final recentlyPlayedScreenProvider =
    Provider.autoDispose<AsyncValue<List<Song>>>((ref) {
      return ref
          .watch(pagedSongsProvider(PagedQueryKind.history))
          .whenData((p) => p.items);
    });
