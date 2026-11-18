import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/android/shell/music_bar/fluid_player_motion.dart';

void main() {
  const Size phone = Size(400, 800);
  const FluidPlayerGeometry geometry = FluidPlayerGeometry(
    screenSize: phone,
    restingBottom: 118,
  );

  group('FluidPlayerGeometry', () {
    test('collapsed panel is the 72dp mini bar above the resting gap', () {
      expect(
        geometry.panelRect(0),
        const Rect.fromLTRB(16, 800 - 118 - 72, 384, 800 - 118),
      );
    });

    test('expanded panel is the whole screen', () {
      expect(geometry.panelRect(1), Offset.zero & phone);
    });

    test('matches the old host geometry at every progress', () {
      for (double p = 0; p <= 1.0001; p += 0.05) {
        final Rect r = geometry.panelRect(p);
        // Old host: bottom = restingBottom * (1 - p),
        // height = 72 + (H - 72) * p, side margin 16 * (1 - p).
        expect(phone.height - r.bottom, closeTo(118 * (1 - p), 1e-9));
        expect(r.height, closeTo(72 + (800 - 72) * p, 1e-9));
        expect(r.left, closeTo(16 * (1 - p), 1e-9));
      }
    });

    test('drag travel is the distance the panel top actually moves', () {
      expect(
        geometry.travel,
        geometry.panelRect(0).top - geometry.panelRect(1).top,
      );
      // A drag of `travel` pixels up moves the top edge exactly that far.
      final double p = 100 / geometry.travel;
      expect(
        geometry.panelRect(0).top - geometry.panelRect(p).top,
        closeTo(100, 1e-9),
      );
    });

    test('upward fling becomes positive progress velocity', () {
      expect(geometry.progressVelocity(-geometry.travel), closeTo(1.0, 1e-9));
    });

    test('morph art goes from the mini thumbnail to the expanded artwork', () {
      const Rect target = Rect.fromLTWH(20, 120, 360, 360);
      final Rect start = geometry.morphArtRect(0, target);
      expect(
        start,
        Rect.fromLTWH(16 + 12, geometry.panelRect(0).top + 11, 50, 50),
      );
      expect(geometry.morphArtRect(1, target), target);
    });

    test('morph art in compact mode is 40dp thumbnail with 26dp radius', () {
      const Rect target = Rect.fromLTWH(20, 120, 360, 360);
      final Rect start = geometry.morphArtRect(0, target, compact: true);
      expect(
        start,
        Rect.fromLTWH(16 + 12, geometry.panelRect(0).top + 8, 40, 40),
      );
      expect(FluidPlayerGeometry.morphArtRadius(0, compact: true), 26.0);
      expect(FluidPlayerGeometry.morphArtRadius(0, compact: false), 32.0);
      expect(FluidPlayerGeometry.morphArtRadius(1, compact: true), 12.0);
    });

    test('panel radius stays constant during flight and smoothly reaches 0 at full expansion', () {
      // In flight: corners do not change (fixed at 36)
      expect(FluidPlayerGeometry.panelRadiusAt(0.0), 36.0);
      expect(FluidPlayerGeometry.panelRadiusAt(0.3), 36.0);
      expect(FluidPlayerGeometry.panelRadiusAt(0.6), 36.0);
      expect(FluidPlayerGeometry.panelRadiusAt(0.9), 36.0);
      expect(FluidPlayerGeometry.panelRadiusAt(FluidPlayerGeometry.panelCornerProgressThreshold), 36.0);

      // Fully expanded: corners are 0 to seamlessly cover square displays
      expect(FluidPlayerGeometry.panelRadiusAt(1.0), 0.0);
      expect(FluidPlayerGeometry.panelRadiusAt(1.1), 0.0);

      // Small drag from 1.0: smoothly transitions from 0 to 36
      final double mid = FluidPlayerGeometry.panelRadiusAt(0.97);
      expect(mid, closeTo(18.0, 0.1));

      // Monotonic decreasing as p expands towards 1.0
      double lastRadius = 36.0;
      for (double p = 0.94; p <= 1.0; p += 0.005) {
        final double r = FluidPlayerGeometry.panelRadiusAt(p);
        expect(r, lessThanOrEqualTo(lastRadius));
        lastRadius = r;
      }
    });
  });

  group('FluidSectionMotion', () {
    const List<FluidSectionMotion> sections = [
      FluidSectionMotion.utilityRow,
      FluidSectionMotion.transportRow,
      FluidSectionMotion.seekBar,
      FluidSectionMotion.songInfo,
      FluidSectionMotion.topBar,
    ];

    test('every section is hidden and lowered when collapsed', () {
      for (final FluidSectionMotion s in sections) {
        expect(s.opacity(0), 0);
        expect(s.offsetY(0), FluidSectionMotion.distance);
      }
    });

    test('every section is fully in place when expanded', () {
      for (final FluidSectionMotion s in sections) {
        expect(s.opacity(1), 1);
        expect(s.offsetY(1), 0);
      }
    });

    test('motion is monotonic - no section ever steps backwards', () {
      for (final FluidSectionMotion s in sections) {
        double lastOpacity = -1;
        double lastOffset = double.infinity;
        for (int i = 0; i <= 1000; i++) {
          final double p = i / 1000;
          expect(s.opacity(p), greaterThanOrEqualTo(lastOpacity));
          expect(s.offsetY(p), lessThanOrEqualTo(lastOffset));
          lastOpacity = s.opacity(p);
          lastOffset = s.offsetY(p);
        }
      }
    });

    test('sections enter bottom-up', () {
      for (int i = 1; i < sections.length; i++) {
        expect(sections[i].start, greaterThan(sections[i - 1].start));
      }
    });

    test(
      'no per-frame jump larger than a few dp at 120Hz over a 400ms expand',
      () {
        // 48 frames; a linear progress sweep is the worst case for a section's
        // steepest point.
        for (final FluidSectionMotion s in sections) {
          for (int i = 1; i <= 48; i++) {
            final double a = s.offsetY((i - 1) / 48);
            final double b = s.offsetY(i / 48);
            expect((a - b).abs(), lessThan(10));
          }
        }
      },
    );

    test('background fill only fades', () {
      expect(FluidSectionMotion.backgroundFill.offsetY(0.3), 0);
      expect(FluidSectionMotion.backgroundFill.opacity(1), 1);
    });
  });

  test('settle spring is critically damped and lands exactly on target', () {
    final SpringSimulation sim = SpringSimulation(
      fluidPlayerSpring,
      0.6,
      1.0,
      2.0,
      snapToEnd: true,
    );
    expect(
      fluidPlayerSpring.damping,
      closeTo(
        2 * math.sqrt(fluidPlayerSpring.mass * fluidPlayerSpring.stiffness),
        1e-9,
      ),
    );
    double t = 0;
    while (!sim.isDone(t)) {
      t += 1 / 120;
      expect(t, lessThan(2.0), reason: 'spring should settle well within 2s');
    }
    expect(sim.x(t), 1.0);
  });

  group('rubber band', () {
    test('matches f(x) = x*d*0.55 / (d + 0.55*x)', () {
      for (final double x in [1.0, 10.0, 50.0, 200.0, 1000.0]) {
        expect(
          rubberBand(x, 96),
          closeTo(x * 96 * 0.55 / (96 + 0.55 * x), 1e-9),
        );
      }
      expect(rubberBand(0, 96), 0.0);
      expect(rubberBand(-5, 96), 0.0);
    });

    test('slope 0.55 at the edge, monotonic, bounded by d', () {
      expect(rubberBand(0.001, 96) / 0.001, closeTo(0.55, 1e-4));
      double last = 0;
      for (double x = 1; x < 100000; x *= 1.5) {
        final double y = rubberBand(x, 96);
        expect(y, greaterThan(last));
        expect(y, lessThan(96));
        last = y;
      }
    });

    test('inverse round-trips', () {
      for (final double x in [0.5, 5.0, 40.0, 300.0]) {
        expect(inverseRubberBand(rubberBand(x, 96), 96), closeTo(x, 1e-6));
      }
    });
  });

  group('stretch from physics position', () {
    test('inside 0..1 is plain progress, no stretch', () {
      expect(FluidPlayerGeometry.progressOf(0.5), 0.5);
      expect(geometry.stretchOf(0.5), 0.0);
      expect(geometry.stretchOf(0.0), 0.0);
      expect(geometry.stretchOf(1.0), 0.0);
    });

    test('past the ends clamps progress and stretches within max', () {
      expect(FluidPlayerGeometry.progressOf(1.4), 1.0);
      expect(FluidPlayerGeometry.progressOf(-0.3), 0.0);
      final double up = geometry.stretchOf(1.4);
      expect(up, greaterThan(0));
      expect(up, lessThan(geometry.stretchOpenMax));
      final double down = geometry.stretchOf(-0.3);
      expect(down, lessThan(0));
      expect(-down, lessThan(geometry.dismissTravel));
    });

    test('open-end stretch keeps the bottom, collapsed-end moves the rect', () {
      final Rect open = geometry.panelRect(1.0, stretch: 30);
      expect(open.top, -30);
      expect(open.bottom, phone.height);
      final Rect rest = geometry.panelRect(0.0);
      final Rect sunk = geometry.panelRect(0.0, stretch: -10);
      expect(sunk.top, rest.top + 10);
      expect(sunk.bottom, rest.bottom + 10);
      expect(sunk.height, rest.height);
    });
  });

  test('open/close bounce is visible on a tap; settle spring is dead', () {
    double peak(SpringDescription s, double from, double to, double v) {
      final sim = SpringSimulation(s, from, to, v);
      double m = to > from ? -1e9 : 1e9;
      for (double t = 0; t < 2; t += 0.005) {
        m = to > from ? math.max(m, sim.x(t)) : math.min(m, sim.x(t));
      }
      return m;
    }

    // Tap to open (no finger velocity) still overshoots noticeably.
    final double open = peak(fluidPlayerOpenBounceSpring, 0.0, 1.0, 0.0);
    expect(open - 1.0, greaterThan(0.05));
    expect(geometry.stretchOf(open), greaterThan(15.0));
    // A hard flick is still capped by the rubber band.
    final double flick = peak(fluidPlayerOpenBounceSpring, 0.6, 1.0, 8.0);
    expect(geometry.stretchOf(flick), lessThan(geometry.stretchOpenMax));
    // Minimizing dips the mini bar under rest, less than opening lifts.
    final double close = peak(fluidPlayerCloseBounceSpring, 1.0, 0.0, 0.0);
    expect(close, lessThan(-0.02));
    expect(-close, lessThan(open - 1.0));
    expect(
      peak(fluidPlayerSpring, 0.6, 1.0, 6.0),
      lessThanOrEqualTo(1.0 + 1e-9),
    );
  });

  group('FluidHorizontalSwipe', () {
    test('linear offset when not blocked', () {
      expect(
        FluidHorizontalSwipe.computeOffset(
          fingerDx: 50.0,
          isBlocked: false,
          limit: 100.0,
        ),
        50.0,
      );
      expect(
        FluidHorizontalSwipe.computeOffset(
          fingerDx: -50.0,
          isBlocked: false,
          limit: 100.0,
        ),
        -50.0,
      );
    });

    test('rubber-bands offset when blocked at queue boundary', () {
      final double positiveBlocked = FluidHorizontalSwipe.computeOffset(
        fingerDx: 80.0,
        isBlocked: true,
        limit: 100.0,
      );
      expect(positiveBlocked, lessThan(80.0));
      expect(positiveBlocked, greaterThan(0.0));

      final double negativeBlocked = FluidHorizontalSwipe.computeOffset(
        fingerDx: -80.0,
        isBlocked: true,
        limit: 100.0,
      );
      expect(negativeBlocked, greaterThan(-80.0));
      expect(negativeBlocked, lessThan(0.0));
    });

    test('projects offset using velocity', () {
      expect(
        FluidHorizontalSwipe.projectedOffset(offset: 20.0, velocityX: 200.0),
        closeTo(20.0 + 200.0 * 0.15, 1e-6),
      );
      expect(
        FluidHorizontalSwipe.projectedOffset(offset: -20.0, velocityX: -200.0),
        closeTo(-20.0 - 200.0 * 0.15, 1e-6),
      );
    });

    test('threshold calculates max of minThreshold and fraction', () {
      expect(FluidHorizontalSwipe.threshold(200.0), 60.0);
      expect(FluidHorizontalSwipe.threshold(400.0), 100.0);
    });

    test('shouldCommit correctly detects threshold crossing', () {
      expect(
        FluidHorizontalSwipe.shouldCommit(
          projectedOffset: 65.0,
          threshold: 60.0,
        ),
        isTrue,
      );
      expect(
        FluidHorizontalSwipe.shouldCommit(
          projectedOffset: -65.0,
          threshold: 60.0,
        ),
        isTrue,
      );
      expect(
        FluidHorizontalSwipe.shouldCommit(
          projectedOffset: 40.0,
          threshold: 60.0,
        ),
        isFalse,
      );
    });
  });

  group('FluidPlayerGeometry.panelRect horizontalOffset', () {
    test('shifts panel horizontally when collapsed (p = 0)', () {
      final Rect normal = geometry.panelRect(0.0);
      final Rect shifted = geometry.panelRect(0.0, horizontalOffset: 25.0);
      expect(shifted.left, normal.left + 25.0);
      expect(shifted.right, normal.right + 25.0);
      expect(shifted.top, normal.top);
      expect(shifted.bottom, normal.bottom);
    });
  });
}
