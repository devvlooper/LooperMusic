import 'package:looper_player/ui/widgets/common/empty_state_card.dart';
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
import 'package:looper_player/ui/android/tabs/library/categories/category_detail_wrapper.dart'
    show CategorySearch;

import 'package:looper_player/features/library/presentation/providers/library/paged_songs_notifier.dart';
export 'package:looper_player/features/library/presentation/providers/library/paged_songs_notifier.dart';

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

    final q = CategorySearch.of(context);
    return pagedAsync.when(
      data: (paged) {
        final list = q.isNotEmpty
            ? _SearchedSongs(query: q, fetch: notifier.fetchAll)
            : paged.items.isEmpty
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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

/// Every song of a paged list matching [query] (title or artist), not just
/// the page on screen.
class _SearchedSongs extends StatefulWidget {
  const _SearchedSongs({required this.query, required this.fetch});

  final String query;
  final Future<List<Song>> Function({String? search}) fetch;

  @override
  State<_SearchedSongs> createState() => _SearchedSongsState();
}

class _SearchedSongsState extends State<_SearchedSongs> {
  late Future<List<Song>> _results = _load();

  // fetchAll filters local songs only; the account's online extras come
  // back unfiltered, so filter the whole result here.
  Future<List<Song>> _load() async => [
    for (final s in await widget.fetch(search: widget.query))
      if (CategorySearch.matches(widget.query, [s.title, s.artist])) s,
  ];

  @override
  void didUpdateWidget(_SearchedSongs old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _results = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Song>>(
      future: _results,
      builder: (context, snap) {
        final songs = snap.data;
        if (songs == null) return const AppLoadingIndicator();
        if (songs.isEmpty) {
          return _buildEmpty(
            context,
            LucideIcons.searchX,
            context.l10n.noSongsFound,
          );
        }
        return SongsList(songs: songs, searchQuery: widget.query);
      },
    );
  }
}

Widget _buildEmpty(BuildContext context, IconData icon, String text) {
  return EmptyStateCard(icon: icon, title: text);
}

/// Whether Library shows "Downloads": always while online music is on (so
/// the screen is easy to find), else while any download exists.
final hasDownloadsProvider = Provider<bool>((ref) {
  if (ref.watch(onlineActiveProvider)) return true;
  if (ref.watch(downloadsProvider).isNotEmpty) return true;
  final paged = ref
      .watch(pagedSongsProvider(PagedQueryKind.downloads))
      .asData
      ?.value;
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
        .where(
          (d) =>
              d.status == DownloadStatus.downloading ||
              d.status == DownloadStatus.queued ||
              d.status == DownloadStatus.failed,
        )
        .toList();

    final q = CategorySearch.of(context);
    if (q.isNotEmpty) {
      return _SearchedSongs(
        query: q,
        fetch: ref
            .read(pagedSongsProvider(PagedQueryKind.downloads).notifier)
            .fetchAll,
      );
    }
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
                        if (activeDownloads.any(
                          (d) => d.status == DownloadStatus.failed,
                        ))
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
          return SingleChildScrollView(child: activeSection!);
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  ref
                      .read(downloadsProvider.notifier)
                      .cancel(item.song.videoId);
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
