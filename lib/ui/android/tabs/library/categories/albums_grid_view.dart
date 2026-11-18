import 'package:looper_player/core/motion/list_wave.dart';
import 'package:looper_player/core/providers/collection_navigation.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:looper_player/ui/widgets/common/filter_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/ui/widgets/common/app_loading_indicator.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/common/empty_state_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'library_categories_views.dart';

enum _AlbumSourceFilter { all, onDevice, youtube }

class AlbumsGridView extends ConsumerStatefulWidget {
  const AlbumsGridView({super.key});

  @override
  ConsumerState<AlbumsGridView> createState() => _AlbumsGridViewState();
}

class _AlbumsGridViewState extends ConsumerState<AlbumsGridView> {
  _AlbumSourceFilter _filter = _AlbumSourceFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sortOptionIndex = ref.watch(
      settingsProvider.select((s) => s.albumSortOptionIndex),
    );
    final sortOption = AlbumSortOption
        .values[sortOptionIndex.clamp(0, AlbumSortOption.values.length - 1)];
    final albumsAsync = ref.watch(albumsSortedProvider(sortOption));
    final onlineAlbums =
        ref.watch(onlineAccountAlbumsProvider).value ??
        const <OnlineCollection>[];
    final accent = ref.watch(settingsProvider).accent;

    return Builder(
      builder: (context) {
        if (!albumsAsync.hasValue) return const AppLoadingIndicator();
        final albums = albumsAsync.requireValue;

        final showOnline = onlineAlbums.isNotEmpty;
        final showLocal =
            _filter == _AlbumSourceFilter.all ||
            _filter == _AlbumSourceFilter.onDevice;
        final showCloud =
            showOnline &&
            (_filter == _AlbumSourceFilter.all ||
                _filter == _AlbumSourceFilter.youtube);

        final q = CategorySearch.of(context);
        final displayLocal = showLocal
            ? [
                for (final a in albums)
                  if (CategorySearch.matches(q, [a.name, a.artist])) a,
              ]
            : const <Album>[];
        // Hide online albums already on device: same title and, when
        // YouTube names one, the same artist ("Greatest Hits" is many albums).
        final localArtists = <String, List<String>>{};
        for (final a in albums) {
          (localArtists[a.name.toLowerCase()] ??= []).add(
            (a.artist ?? '').toLowerCase(),
          );
        }
        bool onDevice(OnlineCollection a) {
          final artists = localArtists[a.title.toLowerCase()];
          if (artists == null) return false;
          if (a.artists.isEmpty) return true;
          return artists.any(
            (l) => a.artists.any((o) => l.contains(o.toLowerCase())),
          );
        }

        final displayOnline = showCloud
            ? [
                for (final a in onlineAlbums)
                  if ((!showLocal || !onDevice(a)) &&
                      CategorySearch.matches(q, [a.title, ...a.artists]))
                    a,
              ]
            : const <OnlineCollection>[];

        final totalDisplayCount = displayLocal.length + displayOnline.length;

        if (albums.isEmpty && onlineAlbums.isEmpty) {
          return EmptyStateCard(
            icon: LucideIcons.disc,
            title: l10n.noAlbumsFound,
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            const crossAxisSpacing = 24.0;
            const horizontalPadding = 24.0;
            const textBlockHeight = 54.0;
            const targetColumnWidth = 200.0;
            final availableWidth = constraints.maxWidth - horizontalPadding * 2;
            final crossAxisCount = math.max(
              2,
              ((availableWidth + crossAxisSpacing) /
                      (targetColumnWidth + crossAxisSpacing))
                  .floor(),
            );
            final itemWidth =
                (availableWidth - crossAxisSpacing * (crossAxisCount - 1)) /
                crossAxisCount;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showOnline)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterPill(
                            label:
                                'All (${albums.length + onlineAlbums.length})',
                            isSelected: _filter == _AlbumSourceFilter.all,
                            accent: accent,
                            onTap: () => setState(
                              () => _filter = _AlbumSourceFilter.all,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterPill(
                            label: 'On Device (${albums.length})',
                            isSelected: _filter == _AlbumSourceFilter.onDevice,
                            accent: accent,
                            onTap: () => setState(
                              () => _filter = _AlbumSourceFilter.onDevice,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterPill(
                            label: 'YouTube Music (${onlineAlbums.length})',
                            isSelected: _filter == _AlbumSourceFilter.youtube,
                            accent: accent,
                            onTap: () => setState(
                              () => _filter = _AlbumSourceFilter.youtube,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: totalDisplayCount == 0
                      ? EmptyStateCard(
                          icon: LucideIcons.disc,
                          title: l10n.noAlbumsFound,
                        )
                      : ListWave(
                          child: GridView.builder(
                            padding: const EdgeInsets.only(
                              left: horizontalPadding,
                              right: horizontalPadding,
                              top: 20,
                              bottom: 200,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 24,
                                  crossAxisSpacing: crossAxisSpacing,
                                  mainAxisExtent: itemWidth + textBlockHeight,
                                ),
                            itemCount: totalDisplayCount,
                            itemBuilder: waveItems((context, index) {
                              if (index < displayLocal.length) {
                                final album = displayLocal[index];
                                return InkWell(
                                  onTap: () async {
                                    await ref
                                        .read(appNavigationProvider.notifier)
                                        .showAlbum(
                                          album,
                                          unknownArtist: l10n.unknownArtist,
                                        );
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 1,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: OptimizedImage(
                                            imagePath: album.artPath,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        album.name,
                                        style: AppFonts.jostStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        album.artist ?? l10n.unknownArtist,
                                        style: AppFonts.jostStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final onlineIndex = index - displayLocal.length;
                              return _OnlineAlbumCard(
                                album: displayOnline[onlineIndex],
                              );
                            }),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _OnlineAlbumCard extends StatelessWidget {
  final OnlineCollection album;
  const _OnlineAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openOnlineCollection(context, album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OptimizedImage(
                    imageUrl: album.thumbnail,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: Colors.white10,
                      child: const Center(
                        child: Icon(
                          LucideIcons.disc,
                          size: 40,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.cloud,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            album.title,
            style: AppFonts.jostStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            album.subtitle ?? 'YouTube Music',
            style: AppFonts.jostStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
