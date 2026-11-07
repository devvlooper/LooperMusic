import 'package:looper_player/core/motion/looper_scroll_physics.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/core/providers/collection_navigation.dart';
import 'dart:math' as math;

import 'package:looper_player/core/utils/song_metadata.dart';

import 'package:flutter/material.dart';
import 'package:looper_player/ui/widgets/common/song_artwork.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/core/theme/app_icons.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/core/utils/responsive.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/songs_list.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/playlists/presentation/screens/playlist_view.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/app_refresh_indicator.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/common/selected_avatar.dart';
import 'package:looper_player/ui/widgets/sheets/song_options_bottom_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../widgets/empty_library_view.dart';
import '../../widgets/enrichment_indicator.dart';
import '../../widgets/library_skeletons.dart';
import '../../widgets/premium_loading_view.dart';
import '../../widgets/premium_section.dart';
import '../library/categories/library_categories_views.dart';
import '../../widgets/genre_card.dart';
import '../../widgets/recent_song_pills.dart';

import 'package:looper_player/core/services/haptics/app_haptics.dart';
part 'home_sections.dart';

class AndroidHomeTab extends ConsumerStatefulWidget {
  const AndroidHomeTab({super.key});

  @override
  ConsumerState<AndroidHomeTab> createState() => _AndroidHomeTabState();
}

class _AndroidHomeTabState extends ConsumerState<AndroidHomeTab> {
  int _currentQuickPickPage = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showSongOptions(BuildContext context, Song song) {
    showSongOptionsBottomSheet(
      context: context,
      ref: ref,
      song: song,
      showEqualizerAndTechnicalInfoOptions: false,
    );
  }

  void _buildQuickPicksSlivers(
    BuildContext context,
    List<Widget> orderedSlivers,
    List<Song> allQuickPicks,
    AppLocalizations l10n,
    bool useBlur,
    bool showArtistInQuickPicks,
    bool showAlbumInQuickPicks,
  ) {
    orderedSlivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.quickPicks,
                    style: AppFonts.jostStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.todayMixForYou,
                    style: AppFonts.jostStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              PremiumSection(
                borderRadius: BorderRadius.circular(32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 0,
                ),
                height: 40,
                useExpanded: false,
                useBlur: useBlur,
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                forceNoBlur: true,
                onTap: () {
                  if (allQuickPicks.isNotEmpty) {
                    AppHaptics.medium();
                    final shuffledPicks = List<Song>.from(allQuickPicks)
                      ..shuffle();
                    ref
                        .read(playbackProvider.notifier)
                        .setPlaylist(shuffledPicks, initialIndex: 0);
                  }
                },
                child: SvgPicture.asset(AppIcons.shuffleHome, width: 40),
              ),
            ],
          ),
        ),
      ),
    );

    orderedSlivers.add(
      SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = (constraints.maxWidth - 32).clamp(
              0.0,
              double.infinity,
            );
            final isLandscape = Responsive.isLandscape(
              MediaQuery.sizeOf(context),
            );
            final crossAxisCount = isLandscape
                ? math.max(3, ((availableWidth + 8) / (110 + 8)).floor())
                : 3;
            final itemWidth =
                ((availableWidth - 8 * (crossAxisCount - 1)) /
                        crossAxisCount)
                    .clamp(0.0, double.infinity);
            final gridHeight = ((itemWidth * 2) + 8).clamp(
              8.0,
              double.infinity,
            );
            final itemsPerPage = crossAxisCount * 2;

            final pageCount = (allQuickPicks.length / itemsPerPage).ceil();
            final validPageCount = pageCount == 0 ? 1 : pageCount;

            return Column(
              children: [
                SizedBox(
                  height: gridHeight,
                  child: PageView.builder(
                    onPageChanged: (index) {
                      setState(() {
                        _currentQuickPickPage = index;
                      });
                    },
                    itemCount: validPageCount,
                    itemBuilder: (context, pageIndex) {
                      final startIndex = pageIndex * itemsPerPage;
                      if (startIndex >= allQuickPicks.length &&
                          allQuickPicks.isNotEmpty) {
                        return const SizedBox();
                      }

                      final pageItems = allQuickPicks
                          .skip(startIndex)
                          .take(itemsPerPage)
                          .toList();

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                        ),
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 1.0,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: pageItems.length,
                          itemBuilder: (context, index) {
                            final song = pageItems[index];
                            final isSuggested = ref
                                .watch(homeQuickPicksSuggestedPathsProvider)
                                .contains(song.path);

                            return GestureDetector(
                              onTap: () {
                                ref
                                    .read(playbackProvider.notifier)
                                    .setPlaylist(
                                      allQuickPicks,
                                      initialIndex: startIndex + index,
                                    );
                              },
                              onLongPress: () {
                                AppHaptics.medium();
                                _showSongOptions(context, song);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: SongArtwork(
                                        song: song,
                                        size: itemWidth,
                                        indicatorSize: 32,
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black54,
                                            ],
                                            stops: [0.5, 1.0],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isSuggested)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.6,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            LucideIcons.sparkles,
                                            size: 11,
                                            color: Colors.amberAccent,
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      left: 8,
                                      bottom: 8,
                                      right: 8,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            song.title,
                                            style: AppFonts.jostStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (showArtistInQuickPicks)
                                            Text(
                                              artistAlbumLabel(
                                                song,
                                                l10n,
                                                showAlbum:
                                                    showAlbumInQuickPicks,
                                              ),
                                              style: AppFonts.jostStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.6),
                                                fontSize: 10,
                                              ),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(validPageCount, (index) {
                    final isActive = _currentQuickPickPage == index;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
    orderedSlivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Quick Picks show the title only until "Show Album Next to Artist" is on.
    final showArtistInQuickPicks = watchShowAlbum(ref);
    final showAlbumInQuickPicks = watchShowAlbumInQuickPicks(ref);
    // This tab is now permanently mounted alongside Songs/Library (see
    // AndroidMainScreen) instead of being torn down on every tab switch, so
    // an unscoped watch of the entire LibraryState/AppSettings objects meant
    // it silently rebuilt this whole (large, image-heavy) tab in the
    // background on every unrelated settings tweak or library write - e.g.
    // every darkness slider drag, or the ~20s listen-time checkpoint during
    // any playback - even while a different tab was on screen. Select just
    // the fields this tab actually renders.
    final (
      songs,
      rawArtists,
      rawAlbums,
      isInitialized,
      isScanning,
      previewReady,
      previewQuickPicks,
      previewRecentlyAdded,
    ) = ref.watch(
      libraryProvider.select(
        (s) => (
          s.songs,
          s.artists,
          s.albums,
          s.isInitialized,
          s.isScanning,
          s.previewReady,
          s.previewQuickPicks,
          s.previewRecentlyAdded,
        ),
      ),
    );
    // App start, saved library still loading: Quick Picks and Recently
    // Added come from small queries of their own, and every other section
    // shows a skeleton until its data is in.
    final bool loadingInParts = !isInitialized && previewReady;
    final l10n = AppLocalizations.of(context)!;
    final (
      albumSortOptionIndex,
      artistSortOptionIndex,
      genreSortOptionIndex,
      disableBlur,
      enableDynamicTheming,
      homeSectionOrder,
      showHomeArtists,
      showHomeAlbums,
      showHomeGenres,
      showHomeRecent,
      showHomePlaylists,
    ) = ref.watch(
      settingsProvider.select(
        (s) => (
          s.albumSortOptionIndex,
          s.artistSortOptionIndex,
          s.genreSortOptionIndex,
          s.disableBlur,
          s.enableDynamicTheming,
          s.homeSectionOrder,
          s.showHomeArtists,
          s.showHomeAlbums,
          s.showHomeGenres,
          s.showHomeRecent,
          s.showHomePlaylists ?? true,
        ),
      ),
    );
    final recentSongs = ref.watch(dashboardRecentlyPlayedProvider).value ?? [];
    final playlists = ref.watch(dashboardPlaylistsProvider).value ?? [];

    final albumSort =
        AlbumSortOption.values[albumSortOptionIndex.clamp(
          0,
          AlbumSortOption.values.length - 1,
        )];
    final artistSort =
        ArtistSortOption.values[artistSortOptionIndex.clamp(
          0,
          ArtistSortOption.values.length - 1,
        )];
    final genreSort =
        GenreSortOption.values[genreSortOptionIndex.clamp(
          0,
          GenreSortOption.values.length - 1,
        )];

    final genresMap = <String, List<Song>>{};
    for (var song in songs) {
      final genre = song.genre ?? l10n.unknown;
      genresMap.putIfAbsent(genre, () => []).add(song);
    }

    final genres = genresMap.keys.toList();
    switch (genreSort) {
      case GenreSortOption.nameAsc:
        genres.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
      case GenreSortOption.nameDesc:
        genres.sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
        break;
      case GenreSortOption.songCountDesc:
        genres.sort(
          (a, b) => genresMap[b]!.length.compareTo(genresMap[a]!.length),
        );
        break;
      case GenreSortOption.songCountAsc:
        genres.sort(
          (a, b) => genresMap[a]!.length.compareTo(genresMap[b]!.length),
        );
        break;
    }

    final artists = List<Artist>.from(rawArtists);
    if (artistSort == ArtistSortOption.nameAsc) {
      artists.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } else {
      artists.sort(
        (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      );
    }

    final albums = List<Album>.from(rawAlbums);
    switch (albumSort) {
      case AlbumSortOption.nameAsc:
        albums.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case AlbumSortOption.nameDesc:
        albums.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case AlbumSortOption.dateAddedNewest:
        albums.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case AlbumSortOption.dateAddedOldest:
        albums.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
        break;
      case AlbumSortOption.yearNewest:
        albums.sort((a, b) {
          if (a.year == null && b.year == null) return 0;
          if (a.year == null) return 1;
          if (b.year == null) return -1;
          return b.year!.compareTo(a.year!);
        });
        break;
      case AlbumSortOption.yearOldest:
        albums.sort((a, b) {
          if (a.year == null && b.year == null) return 0;
          if (a.year == null) return 1;
          if (b.year == null) return -1;
          return a.year!.compareTo(b.year!);
        });
        break;
    }

    // Reopening the app: the saved library is still loading from the
    // database - show the layout it's about to fill.
    if (!isInitialized && !previewReady) {
      return const LoadStateSwitcher(state: 'loading', child: HomeSkeleton());
    }

    // First scan of an empty library can take minutes; keep the animated
    // view with its rotating progress messages for that.
    if (isScanning && songs.isEmpty) {
      return const LoadStateSwitcher(
        state: 'scanning',
        child: PremiumLoadingView(),
      );
    }

    if (songs.isEmpty && !loadingInParts && !ref.watch(onlineActiveProvider)) {
      return LoadStateSwitcher(
        state: 'empty',
        child: SafeArea(child: EmptyLibraryView(title: l10n.noSongsFound)),
      );
    }

    // Quick Picks (most played, up to 18 for 3 pages of 6) and Recently
    // Added (newest first) are computed in memoized providers instead of
    // inline here - same sort, same output, just not redone on every
    // rebuild of this screen. See their doc comments in library_notifier.dart.
    final fullQuickPicks = ref.watch(homeQuickPicksMixedProvider);
    final fullDateAddedSongs = ref.watch(homeRecentlyAddedProvider);
    final allQuickPicks = loadingInParts ? previewQuickPicks : fullQuickPicks;
    final dateAddedSongs = loadingInParts
        ? previewRecentlyAdded
        : fullDateAddedSongs;

    final useBlur = enableDynamicTheming && !disableBlur;

    final orderedSlivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  // Square avatars sit centered in a 40dp slot as before; a
                  // wide logo keeps the 38dp height and grows to the right
                  // (capped so it stays clear of the centered indicator).
                  SizedBox(
                    height: 38,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 40),
                      child: const Center(
                        child: SelectedAvatar(size: 38, maxWidth: 130),
                      ),
                    ),
                  ),
                  // The enriching pill takes only the space between the
                  // avatar and the buttons (shrinking to fit instead of
                  // sliding under them on narrow screens / long languages).
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: EnrichmentIndicator(),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      PremiumSection(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          bottomLeft: Radius.circular(32),
                          topRight: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        width: 48,
                        height: 48,
                        useExpanded: false,
                        useBlur: useBlur,
                        forceNoBlur: true,
                        backgroundColor: Colors.white.withValues(alpha: 0.04),
                        onTap: () {
                          AppHaptics.light();
                          ref
                              .read(appNavigationProvider.notifier)
                              .setItem(NavItem.search);
                        },
                        child: const Icon(
                          LucideIcons.search,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      if (ref.watch(onlineActiveProvider)) ...[
                        const SizedBox(width: 5),
                        const OnlineStatusIndicator(),
                      ],
                      const SizedBox(width: 5),
                      PremiumSection(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                          topRight: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                        width: 48,
                        height: 48,
                        useExpanded: false,
                        useBlur: useBlur,
                        backgroundColor: Colors.white.withValues(alpha: 0.04),
                        forceNoBlur: true,
                        onTap: () {
                          AppHaptics.light();
                          ref
                              .read(appNavigationProvider.notifier)
                              .setItem(NavItem.settings);
                        },
                        child: const Icon(
                          LucideIcons.settings,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];

    // Quick picks is pinned first, ignoring homeSectionOrder.
    if (allQuickPicks.isNotEmpty) {
      _buildQuickPicksSlivers(
        context,
        orderedSlivers,
        allQuickPicks,
        l10n,
        useBlur,
        showArtistInQuickPicks,
        showAlbumInQuickPicks,
      );
    }

    // Online feed follows Quick picks.
    orderedSlivers.add(const OnlineHomeSliver());

    for (final section in homeSectionOrder) {
      if (section == 'quick_picks') continue;
      if (section == 'songs') {
        orderedSlivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.songs,
                    style: AppFonts.jostStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PremiumSection(
                    borderRadius: BorderRadius.circular(32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    height: 40,
                    useExpanded: false,
                    useBlur: useBlur,
                    forceNoBlur: true,
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    onTap: () {
                      AppHaptics.light();
                      ref
                          .read(appNavigationProvider.notifier)
                          .setItem(NavItem.songs);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.viewAll,
                          style: AppFonts.jostStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          LucideIcons.arrowRight,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        orderedSlivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = dateAddedSongs[index];
                return SongTile(
                  showAlbum: true,
                  key: ValueKey(song.path),
                  song: song,
                  l10n: l10n,
                  songs: dateAddedSongs,
                  // Only the first rows are loaded yet; a tap queues the
                  // whole Recently Added list once it is in.
                  resolveQueue: loadingInParts
                      ? () async {
                          await ref
                              .read(libraryProvider.notifier)
                              .loadedSongs();
                          return ref.read(homeRecentlyAddedProvider);
                        }
                      : null,
                );
              },
              childCount: dateAddedSongs.length > 10
                  ? 10
                  : dateAddedSongs.length,
            ),
          ),
        );
        orderedSlivers.add(
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        );
      } else if (section == 'playlists') {
        if (showHomePlaylists && playlists.isNotEmpty) {
          final displayCount = math.min(15, playlists.length);
          final hasMore = playlists.length > 15;
          orderedSlivers.add(
            _buildHorizontalSection(
              title: l10n.playlists,
              actionText: l10n.viewAll,
              onActionTap: () {
                AppHaptics.medium();
                ref
                    .read(appNavigationProvider.notifier)
                    .setItem(NavItem.playlists);
              },
              itemCount: displayCount + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= displayCount) {
                  return _buildViewAllEndCard(
                    onTap: () => ref
                        .read(appNavigationProvider.notifier)
                        .setItem(NavItem.playlists),
                    l10n: l10n,
                    width: 120,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 120,
                    child: PlaylistCard(playlist: playlists[index]),
                  ),
                );
              },
            ),
          );
        }
      } else if (section == 'artists') {
        if (showHomeArtists && (artists.isNotEmpty || loadingInParts)) {
          final displayCount = math.min(15, artists.length);
          final hasMore = artists.length > 15;
          orderedSlivers.add(
            _buildHorizontalSection(
              title: l10n.artists,
              actionText: l10n.viewAll,
              onActionTap: () {
                AppHaptics.medium();
                ref
                    .read(appNavigationProvider.notifier)
                    .setItem(NavItem.artists);
              },
              itemCount: (loadingInParts && artists.isEmpty)
                  ? 0
                  : displayCount + (hasMore ? 1 : 0),
              loading: loadingInParts && artists.isEmpty,
              circleSkeleton: true,
              itemBuilder: (context, index) {
                if (index >= displayCount) {
                  return _buildViewAllEndCard(
                    onTap: () => ref
                        .read(appNavigationProvider.notifier)
                        .setItem(NavItem.artists),
                    l10n: l10n,
                    width: 110,
                    circle: true,
                  );
                }
                return _buildArtistItem(artists[index], l10n);
              },
            ),
          );
        }
      } else if (section == 'albums') {
        if (showHomeAlbums && (albums.isNotEmpty || loadingInParts)) {
          final displayCount = math.min(15, albums.length);
          final hasMore = albums.length > 15;
          orderedSlivers.add(
            _buildHorizontalSection(
              title: l10n.albums,
              actionText: l10n.viewAll,
              onActionTap: () {
                AppHaptics.medium();
                ref
                    .read(appNavigationProvider.notifier)
                    .setItem(NavItem.albums);
              },
              itemCount: (loadingInParts && albums.isEmpty)
                  ? 0
                  : displayCount + (hasMore ? 1 : 0),
              loading: loadingInParts && albums.isEmpty,
              itemBuilder: (context, index) {
                if (index >= displayCount) {
                  return _buildViewAllEndCard(
                    onTap: () => ref
                        .read(appNavigationProvider.notifier)
                        .setItem(NavItem.albums),
                    l10n: l10n,
                    width: 120,
                  );
                }
                return _buildAlbumItem(albums[index], l10n);
              },
            ),
          );
        }
      } else if (section == 'genres') {
        // Genres are counted over every song, so they wait for all of them.
        if (showHomeGenres && (genres.isNotEmpty || loadingInParts)) {
          final displayCount = math.min(15, genres.length);
          final hasMore = genres.length > 15;
          orderedSlivers.add(
            _buildHorizontalSection(
              title: l10n.genres,
              actionText: l10n.viewAll,
              onActionTap: () {
                AppHaptics.medium();
                ref
                    .read(appNavigationProvider.notifier)
                    .setItem(NavItem.genres);
              },
              itemCount: (loadingInParts && genres.isEmpty)
                  ? 0
                  : displayCount + (hasMore ? 1 : 0),
              listHeight: _HomeTabSections.genreRowHeight,
              loading: loadingInParts && genres.isEmpty,
              itemBuilder: (context, index) {
                if (index >= displayCount) {
                  return _buildViewAllEndCard(
                    onTap: () => ref
                        .read(appNavigationProvider.notifier)
                        .setItem(NavItem.genres),
                    l10n: l10n,
                    width: _HomeTabSections._genreCardWidth,
                  );
                }
                final genre = genres[index];
                return _buildGenreItem(genre, genresMap[genre]!);
              },
            ),
          );
        }
      } else if (section == 'recent') {
        if (showHomeRecent && recentSongs.isNotEmpty) {
          orderedSlivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.recentPlayed,
                      style: AppFonts.jostStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PremiumSection(
                      borderRadius: BorderRadius.circular(32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      height: 40,
                      useExpanded: false,
                      useBlur: useBlur,
                      forceNoBlur: true,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      onTap: () {
                        AppHaptics.light();
                        ref
                            .read(appNavigationProvider.notifier)
                            .setItem(NavItem.history);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.viewAll,
                            style: AppFonts.jostStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            LucideIcons.arrowRight,
                            size: 16,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          orderedSlivers.add(
            SliverToBoxAdapter(
              child: RecentSongPills(songs: recentSongs, horizontalPadding: 16),
            ),
          );
          orderedSlivers.add(
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          );
        }
      }
    }

    if (!ref.watch(onlineActiveProvider)) {
      orderedSlivers.add(
        const SliverToBoxAdapter(
          child: OnlineDisabledHomeFooter(),
        ),
      );
    }

    orderedSlivers.add(const SliverToBoxAdapter(child: SizedBox(height: 200)));

    return LoadStateSwitcher(
      state: 'content',
      child: SafeArea(
        child: AppRefreshIndicator(
          onRefresh: () async {
            final futures = <Future>[];
            if (ref.read(onlineActiveProvider)) {
              futures.add(
                ref
                    .read(onlineHomeProvider.notifier)
                    .load(force: true)
                    .timeout(const Duration(seconds: 15))
                    .catchError((e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context)!.onlineLoadFailed,
                            ),
                          ),
                        );
                      }
                    }),
              );
            }
            ref
                .read(libraryProvider.notifier)
                .refreshLibrary(showVisualIndicator: true)
                .ignore();

            if (futures.isNotEmpty) {
              await Future.wait(futures);
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: LooperScrollPhysics(),
            ),
            slivers: orderedSlivers,
          ),
        ),
      ),
    );
  }
}
