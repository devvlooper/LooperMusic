import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/looper_scroll_physics.dart';
import 'package:looper_player/core/motion/scroll_stage.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/song_tile.dart';
import 'package:looper_player/features/online/data/online_downloader.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/widgets/premium_section.dart';
import 'package:looper_player/ui/widgets/collection_detail/collection_pinned_bar.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/presentation/widgets/animated_artwork_widget.dart';
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
  final GlobalKey _titleKey = GlobalKey();

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
    final isArtist = widget.collection.kind == CollectionKind.artist ||
        widget.collection.browseId.startsWith('UC') ||
        widget.collection.subtitle?.toLowerCase().contains('subscriber') == true;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: page.when(
          loading: () => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    PremiumSection(
                      useExpanded: false,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        bottomLeft: Radius.circular(32),
                        topRight: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                      width: 48,
                      height: 48,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      useBlur: true,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Icon(
                        LucideIcons.chevronLeft,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          error: (e, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    PremiumSection(
                      useExpanded: false,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        bottomLeft: Radius.circular(32),
                        topRight: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                      width: 48,
                      height: 48,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      useBlur: true,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Icon(
                        LucideIcons.chevronLeft,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
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
                                onlineGenrePageProvider(widget.collection.title),
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
            final title =
                p.title.isEmpty ? widget.collection.title : p.title;
            final subtitle = p.subtitle ?? widget.collection.subtitle;

            return CustomScrollView(
              controller: _controller,
              physics: const LooperScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: CollectionPinnedBar(
                    controller: _controller,
                    titleKey: _titleKey,
                    title: title,
                    imageUrl: art,
                    onBack: () => Navigator.of(context).maybePop(),
                    onAdd: songs.isNotEmpty
                        ? () {
                            AppHaptics.light();
                            ref
                                .read(downloadsProvider.notifier)
                                .enqueueAll(p.songs);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(l10n.downloadQueued(songs.length)),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        : null,
                    actionIcon: LucideIcons.download,
                  ),
                ),
                SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 450;
                      final motionArt = isArtist
                          ? ref.watch(animatedArtworkForArtistProvider(title))
                          : ref.watch(
                              animatedArtworkForCollectionProvider((
                                artist: subtitle,
                                album: title,
                              )),
                            );
                      final mediaSrc = motionArt.asData?.value?.bestSquareMedia;

                      final staticOnlineArt = OnlineArt(
                        url: art,
                        size: 140,
                        round: isArtist,
                        icon: isArtist
                            ? LucideIcons.user
                            : LucideIcons.disc3,
                      );

                      final artWidget = ScrollStage(
                        controller: _controller,
                        length: 220,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: mediaSrc != null
                              ? SizedBox(
                                  width: 140,
                                  height: 140,
                                  child: AnimatedArtworkWidget(
                                    mediaSource: mediaSrc,
                                    staticFallback: staticOnlineArt,
                                    borderRadius: BorderRadius.circular(
                                      isArtist ? 70 : 16,
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : staticOnlineArt,
                        ),
                      );

                      final infoWidget = Column(
                        crossAxisAlignment: isNarrow
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            key: _titleKey,
                            textAlign: isNarrow
                                ? TextAlign.center
                                : TextAlign.start,
                            style: AppFonts.jostStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (subtitle != null && subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              textAlign: isNarrow
                                  ? TextAlign.center
                                  : TextAlign.start,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.jostStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          if (songs.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              l10n.songsCount(songs.length),
                              style: AppFonts.jostStyle(
                                fontSize: 13,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            alignment: isNarrow
                                ? WrapAlignment.center
                                : WrapAlignment.start,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (songs.isNotEmpty) ...[
                                FilledButton.icon(
                                  onPressed: () {
                                    AppHaptics.light();
                                    ref
                                        .read(playbackProvider.notifier)
                                        .playCollection(songs);
                                  },
                                  icon: const Icon(LucideIcons.play, size: 18),
                                  label: Text(l10n.playAll),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    AppHaptics.light();
                                    ref
                                        .read(playbackProvider.notifier)
                                        .playCollection(songs, shuffle: true);
                                  },
                                  icon: const Icon(LucideIcons.shuffle,
                                      size: 18),
                                  label: Text(l10n.shuffleTitle),
                                ),
                              ],
                              if (isArtist)
                                _FollowButton(
                                  collection: widget.collection,
                                  title: title,
                                  thumbnail: art,
                                ),
                            ],
                          ),
                        ],
                      );

                      return Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: isNarrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Center(child: artWidget),
                                  const SizedBox(height: 18),
                                  infoWidget,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  artWidget,
                                  const SizedBox(width: 20),
                                  Expanded(child: infoWidget),
                                ],
                              ),
                      );
                    },
                  ),
                ),
                if (isArtist && p.songs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnlineSectionTitle(l10n.songs),
                        SizedBox(
                          height: 186,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: p.songs.length,
                            itemBuilder: (context, i) => OnlineSongCard(
                              songs: p.songs,
                              index: i,
                            ),
                          ),
                        ),
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
  });
  final OnlineCollection collection;
  final String title;
  final String? thumbnail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final artistName = title.isNotEmpty ? title : collection.title;
    final following = ref.watch(
      tasteProvider.select((t) => t.hasArtist(artistName)),
    );

    return following
        ? FilledButton.tonalIcon(
            onPressed: () {
              AppHaptics.light();
              ref.read(tasteProvider.notifier).toggleArtist(
                    TasteArtist(
                      artistName,
                      browseId: collection.browseId,
                      thumbnail: thumbnail ?? collection.thumbnail,
                    ),
                  );
            },
            icon: const Icon(LucideIcons.check, size: 18),
            label: Text(l10n.onlineFollowing),
          )
        : OutlinedButton.icon(
            onPressed: () {
              AppHaptics.light();
              ref.read(tasteProvider.notifier).toggleArtist(
                    TasteArtist(
                      artistName,
                      browseId: collection.browseId,
                      thumbnail: thumbnail ?? collection.thumbnail,
                    ),
                  );
            },
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(l10n.onlineFollow),
          );
  }
}
