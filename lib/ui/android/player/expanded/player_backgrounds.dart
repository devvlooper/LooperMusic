import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/artwork/presentation/widgets/animated_artwork_widget.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/core/utils/responsive.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/player/player_gradient/animated_player_gradient.dart';
import 'player_landscape_layout.dart';

export 'package:looper_player/ui/android/shell/blurred_background_art.dart'
    show BlurredBackgroundArt;

/// The player's gradient background (Dynamic Theming off, Player Gradient
/// on), shared by the classic pushed player and the Fluid Player panel so
/// both look the same. The stops are pre-blended onto the surface, so it's
/// opaque on its own and bright at 0% Music Darkness: the old translucent
/// 5-20% primary tint over a dark surface stayed dark even with no overlay.
///
/// With [animated] (the Animated Gradient setting) it hands off to
/// AnimatedPlayerGradient instead; the static gradient below is unchanged.
class PlayerGradientBackground extends StatelessWidget {
  final double darkness;
  final bool animated;
  final bool followExpandProgress;
  const PlayerGradientBackground({
    required this.darkness,
    this.animated = false,
    this.followExpandProgress = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (animated) {
      return AnimatedPlayerGradient(
        darkness: darkness,
        followExpandProgress: followExpandProgress,
      );
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    Color tint(Color color, double alpha) =>
        Color.alphaBlend(color.withValues(alpha: alpha), scheme.surface);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.6,
              colors: [
                tint(scheme.primary, 0.55),
                tint(scheme.primary, 0.28),
                tint(scheme.primary, 0.14),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Music Darkness slider, same as the dynamic-art background.
        if (darkness > 0)
          ColoredBox(color: Colors.black.withValues(alpha: darkness)),
      ],
    );
  }
}

class ForegroundAlbumArt extends ConsumerWidget {
  final Song song;
  const ForegroundAlbumArt({required this.song, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double decodeWidth = Responsive.isLandscape(screenSize)
        ? PlayerLandscapeMetrics.of(
            screenSize,
            MediaQuery.paddingOf(context),
          ).artRect.width
        : screenSize.width;
    final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    final staticArt = AspectRatio(
      aspectRatio: 1.0,
      child: OptimizedImage(
        imagePath: song.artPath != null && !song.artPath!.startsWith('http')
            ? song.artPath
            : null,
        imageUrl: song.artPath != null && song.artPath!.startsWith('http')
            ? song.artPath
            : null,
        fit: BoxFit.cover,
        cacheWidth: (decodeWidth * dpr).toInt(),
      ),
    );

    final motionSettings = ref.watch(animatedArtworkSettingsProvider);
    final motionAsync = ref.watch(animatedArtworkForSongProvider(song));
    final mediaSource = motionAsync.asData?.value?.bestSquareMedia;

    final Widget artWidget;
    if (!motionSettings.isAlbumCoverAnimated('classic') ||
        motionSettings.mode == AnimatedArtworkMode.never) {
      artWidget = staticArt;
    } else {
      artWidget = AspectRatio(
        aspectRatio: 1.0,
        child: AnimatedArtworkWidget(
          mediaSource: mediaSource,
          staticFallback: staticArt,
          borderRadius: BorderRadius.circular(12),
          fit: BoxFit.cover,
        ),
      );
    }

    if (!motionSettings.ambientGlow) {
      return artWidget;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glowOpacity = isDark ? 0.55 : 0.35;

    final staticGlow = AspectRatio(
      aspectRatio: 1.0,
      child: OptimizedImage(
        imagePath: song.artPath != null && !song.artPath!.startsWith('http')
            ? song.artPath
            : null,
        imageUrl: song.artPath != null && song.artPath!.startsWith('http')
            ? song.artPath
            : null,
        fit: BoxFit.cover,
        cacheWidth: 64,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          top: -24,
          bottom: -24,
          left: -24,
          right: -24,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Opacity(
              opacity: glowOpacity,
              child: mediaSource != null
                  ? AnimatedArtworkWidget(
                      mediaSource: mediaSource,
                      staticFallback: staticGlow,
                      fit: BoxFit.cover,
                    )
                  : staticGlow,
            ),
          ),
        ),
        artWidget,
      ],
    );
  }
}

/// Immersive mode (portrait): the art edge to edge from the top of the
/// screen down to the title row, fading out over the lyric line and title
/// so the regular background shows below. Plays the song's motion art when
/// it has one.
class ImmersiveHeroArt extends ConsumerWidget {
  final Song song;

  /// Height of the fade at the bottom of the art.
  final double fadeHeight;
  const ImmersiveHeroArt({
    required this.song,
    required this.fadeHeight,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final String? art = song.artPath;
    final Widget staticArt = SizedBox.expand(
      child: OptimizedImage(
        imagePath: art != null && !art.startsWith('http') ? art : null,
        imageUrl: art != null && art.startsWith('http') ? art : null,
        fit: BoxFit.cover,
        cacheWidth: (MediaQuery.sizeOf(context).width * dpr).toInt(),
      ),
    );
    final motion = ref
        .watch(animatedArtworkForSongProvider(song))
        .asData
        ?.value;
    final String? source = motion != null && motion.hasMotion
        ? motion.bestTallMedia ?? motion.bestSquareMedia
        : null;

    return decorate(
      AnimatedArtworkWidget(
        mediaSource: source,
        staticFallback: staticArt,
        fit: BoxFit.cover,
      ),
      fadeHeight: fadeHeight,
    );
  }

  /// The immersive look over any art: the bottom fade of [fadeHeight] and a
  /// top shade (keeps the white top bar readable over bright art), the
  /// latter at [topShade] of its strength. Shared with the artwork Hero
  /// flight so the flight lands on exactly this picture.
  static Widget decorate(
    Widget art, {
    required double fadeHeight,
    double topShade = 1.0,
  }) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: [
          0.0,
          rect.height <= 0
              ? 0.0
              : (1 - fadeHeight / rect.height).clamp(0.0, 1.0),
          1.0,
        ],
      ).createShader(rect),
      child: Stack(
        fit: StackFit.expand,
        children: [
          art,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.5),
                colors: [
                  Colors.black.withValues(alpha: 0.45 * topShade),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
