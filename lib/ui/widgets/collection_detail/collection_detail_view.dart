import 'package:looper_player/core/motion/list_wave.dart';
import 'package:looper_player/core/motion/scroll_stage.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/motion/looper_scroll_physics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:looper_player/core/utils/responsive.dart';
import 'package:looper_player/ui/android/widgets/premium_section.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/common/song_favorite_button.dart';
import 'package:looper_player/ui/widgets/common/playlist_reorderable_listener.dart';
import 'package:looper_player/ui/widgets/common/song_playback_overlay.dart';
import 'package:looper_player/ui/widgets/common/collection_scroll_to_end.dart';
import 'package:looper_player/ui/widgets/collection_detail/collection_hero.dart';
import 'package:looper_player/ui/widgets/sheets/app_bottom_sheet.dart';
import 'package:looper_player/ui/widgets/sheets/sort_menu_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/songs_list.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/playlists/presentation/screens/playlist_view.dart';
import 'package:looper_player/features/playlists/presentation/widgets/playlist_artwork.dart';
import 'package:looper_player/features/playlists/data/services/playlist_service.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/presentation/widgets/library_grids.dart';
import 'package:looper_player/ui/widgets/sheets/edit_album_sheet.dart';
import 'package:looper_player/ui/widgets/sheets/edit_artist_sheet.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/utils/song_metadata.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:looper_player/ui/widgets/sheets/song_options_bottom_sheet.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/presentation/widgets/animated_artwork_widget.dart';
part 'collection_header.dart';
part 'sort_sheet.dart';
part 'playlist_options.dart';
part 'album_groups.dart';

// Persistent collection sorting is stored in settings.collectionSortOptionIndex

enum CollectionSortOption {
  defaultOrder,
  titleAsc,
  titleDesc,
  artistAsc,
  albumAsc,
  duration,
  yearNewest,
  yearOldest,
}

class CollectionDetailView extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final String? artPath;
  final String? imageUrl;
  final List<Song> songs;
  final Playlist? playlist;
  final Album? album;
  final Artist? artist;

  const CollectionDetailView({
    super.key,
    required this.title,
    this.subtitle,
    this.artPath,
    this.imageUrl,
    required this.songs,
    this.playlist,
    this.album,
    this.artist,
  });

  /// Whether this page shows an artist (as opposed to an album, playlist or
  /// other song list).
  bool _isArtistPage(AppLocalizations l10n) =>
      playlist == null &&
      album == null &&
      (artist != null ||
          subtitle == l10n.artist ||
          subtitle == l10n.artists ||
          subtitle?.toLowerCase() == 'artist');

  String _durationLabel(List<Song> songs, AppLocalizations l10n) {
    if (songs.any((song) => (song.duration ?? 0) <= 0)) return l10n.unknown;
    final totalMs = songs.fold<int>(
      0,
      (sum, song) => sum + (song.duration ?? 0),
    );
    final minutes = (totalMs / 60000).round();
    return minutes >= 60
        ? l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60)
        : l10n.minutesShort(minutes);
  }

  String _metaText(
    String? label,
    List<Song> songs,
    AppLocalizations l10n, {
    bool songsLoading = false,
  }) {
    final hasLabel = label?.trim().isNotEmpty == true;
    return '${hasLabel ? '$label • ' : ''}${l10n.songsCount(songs.length)} • ${songsLoading ? l10n.unknown : _durationLabel(songs, l10n)}';
  }

  Widget _buildCollectionSubtitle(
    String? label,
    List<Song> songs,
    AppLocalizations l10n, {
    bool songsLoading = false,
    required double fontSize,
    required Color color,
  }) {
    // Keep all of the metadata readable when the header is narrow or text is
    // enlarged. A single Text wraps within the column's available width.
    return Text(
      _metaText(label, songs, l10n, songsLoading: songsLoading),
      style: AppFonts.jostStyle(fontSize: fontSize, color: color),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSong = ref.watch(playbackProvider.select((s) => s.currentSong));

    // Reactively watch the playlist object if it is passed, so the title updates when renamed
    final reactivePlaylist = playlist != null
        ? ref.watch(
            playlistProvider.select(
              (list) => list.firstWhere(
                (p) => p.id == playlist!.id,
                orElse: () => playlist!,
              ),
            ),
          )
        : null;

    // Reactively watch the album object if it is passed, so the header
    // (name/artist/artwork) updates live when the album is edited.
    // albumsProvider is a StreamProvider (AsyncValue), unlike playlistProvider
    // above which is a plain StateNotifierProvider<..., List<Playlist>>.
    final reactiveAlbum = album != null
        ? (ref
                  .watch(albumsProvider)
                  .value
                  ?.firstWhere(
                    (a) => a.id == album!.id,
                    orElse: () => album!,
                  ) ??
              album)
        : null;

    // Same for an artist, so a picture changed in the edit sheet shows here
    // straight away.
    final reactiveArtist = artist != null && album == null
        ? (ref
                  .watch(artistsProvider)
                  .value
                  ?.firstWhere(
                    (a) => a.id == artist!.id,
                    orElse: () => artist!,
                  ) ??
              artist)
        : null;
    final artistImage = reactiveArtist?.artistImageUrl;
    final artistImageIsUrl = artistImage?.startsWith('http') ?? false;

    final titleToRender =
        reactivePlaylist?.name ?? reactiveAlbum?.name ?? title;
    // Fall back to the static nav-args only when there is no reactive album at
    // all - once one is present its own (possibly now-null) fields are the
    // source of truth, so clearing the artwork/artist in the edit sheet is
    // reflected instead of being masked by the stale value passed at nav time.
    final artToRender = reactiveAlbum != null
        ? reactiveAlbum.artPath
        : reactiveArtist != null
        ? (artistImage != null && !artistImageIsUrl
              ? artistImage
              : reactiveArtist.artPath)
        : artPath;
    final imageUrlToRender = reactiveArtist != null
        ? (artistImageIsUrl ? artistImage : null)
        : imageUrl;
    final subtitleToRender = reactiveAlbum != null
        ? reactiveAlbum.artist
        : subtitle;

    // Reactively watch songs of this playlist/album using their respective providers
    final playlistSongsAsync = playlist != null
        ? ref.watch(playlistSongsProvider(playlist!.id))
        : null;
    final albumSongsAsync = reactiveAlbum != null
        ? ref.watch(songsForAlbumProvider(reactiveAlbum.name))
        : null;

    final songsLoading = playlistSongsAsync != null
        ? !playlistSongsAsync.hasValue
        : albumSongsAsync != null && !albumSongsAsync.hasValue;

    final songsToRender = playlistSongsAsync != null
        ? (playlistSongsAsync.value ?? <Song>[])
        : albumSongsAsync != null
        ? (albumSongsAsync.value ?? <Song>[])
        : songs;

    final sortOptionIndex = ref.watch(
      settingsProvider.select((s) => s.collectionSortOptionIndex),
    );
    final sortOption =
        CollectionSortOption.values[sortOptionIndex.clamp(
          0,
          CollectionSortOption.values.length - 1,
        )];
    var sortedSongs = List<Song>.from(songsToRender);
    switch (sortOption) {
      case CollectionSortOption.defaultOrder:
        break;
      case CollectionSortOption.titleAsc:
        sortedSongs.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case CollectionSortOption.titleDesc:
        sortedSongs.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case CollectionSortOption.artistAsc:
        sortedSongs.sort(
          (a, b) => (a.artist ?? '').toLowerCase().compareTo(
            (b.artist ?? '').toLowerCase(),
          ),
        );
        break;
      case CollectionSortOption.albumAsc:
        sortedSongs.sort(
          (a, b) => (a.album ?? '').toLowerCase().compareTo(
            (b.album ?? '').toLowerCase(),
          ),
        );
        break;
      case CollectionSortOption.duration:
        sortedSongs.sort(
          (a, b) => (a.duration ?? 0).compareTo(b.duration ?? 0),
        );
        break;
      case CollectionSortOption.yearNewest:
        sortedSongs.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case CollectionSortOption.yearOldest:
        sortedSongs.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
        break;
    }

    final canReorderPlaylist =
        reactivePlaylist != null &&
        sortOption == CollectionSortOption.defaultOrder;

    // Artist pages can list their songs under album headers. The flattened
    // grouped order is also the play order.
    final groupByAlbum =
        ref.watch(settingsProvider.select((s) => s.artistGroupByAlbum)) &&
        _isArtistPage(AppLocalizations.of(context)!);
    final albumGroups = groupByAlbum && sortedSongs.isNotEmpty
        ? _groupByAlbum(sortedSongs, sortOption)
        : null;
    if (albumGroups != null) {
      sortedSongs = [for (final g in albumGroups) ...g.songs];
    }
    // Header or song index, in display order.
    final groupedItems = albumGroups == null
        ? null
        : <Object>[
            for (final g in albumGroups) ...[
              g,
              for (var i = 0; i < g.songs.length; i++) g.start + i,
            ],
          ];

    final l10n = AppLocalizations.of(context)!;
    final isArtist = _isArtistPage(l10n);
    final meta = _metaText(
      reactivePlaylist != null ? l10n.playlist : subtitleToRender,
      sortedSongs,
      l10n,
      songsLoading: songsLoading,
    );
    final thumbnail = imageUrlToRender ?? artToRender;

    return Scaffold(
      // Not Colors.transparent - see the comment on CategoryDetailWrapper's
      // Scaffold in library_categories_views.dart for why.
      backgroundColor: Theme.of(context).colorScheme.surface,
      // The hero runs under the status bar.
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = Responsive.isLandscape(
              MediaQuery.sizeOf(context),
            );
            Widget songRow(int index, {int? reorderIndex}) => SongTile(
              key: ValueKey((sortedSongs[index].path, index)),
              song: sortedSongs[index],
              l10n: l10n,
              songs: sortedSongs,
              playlist: reactivePlaylist,
              collectionIndex: index,
              reorderIndex: reorderIndex,
            );
            final songDelegate = SliverChildBuilderDelegate(
              waveItems((context, index) => songRow(index)),
              childCount: sortedSongs.length,
            );
            Widget buildScrollView(ScrollController controller) => Stack(
              children: [
                ListWave(
                  child: CustomScrollView(
                    controller: controller,
                    physics: const LooperScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: CollectionHero(
                          isArtist: isArtist,
                          title: titleToRender,
                          meta: meta,
                          albumArtist: reactiveAlbum?.artist,
                          album: reactiveAlbum?.name,
                          still: _heroStill(
                            reactivePlaylist,
                            artToRender,
                            imageUrlToRender,
                          ),
                          actions: _heroActions(
                            context,
                            ref,
                            isArtist: isArtist,
                            title: titleToRender,
                            songs: sortedSongs,
                            thumbnail: thumbnail,
                            playlist: reactivePlaylist,
                            album: reactiveAlbum,
                            artist: reactiveArtist,
                            canReorder:
                                canReorderPlaylist && sortedSongs.length > 1,
                          ),
                        ),
                      ),
                      if (groupedItems != null)
                        SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final item = groupedItems[i];
                            return item is _AlbumGroup
                                ? _AlbumGroupHeader(
                                    group: item,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      20,
                                      8,
                                      8,
                                    ),
                                  )
                                : songRow(item as int);
                          }, childCount: groupedItems.length),
                        )
                      else if (sortedSongs.isNotEmpty)
                        // Dragging to reorder only makes sense while sortedSongs is
                        // actually the playlist's own saved order - once a sort
                        // option (title/artist/duration/...) is applied, a row's
                        // on-screen position no longer corresponds to a slot in
                        // playlist.songPaths that dragging could sensibly write to.
                        if (canReorderPlaylist)
                          SliverReorderableList(
                            // Equal-height rows let Flutter jump without laying out
                            // every intervening song. Measure one for text scaling.
                            prototypeItem: TickerMode(
                              enabled: false,
                              child: songRow(0),
                            ),
                            itemBuilder: (context, index) =>
                                songRow(index, reorderIndex: index),
                            itemCount: sortedSongs.length,
                            onReorderStart: (_) => AppHaptics.medium(),
                            onReorder: (oldIndex, newIndex) {
                              PlaylistService.reorderSong(
                                reactivePlaylist,
                                oldIndex,
                                newIndex,
                              );
                            },
                          )
                        else
                          SliverPrototypeExtentList(
                            prototypeItem: TickerMode(
                              enabled: false,
                              child: songRow(0),
                            ),
                            delegate: songDelegate,
                          ),
                      if (isArtist && ref.watch(onlineActiveProvider))
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: _ExploreOnlineArtistCard(
                              artistName: titleToRender,
                              thumbnail: thumbnail,
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: 200,
                        ), // Added padding to fix navbar overlap
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CollectionHeroBar(
                    controller: controller,
                    title: titleToRender,
                    meta: meta,
                    cover: _miniCover(
                      reactivePlaylist,
                      artToRender,
                      imageUrlToRender,
                    ),
                    onBack: () =>
                        ref.read(appNavigationProvider.notifier).goBack(),
                    trailing: isArtist
                        ? _ArtistFollowButton(
                            artistName: titleToRender,
                            thumbnail: thumbnail,
                            height: 40,
                          )
                        : null,
                    action: reactivePlaylist != null
                        ? HeroRoundButton(
                            icon: LucideIcons.plus,
                            size: 40,
                            onTap: () => _showAddSongsHint(context),
                          )
                        : null,
                  ),
                ),
              ],
            );
            // In landscape, cap the reading width and center it instead of
            // stretching the song list edge-to-edge across the whole window.
            // One tree for both orientations, only the cap changes: swapping
            // the parent on rotation remounted the scroll view, the shared
            // controller briefly had two positions, and the hero bar's
            // `offset` threw (white screen on rotate).
            return CollectionScrollToEnd(
              bottomPadding: activeSong != null ? 100 : 16,
              builder: (controller) => Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLandscape ? 700 : double.infinity,
                  ),
                  child: buildScrollView(controller),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ExploreOnlineArtistCard extends ConsumerWidget {
  const _ExploreOnlineArtistCard({required this.artistName, this.thumbnail});

  final String artistName;
  final String? thumbnail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PremiumSection(
      useExpanded: false,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => _exploreArtistOnline(context, artistName, thumbnail),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.sparkles,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.onlineDiscover} $artistName',
                  style: AppFonts.jostStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.onlineEnabledDesc,
                  style: AppFonts.jostStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

Future<void> _exploreArtistOnline(
  BuildContext context,
  String artistName,
  String? thumbnail,
) async {
  AppHaptics.light();
  try {
    final list = await OnlineApi.searchCollections(
      artistName,
      CollectionKind.artist,
    );
    if (!context.mounted) return;
    final match =
        list
            .where((c) => c.title.toLowerCase() == artistName.toLowerCase())
            .firstOrNull ??
        list.firstOrNull;
    if (match != null) {
      openOnlineCollection(context, match);
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.onlineNoResults),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.onlineLoadFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
