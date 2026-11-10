part of 'collection_detail_view.dart';

extension _CollectionHeader on CollectionDetailView {
  /// Songs join a playlist from their own options menu, so the playlist's +
  /// button explains where that is rather than opening a picker.
  void _showAddSongsHint(BuildContext context) {
    AppHaptics.light();
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            UiUtils.isDesktop
                ? l10n.addSongsToPlaylistHintDesktop
                : l10n.addSongsToPlaylistHint,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  /// Rows only start dragging after a long-press, which isn't discoverable
  /// on its own, so the playlist header's info button explains it.
  void _showReorderHint(BuildContext context) {
    AppHaptics.light();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.reorderSongsHint),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Widget _buildArt(
    BuildContext context,
    bool isNarrow,
    String? artOverride, {
    Playlist? playlist,
    String? imageUrl,
    Album? album,
    Artist? artist,
    WidgetRef? ref,
  }) {
    final double size = 140; // Unified size for a cleaner Row look
    final Widget staticArt;
    if (playlist != null) {
      staticArt = PlaylistArtwork(
        songPaths: playlist.songPaths,
        coverPath: playlist.coverPath,
        size: size,
        borderRadius: BorderRadius.circular(16),
      );
    } else {
      staticArt = OptimizedImage(
        imagePath: artOverride,
        imageUrl: imageUrl,
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(16),
        placeholder: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(LucideIcons.music, size: 48, color: Colors.grey),
        ),
      );
    }

    if (ref == null) return staticArt;

    String? mediaSource;
    if (album != null) {
      final motion = ref.watch(animatedArtworkForCollectionProvider((
        artist: album.artist,
        album: album.name,
      )));
      mediaSource = motion.asData?.value?.bestSquareMedia;
    } else if (artist != null) {
      final motion = ref.watch(animatedArtworkForArtistProvider(artist.name));
      mediaSource = motion.asData?.value?.bestSquareMedia;
    }

    if (mediaSource == null) return staticArt;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedArtworkWidget(
        mediaSource: mediaSource,
        staticFallback: staticArt,
        borderRadius: BorderRadius.circular(16),
        fit: BoxFit.cover,
      ),
    );
  }

  /// Artist pages: a full-bleed banner (motion art when there is some)
  /// with [info] over its faded bottom, like the online artist page.
  Widget _buildArtistHero(
    BuildContext context,
    WidgetRef ref, {
    required String? art,
    required String? imageUrl,
    required Widget info,
  }) {
    final banner =
        ref.watch(animatedArtworkForArtistProvider(title)).asData?.value;
    final mediaSrc = banner?.bestWideMedia;
    final still = OptimizedImage(
      imagePath: banner?.stillUrl == null ? art : null,
      imageUrl: banner?.stillUrl ?? imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
    );
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          mediaSrc != null
              ? AnimatedArtworkWidget(
                  mediaSource: mediaSrc,
                  staticFallback: still,
                  fit: BoxFit.cover,
                )
              : still,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.45),
                  Theme.of(context).colorScheme.surface,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(left: 16, right: 16, bottom: 16, child: info),
        ],
      ),
    );
  }

  Widget _buildInfo(
    BuildContext context,
    WidgetRef ref,
    bool isNarrow,
    String? activeArtworkPath,
    Playlist? reactivePlaylist,
    Album? reactiveAlbum,
    String titleToRender,
    String? subtitleToRender,
    List<Song> songsToRender, {
    bool songsLoading = false,
    bool canReorder = false,
    Key? titleKey,
    Artist? reactiveArtist,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isArtist = reactivePlaylist == null &&
        reactiveAlbum == null &&
        (reactiveArtist != null ||
            subtitleToRender == l10n.artist ||
            subtitleToRender == l10n.artists ||
            subtitleToRender?.toLowerCase() == 'artist');
    // Lit only while this collection is the one playing shuffled.
    final key = collectionKey(songsToRender);
    final isShuffle = ref.watch(
      playbackProvider.select((s) => s.isShuffle && s.queueSourceKey == key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleToRender,
          key: titleKey,
          style: AppFonts.jostStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: _buildCollectionSubtitle(
                reactivePlaylist != null ? l10n.playlist : subtitleToRender,
                songsToRender,
                l10n,
                fontSize: 16,
                songsLoading: songsLoading,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            if (canReorder)
              IconButton(
                tooltip: l10n.reorderSongsHint,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showReorderHint(context),
                icon: Icon(
                  LucideIcons.info,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final buttons = <Widget>[
              PremiumSection(
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                height: 44,
                useExpanded: false,
                onTap: () {
                  AppHaptics.medium();
                  final playback = ref.read(playbackProvider.notifier);
                  playback.playCollection(
                    songsToRender,
                    sourcePlaylistId: reactivePlaylist?.id,
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.play,
                      style: AppFonts.jostStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PremiumSection(
                borderRadius: BorderRadius.circular(12),
                width: 44,
                height: 44,
                useExpanded: false,
                backgroundColor: isShuffle
                    ? Colors.white.withValues(alpha: 0.10)
                    : null,
                onTap: () {
                  AppHaptics.light();
                  ref
                      .read(playbackProvider.notifier)
                      .toggleCollectionShuffle(
                        songsToRender,
                        sourcePlaylistId: reactivePlaylist?.id,
                      );
                },
                child: Semantics(
                  label: l10n.shuffleTitle,
                  toggled: isShuffle,
                  child: Icon(
                    LucideIcons.shuffle,
                    size: 16,
                    color: isShuffle
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PremiumSection(
                borderRadius: BorderRadius.circular(12),
                width: 44,
                height: 44,
                useExpanded: false,
                onTap: () {
                  AppHaptics.light();
                  _showSortBottomSheet(context, ref);
                },
                child: const Icon(
                  LucideIcons.arrowUpDown,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              if (isArtist) ...[
                const SizedBox(width: 8),
                _ArtistFollowButton(
                  artistName: titleToRender,
                  thumbnail: activeArtworkPath,
                ),
                if (ref.watch(onlineActiveProvider)) ...[
                  const SizedBox(width: 8),
                  PremiumSection(
                    borderRadius: BorderRadius.circular(12),
                    width: 44,
                    height: 44,
                    useExpanded: false,
                    onTap: () => _exploreArtistOnline(
                      context,
                      titleToRender,
                      activeArtworkPath,
                    ),
                    child: Semantics(
                      label: l10n.onlineDiscover,
                      child: const Icon(
                        LucideIcons.globe,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
              if (reactivePlaylist != null) ...[
                const SizedBox(width: 8),
                PremiumSection(
                  borderRadius: BorderRadius.circular(12),
                  width: 44,
                  height: 44,
                  useExpanded: false,
                  onTap: () =>
                      _showPlaylistOptions(context, ref, reactivePlaylist),
                  child: const Icon(
                    LucideIcons.moreHorizontal,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ] else if (reactiveAlbum != null) ...[
                const SizedBox(width: 8),
                PremiumSection(
                  borderRadius: BorderRadius.circular(12),
                  width: 44,
                  height: 44,
                  useExpanded: false,
                  onTap: () {
                    AppHaptics.light();
                    _showEditAlbumSheet(context, ref, reactiveAlbum);
                  },
                  child: const Icon(
                    LucideIcons.edit2,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ] else if (reactiveArtist != null) ...[
                const SizedBox(width: 8),
                PremiumSection(
                  borderRadius: BorderRadius.circular(12),
                  width: 44,
                  height: 44,
                  useExpanded: false,
                  onTap: () {
                    AppHaptics.light();
                    _showEditArtistSheet(context, reactiveArtist);
                  },
                  child: const Icon(
                    LucideIcons.edit2,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ];
            Widget row(Iterable<Widget> children) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(children: [...children]),
            );
            // Artist pages: play / shuffle / sort, then follow / explore /
            // edit on a second row so nothing runs off screen.
            if (!isArtist || buttons.length <= 6) return row(buttons);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row(buttons.take(5)),
                const SizedBox(height: 8),
                row(buttons.skip(6)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ArtistFollowButton extends ConsumerWidget {
  const _ArtistFollowButton({
    required this.artistName,
    this.thumbnail,
  });

  final String artistName;
  final String? thumbnail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final following = ref.watch(
      tasteProvider.select((t) => t.hasArtist(artistName)),
    );
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return PremiumSection(
      borderRadius: BorderRadius.circular(12),
      height: 44,
      useExpanded: false,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      backgroundColor: following
          ? primaryColor.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.08),
      onTap: () {
        AppHaptics.light();
        ref.read(tasteProvider.notifier).toggleArtist(
              TasteArtist(artistName, thumbnail: thumbnail),
            );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            following ? LucideIcons.check : LucideIcons.plus,
            size: 16,
            color: following ? primaryColor : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            following ? l10n.onlineFollowing : l10n.onlineFollow,
            style: AppFonts.jostStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: following ? primaryColor : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
