part of 'premium_music_bar.dart';

extension _MiniPlayerContent on PremiumMusicBarState {
  /// One rounded glass bar: artwork, title and artist, a hairline divider,
  /// then play/pause and next. In the Fluid Player the panel behind draws
  /// the glass, so the bar itself is transparent there.
  Widget _buildMiniPlayerContent(
    Song song,
    bool isPlaying,
    bool useBlur,
    Color? cardBgColor,
    double cardBlurAmount,
    dynamic settings, {
    bool compact = false,
  }) {
    final bool fluid = settings.enableSlideGesture as bool;
    Widget buildHero({required String tag, required Widget child}) {
      if (fluid) return child;
      return Hero(tag: tag, child: child);
    }

    final double artSize = FluidPlayerGeometry.miniArtSize(compact: compact);
    final double artRadius = FluidPlayerGeometry.miniArtRadius(
      compact: compact,
    );
    final double iconSize = (compact ? 15.0 : 17.0).s;

    Widget control({
      required String label,
      required VoidCallback onTap,
      required Widget child,
    }) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.light();
            onTap();
          },
          child: Center(child: child),
        ),
      ),
    );

    return PremiumSection(
      useBlur: useBlur,
      forceTransparent: fluid,
      keepSurfaceOnDisableBlur: true,
      backgroundColor: cardBgColor ?? PremiumMusicBarState.barColor,
      blurAmount: cardBlurAmount,
      showBorder: false,
      useExpanded: false,
      useCenter: false,
      onTap: null, // Handled by parent GestureDetector
      borderRadius: BorderRadius.circular(FluidPlayerGeometry.panelRadius),
      child: Row(
        children: [
          SizedBox(width: FluidPlayerGeometry.miniArtLeft),
          SizedBox(
            width: artSize,
            height: artSize,
            // In the Fluid Player the morph layer draws the art here.
            child: fluid
                ? null
                : DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(artRadius),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(artRadius),
                      child: Hero(
                        tag: 'album_art',
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Mini player shows static art only (Doc 20 §2 bug A17)
                            OptimizedImage(
                              imagePath:
                                  song.artPath != null &&
                                      !song.artPath!.startsWith('http')
                                  ? song.artPath
                                  : null,
                              imageUrl:
                                  song.artPath != null &&
                                      song.artPath!.startsWith('http')
                                  ? song.artPath
                                  : null,
                              fit: BoxFit.cover,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildHero(
                  tag: 'song_title',
                  child: ScrollingText(
                    text: song.title,
                    style: AppFonts.jostStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: (compact ? 15.0 : 16.0).ts,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                buildHero(
                  tag: 'song_artist',
                  child: ScrollingText(
                    text: artistAlbumLabel(
                      song,
                      context.l10n,
                      showAlbum: settings.showAlbumNextToArtist as bool,
                    ),
                    style: AppFonts.jostStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: (compact ? 12.0 : 13.0).ts,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 14),
            color: Colors.white.withValues(alpha: 0.03),
          ),
          SizedBox(
            width: compact ? 96 : 104,
            child: Row(
              children: [
                control(
                  label: isPlaying ? context.l10n.pause : context.l10n.play,
                  onTap: () => ref.read(playbackProvider.notifier).togglePlay(),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final isBuffering = ref.watch(
                        playbackProvider.select((s) => s.isBuffering),
                      );
                      final icon = AnimatedPlayPauseIcon(
                        isPlaying: isPlaying,
                        color: Colors.white,
                        size: iconSize,
                      );
                      return buildHero(
                        tag: 'player_play_pause_btn',
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            icon,
                            if (isBuffering)
                              SizedBox.square(
                                dimension: iconSize + 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                control(
                  label: context.l10n.skipNext,
                  onTap: () => ref.read(playbackProvider.notifier).skipNext(),
                  child: SvgPicture.asset(
                    AppIcons.miniNext,
                    width: iconSize,
                    height: iconSize * 15 / 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
