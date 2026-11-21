import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/motion/looper_scroll_physics.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/song_tile.dart';
import 'package:looper_player/ui/widgets/common/queue_toggle.dart';
import 'package:looper_player/ui/widgets/common/home_design_kit.dart';
import 'package:looper_player/ui/widgets/sheets/song_options_bottom_sheet.dart';
import 'package:looper_player/ui/widgets/sheets/add_to_playlist_sheet.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_view_all_screen.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/collection_detail/collection_hero.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// An online album, playlist or artist: header, play/shuffle, the song
/// list, and (for artists) the carousels below it.
class OnlineCollectionScreen extends ConsumerStatefulWidget {
  const OnlineCollectionScreen({super.key, required this.collection});
  final OnlineCollection collection;

  @override
  ConsumerState<OnlineCollectionScreen> createState() =>
      _OnlineCollectionScreenState();
}

class _OnlineCollectionScreenState
    extends ConsumerState<OnlineCollectionScreen> {
  late final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isGenre = widget.collection.browseId.startsWith('genre:');
    final page = isGenre
        ? ref.watch(onlineGenrePageProvider(widget.collection.title))
        : ref.watch(onlinePageProvider(widget.collection.browseId));
    final isArtist =
        widget.collection.kind == CollectionKind.artist ||
        widget.collection.browseId.startsWith('UC') ||
        widget.collection.subtitle?.toLowerCase().contains('subscriber') ==
            true;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      // The hero runs under the status bar; loading / error keep the inset.
      body: SafeArea(
        top: !page.hasValue,
        child: page.when(
          loading: () => Column(
            children: [
              // Same button and spot as CollectionHeroBar once loaded.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: HeroRoundButton(
                      icon: LucideIcons.arrowLeft,
                      size: 40,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
          error: (e, _) => Column(
            children: [
              // Same button and spot as CollectionHeroBar once loaded.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: HeroRoundButton(
                      icon: LucideIcons.arrowLeft,
                      size: 40,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.onlineLoadFailed,
                        textAlign: TextAlign.center,
                        style: AppFonts.jostStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () => isGenre
                            ? ref.invalidate(
                                onlineGenrePageProvider(
                                  widget.collection.title,
                                ),
                              )
                            : ref.invalidate(
                                onlinePageProvider(widget.collection.browseId),
                              ),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (p) {
            final songs = [for (final s in p.songs) s.toSong()];
            final art = p.thumbnail ?? widget.collection.thumbnail;
            final title = p.title.isEmpty ? widget.collection.title : p.title;
            final subtitle = p.subtitle ?? widget.collection.subtitle;

            final totalMs = songs.fold<int>(0, (a, s) => a + (s.duration ?? 0));
            final meta = [
              if (songs.isNotEmpty) l10n.songsCount(songs.length),
              if (totalMs >= 60000) l10n.minutesShort(totalMs ~/ 60000),
            ].join(' \u2022 ');
            // Artists show their audience ("239M monthly audience").
            final metaLine = isArtist && subtitle != null
                ? subtitle
                : meta.isNotEmpty
                ? meta
                : (subtitle ?? '');
            void play({bool shuffle = false}) {
              AppHaptics.light();
              ref
                  .read(playbackProvider.notifier)
                  .playCollection(songs, shuffle: shuffle);
            }

            Widget follow({double height = 48}) => _FollowButton(
              collection: widget.collection,
              title: title,
              thumbnail: art,
              height: height,
            );

            return Stack(
              children: [
                CustomScrollView(
                  controller: _controller,
                  physics: const LooperScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: CollectionHero(
                        isArtist: isArtist,
                        title: title,
                        meta: metaLine,
                        albumArtist: subtitle,
                        album: isArtist ? null : title,
                        still: OptimizedImage(
                          imageUrl: art,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                        actions: Row(
                          children: [
                            if (songs.isNotEmpty) ...[
                              HeroPillButton(
                                icon: Icons.play_arrow_rounded,
                                label: l10n.play,
                                onTap: play,
                              ),
                              const SizedBox(width: 12),
                              HeroRoundButton(
                                icon: LucideIcons.shuffle,
                                size: 48,
                                onTap: () => play(shuffle: true),
                              ),
                            ],
                            if (!isArtist && songs.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              // Adds the whole album to a playlist, or makes
                              // a new one named after it.
                              HeroRoundButton(
                                icon: LucideIcons.listPlus,
                                size: 48,
                                semanticLabel: l10n.addToPlaylists,
                                onTap: () async {
                                  AppHaptics.light();
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final name = await showAddToPlaylistSheet(
                                    context,
                                    songs,
                                    suggestedName: title,
                                  );
                                  if (name == null) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.addedTo(name)),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            ],
                            // Follow takes the rest, right-aligned, and only
                            // shrinks (ellipsizing) when the row runs out.
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: isArtist ? follow() : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isArtist && songs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Two lines ("Top" over "Songs"), like every shelf.
                            HomeSectionHeader(
                              title: splitShelfTitle(l10n.topSongs).$2,
                              label: splitShelfTitle(l10n.topSongs).$1,
                              padding: const EdgeInsets.fromLTRB(
                                21,
                                15,
                                16,
                                12,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HeroRoundButton(
                                    icon: Icons.play_arrow_rounded,
                                    size: 41,
                                    fill: const Color(0x1AFFFFFF),
                                    onTap: play,
                                  ),
                                  if (p.moreSongsBrowseId != null ||
                                      songs.length > 5) ...[
                                    const SizedBox(width: 8),
                                    ViewAllHeaderButton(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          riseRoute(
                                            OnlineViewAllScreen(
                                              title: l10n.topSongs,
                                              initialSongs: p.songs,
                                              browseId: p.moreSongsBrowseId,
                                              params: p.moreSongsParams,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _ArtistSongPages(online: p.songs, songs: songs),
                          ],
                        ),
                      )
                    else if (!isArtist)
                      SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, i) => SongTile(
                          key: ValueKey('online-page-$i-${songs[i].path}'),
                          song: songs[i],
                          songs: songs,
                          l10n: l10n,
                          collectionIndex: i,
                        ),
                      ),
                    if (p.shelves.isNotEmpty)
                      SliverList.builder(
                        itemCount: p.shelves.length,
                        itemBuilder: (_, i) =>
                            OnlineShelfView(shelf: p.shelves[i]),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 180)),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CollectionHeroBar(
                    controller: _controller,
                    title: title,
                    meta: metaLine,
                    cover: OptimizedImage(
                      imageUrl: art,
                      width: 42,
                      height: 42,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onBack: () => Navigator.of(context).maybePop(),
                    trailing: isArtist ? follow(height: 40) : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Follow an artist: it joins the stated taste behind recommendations.
class _FollowButton extends ConsumerWidget {
  const _FollowButton({
    required this.collection,
    required this.title,
    this.thumbnail,
    this.height = 48,
  });
  final OnlineCollection collection;
  final String title;
  final String? thumbnail;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final artistName = title.isNotEmpty ? title : collection.title;
    final following = ref.watch(
      tasteProvider.select((t) => t.hasArtist(artistName)),
    );

    return HeroPillButton(
      icon: following ? Icons.check_circle_rounded : LucideIcons.plus,
      label: following ? l10n.onlineFollowing : l10n.onlineFollow,
      height: height,
      onTap: () {
        AppHaptics.light();
        ref
            .read(tasteProvider.notifier)
            .toggleArtist(
              TasteArtist(
                artistName,
                browseId: collection.browseId,
                thumbnail: thumbnail ?? collection.thumbnail,
              ),
            );
      },
    );
  }
}

/// Top songs as numbered columns of four that page sideways, the next
/// column peeking in at the edge.
class _ArtistSongPages extends StatelessWidget {
  const _ArtistSongPages({required this.online, required this.songs});

  final List<OnlineSong> online;
  final List<Song> songs;

  static const _perColumn = 4;
  static const _rowHeight = 56.0;
  static const _columnWidth = 330.0;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    final columns = (songs.length / _perColumn).ceil();
    Widget column(int c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (
          var i = c * _perColumn;
          i < math.min((c + 1) * _perColumn, songs.length);
          i++
        )
          _TopSongRow(online: online, songs: songs, index: i),
      ],
    );
    final height = math.min(_perColumn, songs.length) * _rowHeight;
    if (columns == 1) return column(0);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: height,
        child: PageView.builder(
          controller: PageController(
            viewportFraction: math.min(1, _columnWidth / constraints.maxWidth),
          ),
          padEnds: false,
          physics: const LooperScrollPhysics(),
          itemCount: columns,
          itemBuilder: (context, c) => column(c),
        ),
      ),
    );
  }
}

class _TopSongRow extends ConsumerWidget {
  const _TopSongRow({
    required this.online,
    required this.songs,
    required this.index,
  });

  final List<OnlineSong> online;
  final List<Song> songs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = songs[index];
    final artist = song.artist;
    return InkWell(
      onTap: () => playOnlineSongs(ref, online, index),
      child: SizedBox(
        height: _ArtistSongPages._rowHeight,
        child: Row(
          children: [
            QueueToggle(
              song: song,
              width: 55,
              height: _ArtistSongPages._rowHeight,
              number: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: homeCardTitle(),
              ),
            ),
            OnlineArt(url: online[index].thumbnail, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: homeCardTitle(),
                  ),
                  if (artist != null && artist.isNotEmpty)
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardTitle(size: 14).copyWith(color: kHomeGrey),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onPressed: () => showSongOptionsBottomSheet(
                context: context,
                ref: ref,
                song: song,
                showEqualizerAndTechnicalInfoOptions: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
