import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/core/utils/l10n.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/songs_list.dart';
import 'package:looper_player/features/online/data/account_data_sync.dart';
import 'package:looper_player/features/online/data/online_downloader.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/filter_pill.dart';
import 'package:looper_player/ui/widgets/common/app_loading_indicator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum PagedQueryKind { favorites, history, downloads }

/// Which songs Favorites / History show, like the playlist screen's chips.
enum SongSource { all, onDevice, youtube }

class PagedSongs {
  final List<Song> items;
  final int total;
  final bool loadingMore;

  /// Favorites / History show one page at a time; downloads scroll on.
  final int page;
  final SongSource source;

  const PagedSongs({
    required this.items,
    required this.total,
    this.loadingMore = false,
    this.page = 0,
    this.source = SongSource.all,
  });

  int get pageCount => (total / PagedSongsNotifier.pageSize).ceil();

  PagedSongs copyWith({
    List<Song>? items,
    int? total,
    bool? loadingMore,
  }) =>
      PagedSongs(
        items: items ?? this.items,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
        page: page,
        source: source,
      );
}

final pagedSongsProvider =
    AsyncNotifierProvider.family<PagedSongsNotifier, PagedSongs, PagedQueryKind>(
  PagedSongsNotifier.new,
);

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

  QueryBuilder<Song, Song, QAfterSortBy> _sortedQuery({
    String? search,
  }) {
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
    final seen = {
      for (final t in await _filterQuery().titleProperty().findAll())
        t.toLowerCase(),
    };
    return [
      for (final s in online)
        if (seen.add(s.title.toLowerCase()))
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
    if (!_paged) {
      final items = await _sortedQuery().limit(limit).findAll();
      return PagedSongs(items: items, total: total, source: _source);
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
      page: _page,
      source: _source,
    );
  }

  @override
  Future<PagedSongs> build() async {
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _debounce?.cancel();
    });

    _sub ??= DbService.isar.songs.watchLazy().listen((_) {
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
  return ref.watch(pagedSongsProvider(PagedQueryKind.favorites)).whenData(
        (p) => p.items,
      );
});

/// Backwards compatibility provider for [recentlyPlayedScreen].
final recentlyPlayedScreenProvider =
    Provider.autoDispose<AsyncValue<List<Song>>>((ref) {
  return ref.watch(pagedSongsProvider(PagedQueryKind.history)).whenData(
        (p) => p.items,
      );
});

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) => _PagedSongsView(
        kind: PagedQueryKind.favorites,
        emptyIcon: LucideIcons.heart,
        emptyText: AppLocalizations.of(context)!.noFavoritesYet,
      );
}

class RecentlyPlayedView extends StatelessWidget {
  const RecentlyPlayedView({super.key});

  @override
  Widget build(BuildContext context) => _PagedSongsView(
        kind: PagedQueryKind.history,
        emptyIcon: LucideIcons.clock,
        emptyText: AppLocalizations.of(context)!.noHistoryYet,
      );
}

/// Favorites / History: source chips on top (while online music is on),
/// one page of songs, and a page switcher at the end of the list.
class _PagedSongsView extends ConsumerWidget {
  const _PagedSongsView({
    required this.kind,
    required this.emptyIcon,
    required this.emptyText,
  });

  final PagedQueryKind kind;
  final IconData emptyIcon;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pagedSongsProvider(kind);
    final pagedAsync = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final showChips = ref.watch(onlineActiveProvider);
    final accent = ref.watch(settingsProvider).accent;

    return pagedAsync.when(
      data: (paged) {
        final list = paged.items.isEmpty
            ? _buildEmpty(context, emptyIcon, emptyText)
            : SongsList(
                // New page: fresh list scrolled to the top.
                key: ValueKey('${paged.source}-${paged.page}'),
                songs: paged.items,
                totalCount: paged.total,
                onRefresh: notifier.refresh,
                resolveQueue: notifier.fetchAll,
                footer: paged.pageCount > 1
                    ? _PageBar(
                        page: paged.page,
                        pageCount: paged.pageCount,
                        onPage: notifier.goToPage,
                      )
                    : null,
              );
        if (!showChips) return list;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (source, label) in const [
                      (SongSource.all, 'All'),
                      (SongSource.onDevice, 'On Device'),
                      (SongSource.youtube, 'YouTube Music'),
                    ]) ...[
                      FilterPill(
                        label: label,
                        isSelected: paged.source == source,
                        accent: accent,
                        onTap: () => notifier.setSource(source),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(child: list),
          ],
        );
      },
      loading: () => const AppLoadingIndicator(),
      error: (e, s) => Center(child: Text(context.l10n.errorWithDetails('$e'))),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.page,
    required this.pageCount,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    void go(int p) {
      AppHaptics.selection();
      onPage(p);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft, size: 20),
            tooltip: 'Previous page',
            onPressed: page > 0 ? () => go(page - 1) : null,
          ),
          const SizedBox(width: 8),
          Text(
            'Page ${page + 1} of $pageCount',
            style: AppFonts.jostStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight, size: 20),
            tooltip: 'Next page',
            onPressed: page < pageCount - 1 ? () => go(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

Widget _buildEmpty(BuildContext context, IconData icon, String text) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: Colors.grey.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text(text),
      ],
    ),
  );
}

/// Whether Library shows "Downloads": always while online music is on (so
/// the screen is easy to find), else while any download exists.
final hasDownloadsProvider = Provider<bool>((ref) {
  if (ref.watch(onlineActiveProvider)) return true;
  if (ref.watch(downloadsProvider).isNotEmpty) return true;
  final paged =
      ref.watch(pagedSongsProvider(PagedQueryKind.downloads)).asData?.value;
  return (paged?.total ?? 0) > 0;
});

class DownloadsView extends ConsumerWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pagedAsync = ref.watch(pagedSongsProvider(PagedQueryKind.downloads));
    final downloadsMap = ref.watch(downloadsProvider);
    final activeDownloads = downloadsMap.values
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.failed)
        .toList();

    return pagedAsync.when(
      data: (paged) {
        if (paged.items.isEmpty && activeDownloads.isEmpty) {
          return _buildEmpty(context, LucideIcons.download, l10n.noSongsFound);
        }

        final activeSection = activeDownloads.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Downloading (${activeDownloads.length})',
                          style: AppFonts.jostStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                        if (activeDownloads
                            .any((d) => d.status == DownloadStatus.failed))
                          TextButton(
                            onPressed: () => ref
                                .read(downloadsProvider.notifier)
                                .clearFailed(),
                            child: Text(
                              'Clear failed',
                              style: AppFonts.jostStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final item in activeDownloads) ...[
                      _DownloadProgressTile(item: item),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              );

        if (paged.items.isEmpty) {
          return SingleChildScrollView(
            child: activeSection!,
          );
        }

        if (activeSection == null) {
          return SongsList(
            songs: paged.items,
            totalCount: paged.total,
            loading: paged.loadingMore,
            onEndReached: () => ref
                .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
                .loadMore(),
            onRefresh: () => ref
                .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
                .refresh(),
            resolveQueue: () => ref
                .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
                .fetchAll(),
          );
        }

        return Column(
          children: [
            activeSection,
            const Divider(height: 1, color: Colors.white10),
            Expanded(
              child: SongsList(
                songs: paged.items,
                totalCount: paged.total,
                loading: paged.loadingMore,
                onEndReached: () => ref
                    .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
                    .loadMore(),
                onRefresh: () => ref
                    .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
                    .refresh(),
                resolveQueue: () => ref
                    .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
                    .fetchAll(),
              ),
            ),
          ],
        );
      },
      loading: () => const AppLoadingIndicator(),
      error: (e, s) => Center(child: Text(context.l10n.errorWithDetails('$e'))),
    );
  }
}

class _DownloadProgressTile extends ConsumerWidget {
  const _DownloadProgressTile({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    final isDownloading = item.status == DownloadStatus.downloading;
    final isQueued = item.status == DownloadStatus.queued;
    final isFailed = item.status == DownloadStatus.failed;

    final percent = (item.progress * 100).clamp(0, 100).toInt();
    final statusText = isDownloading
        ? '$percent%'
        : isQueued
            ? 'Queued'
            : 'Failed';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OnlineArt(
                url: item.song.thumbnail,
                size: 44,
                round: false,
                icon: LucideIcons.music,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.jostStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.song.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.jostStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: AppFonts.jostStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isFailed
                      ? Colors.redAccent
                      : isDownloading
                          ? accent
                          : Colors.white54,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                color: Colors.white38,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  AppHaptics.light();
                  ref.read(downloadsProvider.notifier).cancel(item.song.videoId);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isDownloading
                  ? item.progress
                  : isQueued
                      ? null
                      : 1.0,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                isFailed ? Colors.redAccent : accent,
              ),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
