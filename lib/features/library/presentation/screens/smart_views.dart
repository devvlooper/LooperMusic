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
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/app_loading_indicator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum PagedQueryKind { favorites, history, downloads }

class PagedSongs {
  final List<Song> items;
  final int total;
  final bool loadingMore;

  const PagedSongs({
    required this.items,
    required this.total,
    this.loadingMore = false,
  });

  PagedSongs copyWith({
    List<Song>? items,
    int? total,
    bool? loadingMore,
  }) =>
      PagedSongs(
        items: items ?? this.items,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
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

    if (kind == PagedQueryKind.downloads) {
      _downloadDirs = (await DownloadFolders.all()).toList();
    }
    final total = await _filterQuery().count();
    final items = await _sortedQuery().limit(pageSize).findAll();

    // In unified mode, merge cloud favorites / history if connected
    final isConnected = ref.watch(isOnlineConnectedProvider);
    if (isConnected) {
      if (kind == PagedQueryKind.favorites) {
        final onlineFavorites = await AccountDataSync.getAccountFavorites();
        final seen = {for (final s in items) s.title.toLowerCase(): s};
        final extra = [
          for (final s in onlineFavorites)
            if (!seen.containsKey(s.title.toLowerCase()))
              s.toSong()..isFavorite = true,
        ];
        return PagedSongs(
          items: [...items, ...extra],
          total: total + extra.length,
          loadingMore: false,
        );
      } else if (kind == PagedQueryKind.history) {
        final onlineHistory = await AccountDataSync.getAccountHistory();
        final seen = {for (final s in items) s.title.toLowerCase(): s};
        final extra = [
          for (final s in onlineHistory)
            if (!seen.containsKey(s.title.toLowerCase())) s.toSong(),
        ];
        return PagedSongs(
          items: [...items, ...extra],
          total: total + extra.length,
          loadingMore: false,
        );
      }
    }

    return PagedSongs(items: items, total: total, loadingMore: false);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
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
    if (kind == PagedQueryKind.downloads) {
      _downloadDirs = (await DownloadFolders.all()).toList();
    }
    final current = state.value;
    final limit = math.max(pageSize, current?.items.length ?? pageSize);
    final total = await _filterQuery().count();
    final items = await _sortedQuery().limit(limit).findAll();

    final isConnected = ref.read(isOnlineConnectedProvider);
    if (isConnected) {
      if (kind == PagedQueryKind.favorites) {
        final onlineFavorites = await AccountDataSync.getAccountFavorites();
        final seen = {for (final s in items) s.title.toLowerCase(): s};
        final extra = [
          for (final s in onlineFavorites)
            if (!seen.containsKey(s.title.toLowerCase()))
              s.toSong()..isFavorite = true,
        ];
        state = AsyncData(
          PagedSongs(
            items: [...items, ...extra],
            total: total + extra.length,
            loadingMore: false,
          ),
        );
        return;
      } else if (kind == PagedQueryKind.history) {
        final onlineHistory = await AccountDataSync.getAccountHistory();
        final seen = {for (final s in items) s.title.toLowerCase(): s};
        final extra = [
          for (final s in onlineHistory)
            if (!seen.containsKey(s.title.toLowerCase())) s.toSong(),
        ];
        state = AsyncData(
          PagedSongs(
            items: [...items, ...extra],
            total: total + extra.length,
            loadingMore: false,
          ),
        );
        return;
      }
    }

    state = AsyncData(
      PagedSongs(items: items, total: total, loadingMore: false),
    );
  }

  Future<List<Song>> fetchAll({String? search}) async {
    final local = await _sortedQuery(search: search).findAll();
    if (!ref.read(isOnlineConnectedProvider)) return local;
    if (kind == PagedQueryKind.favorites) {
      final onlineFavorites = await AccountDataSync.getAccountFavorites();
      final seen = {for (final s in local) s.title.toLowerCase(): s};
      return [
        ...local,
        for (final s in onlineFavorites)
          if (!seen.containsKey(s.title.toLowerCase()))
            s.toSong()..isFavorite = true,
      ];
    } else if (kind == PagedQueryKind.history) {
      final onlineHistory = await AccountDataSync.getAccountHistory();
      final seen = {for (final s in local) s.title.toLowerCase(): s};
      return [
        ...local,
        for (final s in onlineHistory)
          if (!seen.containsKey(s.title.toLowerCase())) s.toSong(),
      ];
    }
    return local;
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

class FavoritesView extends ConsumerWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pagedAsync = ref.watch(pagedSongsProvider(PagedQueryKind.favorites));

    return pagedAsync.when(
      data: (paged) => paged.items.isEmpty
          ? _buildEmpty(context, LucideIcons.heart, l10n.noFavoritesYet)
          : SongsList(
              songs: paged.items,
              totalCount: paged.total,
              loading: paged.loadingMore,
              onEndReached: () => ref
                  .read(pagedSongsProvider(PagedQueryKind.favorites).notifier)
                  .loadMore(),
              onRefresh: () => ref
                  .read(pagedSongsProvider(PagedQueryKind.favorites).notifier)
                  .refresh(),
              resolveQueue: () => ref
                  .read(pagedSongsProvider(PagedQueryKind.favorites).notifier)
                  .fetchAll(),
            ),
      loading: () => const AppLoadingIndicator(),
      error: (e, s) => Center(child: Text(context.l10n.errorWithDetails('$e'))),
    );
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
}

class RecentlyPlayedView extends ConsumerWidget {
  const RecentlyPlayedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pagedAsync = ref.watch(pagedSongsProvider(PagedQueryKind.history));

    return pagedAsync.when(
      data: (paged) => paged.items.isEmpty
          ? _buildEmpty(context, LucideIcons.clock, l10n.noHistoryYet)
          : SongsList(
              songs: paged.items,
              totalCount: paged.total,
              loading: paged.loadingMore,
              onEndReached: () => ref
                  .read(pagedSongsProvider(PagedQueryKind.history).notifier)
                  .loadMore(),
              onRefresh: () => ref
                  .read(pagedSongsProvider(PagedQueryKind.history).notifier)
                  .refresh(),
              resolveQueue: () => ref
                  .read(pagedSongsProvider(PagedQueryKind.history).notifier)
                  .fetchAll(),
            ),
      loading: () => const AppLoadingIndicator(),
      error: (e, s) => Center(child: Text(context.l10n.errorWithDetails('$e'))),
    );
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
