import 'dart:ui' show Offset, Rect, Size, lerpDouble;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/physics.dart' show SpringDescription;
import 'package:looper_player/core/motion/rubber_band.dart';

export 'package:looper_player/core/motion/rubber_band.dart';

/// Geometry and motion of the Fluid Player (the slide-to-expand player), as
/// pure functions of the expand progress `p` (0 = mini bar, 1 = full player)
/// so the per-frame values can be unit-tested without the audio backend.
///
/// Everything is in the coordinates of the full-screen layer that hosts the
/// player. The panel (background and rounded clip) grows from the mini bar's
/// rect to the whole screen; the player's content stays pinned to the screen
/// and only eases in over a short distance ([FluidSectionMotion]) rather than
/// riding the panel's top edge up the whole screen.
/// Progress at which the morphing art hands over to the real artwork (and
/// the mini-bar layers leave). The panel's top edge travels ~1700 px, so at
/// the old 0.99 the morph was still ~17 px short and 1 % small and the real
/// art snapped into place; at 0.999 the gap is under 2 px. Settling springs
/// land exactly on 1.0, so the handoff always happens.
const double kFluidHandoff = 0.999;

class FluidPlayerGeometry {
  const FluidPlayerGeometry({
    required this.screenSize,
    required this.restingBottom,
  });

  /// Size of the full-screen host layer.
  final Size screenSize;

  /// Gap between the collapsed mini bar and the bottom of the screen (clears
  /// the navbar at a tab root, or just the system inset elsewhere).
  final double restingBottom;

  static const double miniHeight = 66.0;
  static const double miniMargin = 15.0;
  static const double panelRadius = 15.0;

  /// The mini bar's artwork thumbnail, shared by the bar itself and the
  /// morph that flies it into the expanded player. Compact is the 56dp bar
  /// on short (landscape) windows.
  static const double miniArtLeft = 11.0;
  static double miniArtSize({bool compact = false}) => compact ? 40.0 : 47.0;
  static double miniArtTop({bool compact = false}) => compact ? 8.0 : 9.5;
  static double miniArtRadius({bool compact = false}) => compact ? 7.0 : 8.0;

  /// Progress threshold where the panel corners begin smoothing from [panelRadius]
  /// down to 0 at full expansion. During flight (p <= 0.94), corners remain constant
  /// at 36dp.
  static const double panelCornerProgressThreshold = 0.94;

  /// Corner radius of the player panel as a function of expand progress [p]:
  /// constant [panelRadius] (36) throughout flight (p <= 0.94), transitioning
  /// smoothly via an easeInOut curve to 0 at full expansion (p = 1.0) so square-corner
  /// devices have seamless edge-to-edge coverage while any small drag restores
  /// the rounded floating card appearance.
  static double panelRadiusAt(double p) {
    if (p <= panelCornerProgressThreshold) return panelRadius;
    if (p >= 1.0) return 0.0;
    final double t =
        (p - panelCornerProgressThreshold) /
        (1.0 - panelCornerProgressThreshold);
    final double curved = Curves.easeInOut.transform(t);
    return lerpDouble(panelRadius, 0.0, curved)!;
  }

  /// Width the mini content is laid out at. Fixed (the collapsed panel's
  /// width) so a moving panel never re-lays it out.
  double get miniWidth => screenSize.width - 2 * miniMargin;

  /// Top of the collapsed panel.
  double get collapsedTop => screenSize.height - restingBottom - miniHeight;

  /// How far the panel's top edge travels from collapsed to expanded. Drag
  /// deltas are divided by this (not the screen height) so the edge stays
  /// under the finger.
  double get travel => collapsedTop > 1.0 ? collapsedTop : 1.0;

  /// Most the fully open panel can lift when pulled past the open end.
  double get stretchOpenMax => screenSize.height * 0.12;

  /// How far the collapsed mini bar travels to leave the screen. Pushing it
  /// down follows the finger with rubber-band resistance toward this (the
  /// drag-down dismiss); a dismiss animates the rest of the way.
  double get dismissTravel => restingBottom + miniHeight + 24.0;

  /// Visible progress (0..1) for an unclamped physics position [r].
  static double progressOf(double r) => r.clamp(0.0, 1.0).toDouble();

  /// Signed stretch in px for an unclamped physics position [r]: positive
  /// lifts the open panel, negative sinks the collapsed one. `r` beyond an
  /// end is the finger's (or spring's) overshoot in progress units; it is
  /// turned into px and damped through [rubberBand], so it never exceeds the
  /// end's max.
  double stretchOf(double r) {
    if (r > 1.0) return rubberBand((r - 1.0) * travel, stretchOpenMax);
    if (r < 0.0) return -rubberBand(-r * travel, dismissTravel);
    return 0.0;
  }

  /// [stretch] > 0 (open end) raises the top edge and keeps the bottom on
  /// the screen edge; [stretch] < 0 (collapsed end) moves the whole rect down.
  /// [horizontalOffset] shifts the collapsed mini panel sideways during swipe gestures.
  Rect panelRect(
    double p, {
    double stretch = 0.0,
    double horizontalOffset = 0.0,
  }) {
    final double margin = miniMargin * (1.0 - p);
    double top = collapsedTop * (1.0 - p);
    double bottom = screenSize.height - restingBottom * (1.0 - p);
    if (stretch > 0) {
      top -= stretch;
    } else if (stretch < 0) {
      top -= stretch;
      bottom -= stretch;
    }
    final double left = margin + horizontalOffset;
    final double right = screenSize.width - margin + horizontalOffset;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Converts a vertical pointer velocity (px/s, down positive) into
  /// progress units per second (expanding positive).
  double progressVelocity(double pixelsPerSecondDy) =>
      -pixelsPerSecondDy / travel;

  /// Rect of the morphing album art: from the mini bar's thumbnail
  /// (riding the panel) to the expanded player's artwork rect.
  Rect morphArtRect(
    double p,
    Rect expandedArt, {
    double stretch = 0.0,
    double horizontalOffset = 0.0,
    bool compact = false,
  }) {
    final Rect panel = panelRect(
      p,
      stretch: stretch,
      horizontalOffset: horizontalOffset,
    );
    final double miniSize = miniArtSize(compact: compact);
    final double miniTop = miniArtTop(compact: compact);
    final double size = lerpDouble(miniSize, expandedArt.width, p)!;
    final double left =
        panel.left + miniArtLeft + (expandedArt.left - miniArtLeft) * p;
    final double top = panel.top + miniTop + (expandedArt.top - miniTop) * p;
    return Rect.fromLTWH(left, top, size, size);
  }

  /// Corner radius of the morphing art: the mini thumbnail's 32 (or 26 compact)
  /// to the expanded artwork's 12.
  static double morphArtRadius(double p, {bool compact = false}) =>
      lerpDouble(miniArtRadius(compact: compact), 12.0, p)!;

  Offset miniOrigin(
    double p, {
    double stretch = 0.0,
    double horizontalOffset = 0.0,
  }) => panelRect(
    p,
    stretch: stretch,
    horizontalOffset: horizontalOffset,
  ).topLeft;
}

/// Staggered entrance of one expanded-player section: it fades in and rises
/// [distance] into place over its own [start]..[end] slice of the progress.
/// Collapsing plays the same mapping backwards, so sections leave in reverse.
class FluidSectionMotion {
  const FluidSectionMotion(this.start, this.end, {this.slide = true});

  final double start;
  final double end;

  /// False for layers that should only fade (e.g. a background fill).
  final bool slide;

  static const double distance = 48.0;
  static const Curve curve = Curves.easeOutCubic;

  // Bottom-up, following the panel as it grows upward and uncovers the lower
  // controls first. Every section is fully in place well before p = 1.
  static const FluidSectionMotion utilityRow = FluidSectionMotion(0.30, 0.75);
  static const FluidSectionMotion transportRow = FluidSectionMotion(0.35, 0.80);
  static const FluidSectionMotion seekBar = FluidSectionMotion(0.40, 0.85);
  static const FluidSectionMotion songInfo = FluidSectionMotion(0.45, 0.90);
  static const FluidSectionMotion topBar = FluidSectionMotion(0.55, 1.0);
  static const FluidSectionMotion backgroundFill = FluidSectionMotion(
    0.0,
    1.0,
    slide: false,
  );

  double _t(double p) =>
      curve.transform(((p - start) / (end - start)).clamp(0.0, 1.0).toDouble());

  double opacity(double p) => _t(p);

  double offsetY(double p) => slide ? (1.0 - _t(p)) * distance : 0.0;
}

/// Blur Music Bar during the open/close: a full-screen backdrop blur halves
/// the frame rate, so it hands over to the opaque player background within
/// the first [end] of the motion and the rest runs without it.
abstract final class FluidBarBlur {
  static const double end = 0.15;

  static double _t(double p) =>
      Curves.easeInOut.transform((p / end).clamp(0.0, 1.0).toDouble());

  static double amount(double p) => 1.0 - _t(p);

  static double backgroundOpacity(double p) => _t(p);
}

/// Soft spring for every open: the sheet glides up and lands with no visible
/// carry past the top on a tap. A hard flick can still lift it a little,
/// which the rubber band caps.
final SpringDescription fluidPlayerOpenBounceSpring =
    SpringDescription.withDampingRatio(mass: 1.0, stiffness: 200.0, ratio: 0.9);

/// Tap on the mini bar to open: the same glide, a touch more damped.
final SpringDescription fluidPlayerTapOpenSpring =
    SpringDescription.withDampingRatio(
      mass: 1.0,
      stiffness: 200.0,
      ratio: 0.94,
    );

/// Minimizing: glides back down into the mini bar's resting spot.
final SpringDescription fluidPlayerCloseBounceSpring =
    SpringDescription.withDampingRatio(
      mass: 1.0,
      stiffness: 220.0,
      ratio: 0.92,
    );

/// Critically damped settle (no bounce): releases from inside a stretch,
/// catches let go without a drag, and reduced motion. Started with the
/// finger's velocity so letting go never jumps in speed.
final SpringDescription fluidPlayerSpring = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 380.0,
  ratio: 1.0,
);

/// Pure calculation helper for horizontal swipe gesture physics and commit
/// thresholds in Fluid Player.
class FluidHorizontalSwipe {
  static const double commitThresholdFraction = 0.25;
  static const double commitThresholdMin = 60.0;
  static const double projectionTime = 0.15;

  /// Returns drag displacement, dampening through [rubberBand] if the drag is
  /// blocked at a boundary (start or end of queue).
  static double computeOffset({
    required double fingerDx,
    required bool isBlocked,
    required double limit,
  }) {
    if (!isBlocked) return fingerDx;
    if (fingerDx == 0.0) return 0.0;
    return fingerDx.sign * rubberBand(fingerDx.abs(), limit);
  }

  /// Projects final offset from [offset] and pointer [velocityX] (px/s).
  static double projectedOffset({
    required double offset,
    required double velocityX,
    double projectionTime = projectionTime,
  }) {
    return offset + velocityX * projectionTime;
  }

  /// Minimum horizontal travel required to trigger a track skip.
  static double threshold(double containerWidth) {
    final double fraction = containerWidth * commitThresholdFraction;
    return fraction > commitThresholdMin ? fraction : commitThresholdMin;
  }

  /// Whether the swipe throw or drag has crossed the commit threshold.
  static bool shouldCommit({
    required double projectedOffset,
    required double threshold,
  }) {
    return projectedOffset.abs() >= threshold;
  }
}
