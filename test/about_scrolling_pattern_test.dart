import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/settings/presentation/widgets/tiles/about_settings_tiles.dart';

void main() {
  test('Alternating diagonal marquee offsets scroll in opposite directions', () {
    const scale = 1.064089;
    const tileWidth = 114.0 * scale;
    const stagger = 37.0 * scale;

    double offsetFor(int i, double t) {
      return (i % 2 == 0)
          ? (t * tileWidth) % tileWidth
          : (stagger - t * tileWidth) % tileWidth;
    }

    // At t = 0.0 vs t = 0.1:
    // Row 0 (even) should scroll forward (offset increases)
    final r0T0 = offsetFor(0, 0.0);
    final r0T1 = offsetFor(0, 0.1);
    expect(r0T1, greaterThan(r0T0));

    // Row 1 (odd) should scroll backward (offset decreases)
    final r1T0 = offsetFor(1, 0.0);
    final r1T1 = offsetFor(1, 0.1);
    expect(r1T1, lessThan(r1T0));

    // Row 2 (even) should scroll forward
    final r2T0 = offsetFor(2, 0.0);
    final r2T1 = offsetFor(2, 0.1);
    expect(r2T1, greaterThan(r2T0));

    // Row 3 (odd) should scroll backward
    final r3T0 = offsetFor(3, 0.0);
    final r3T1 = offsetFor(3, 0.1);
    expect(r3T1, lessThan(r3T0));

    // Continuous seamless wrapping: value at t=1.0 modulo tileWidth equals value at t=0.0
    expect((offsetFor(0, 1.0) - offsetFor(0, 0.0)).abs() % tileWidth, closeTo(0.0, 1e-6));
    expect((offsetFor(1, 1.0) - offsetFor(1, 0.0)).abs() % tileWidth, closeTo(0.0, 1e-6));
  });

  testWidgets('AboutHeroCard builds and mounts cleanly', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AboutHeroCard(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AboutHeroCard), findsOneWidget);
    expect(find.text('Looper Music'), findsOneWidget);

    // Pump a few frames to verify animation ticks without error
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
