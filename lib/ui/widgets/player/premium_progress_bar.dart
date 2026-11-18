import 'package:flutter/material.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'squiggly_slider/slider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/features/settings/domain/progress_bar_style.dart';

class ExpressiveSlider extends ConsumerStatefulWidget {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;
  final Color color;
  final bool showTimestamps;
  final Duration? buffer;
  final bool isStreaming;

  /// Overrides the style from settings - used by the settings preview to
  /// show unsaved changes live.
  final ProgressBarStyle? style;

  const ExpressiveSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onSeek,
    this.onSeekStart,
    this.onSeekEnd,
    required this.color,
    this.showTimestamps = true,
    this.buffer,
    this.isStreaming = false,
    this.style,
  });

  @override
  ConsumerState<ExpressiveSlider> createState() => _ExpressiveSliderState();
}

class _ExpressiveSliderState extends ConsumerState<ExpressiveSlider> {
  double? _dragValue;

  String _formatDuration(Duration duration) {
    return UiUtils.formatPlaybackDuration(
      duration,
      showHours: widget.duration.inHours > 0,
    );
  }

  Widget _buildAnimatedDuration(String durationStr, bool isRightAligned) {
    final settings = ref.watch(settingsProvider);
    if (settings.disableAnimatedDuration) {
      return Text(
        durationStr,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isRightAligned
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: durationStr.characters.map((char) {
        return SizedBox(
          width: char == ':' ? 5 : 9,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              final isIn = (child as Text).data == char;
              // Digits roll through a clip: no fade, because a fading digit
              // is a GPU save-layer, and the clock changed every second -
              // most of the player screen's per-frame layers came from here.
              return ClipRect(
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0.0, isIn ? 1.0 : -1.0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              char,
              key: ValueKey(char),
              style: AppFonts.jostStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _onChanged(double val) {
    setState(() => _dragValue = val);
    widget.onSeek(widget.duration * val);
  }

  void _onChangeStart(double val) {
    setState(() => _dragValue = val);
    widget.onSeekStart?.call();
  }

  void _onChangeEnd(double val) {
    setState(() => _dragValue = null);
    widget.onSeekEnd?.call();
  }

  /// Flat for the first 12% of the song (the "wave from start" setting being
  /// off), then grows in over the next 6% instead of popping in at 12%.
  static double _startRamp(double progress) =>
      Curves.easeInOut.transform(((progress - 0.12) / 0.06).clamp(0.0, 1.0));

  Widget _buildStyledSlider(
    double displayValue,
    double? secondaryTrackValue,
    ProgressBarStyle style,
  ) {
    final bool showWave =
        style.wave && (widget.isPlaying || style.freezeWhenPaused);
    final double targetAmplitude = showWave
        ? style.waveHeight *
              (style.waveFromStart ? 1.0 : _startRamp(displayValue))
        : 0.0;
    final Color inactive = Colors.white.withValues(
      alpha: style.inactiveOpacity,
    );
    final Color secondaryColor = Colors.white.withValues(
      alpha: (style.inactiveOpacity * 2).clamp(0.0, 1.0),
    );
    final double thumbWidth = switch (style.thumbStyle) {
      ProgressThumbStyle.pill => style.thumbWidth,
      ProgressThumbStyle.round => style.thumbHeight,
      ProgressThumbStyle.none => 0,
    };
    final double thumbHeight = style.thumbStyle == ProgressThumbStyle.none
        ? 0
        : style.thumbHeight;

    // Fixed at the default bar's height (its 16dp thumb) whatever the style,
    // so thicker bars, taller thumbs or no thumb never move the player's
    // layout - bigger parts just paint past it (nothing up the tree clips).
    return SizedBox(
      height: ProgressBarStyle.defaultThumbHeight,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: style.thickness,
          activeTrackColor: widget.color,
          inactiveTrackColor: inactive,
          secondaryActiveTrackColor: secondaryColor,
          thumbShape: LineThumbShape(
            thumbHeight: thumbHeight,
            thumbWidth: thumbWidth,
            growOnDrag: style.growThumbOnDrag,
          ),
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: targetAmplitude),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          builder: (context, amplitude, child) {
            return SquigglySlider(
              value: displayValue,
              secondaryTrackValue: secondaryTrackValue,
              onChanged: _onChanged,
              onChangeStart: _onChangeStart,
              onChangeEnd: _onChangeEnd,
              activeColor: widget.color,
              inactiveColor: inactive,
              secondaryActiveColor: secondaryColor,
              squiggleAmplitude: amplitude,
              squiggleWavelength: style.squiggleWavelength,
              squiggleSpeed: style.waveSpeed,
              squiggleAnimating: widget.isPlaying,
              thumbGap: style.thumbGap,
              useLineThumb: false,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double progress = widget.duration.inMilliseconds > 0
        ? (widget.position.inMilliseconds / widget.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    final displayValue = _dragValue ?? progress;
    final displayPosition = _dragValue != null
        ? widget.duration * _dragValue!
        : widget.position;

    final double? secondaryTrackValue =
        widget.isStreaming &&
            widget.duration > Duration.zero &&
            widget.buffer != null
        ? (widget.buffer!.inMilliseconds / widget.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : null;

    final sliderWidget = _buildStyledSlider(
      displayValue,
      secondaryTrackValue,
      widget.style ??
          ref.watch(settingsProvider.select(ProgressBarStyle.fromSettings)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        sliderWidget,
        if (widget.showTimestamps) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAnimatedDuration(_formatDuration(displayPosition), false),
                _buildAnimatedDuration(_formatDuration(widget.duration), true),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class LineThumbShape extends SliderComponentShape {
  final double thumbHeight;
  final double thumbWidth;

  /// Grow the thumb a little while it's being dragged.
  final bool growOnDrag;

  const LineThumbShape({
    this.thumbHeight = 12,
    this.thumbWidth = 2,
    this.growOnDrag = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(thumbWidth, thumbHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (thumbWidth <= 0 || thumbHeight <= 0) return;
    final double grow = growOnDrag ? 1 + 0.35 * activationAnimation.value : 1;
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: thumbWidth * grow,
          height: thumbHeight * grow,
        ),
        Radius.circular(thumbWidth * grow / 2),
      ),
      paint,
    );
  }
}
