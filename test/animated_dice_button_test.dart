import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/android/widgets/animated_dice_button.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('AnimatedDiceButton triggers onTap on tap and shows icon', (tester) async {
    int tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedDiceButton(
              tooltip: 'Reshuffle',
              onTap: () {
                tapCount++;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.dices), findsOneWidget);

    await tester.tap(find.byType(AnimatedDiceButton));
    await tester.pump(); // animation start
    expect(tapCount, 1);

    await tester.pump(const Duration(milliseconds: 250)); // mid-animation
    await tester.tap(find.byType(AnimatedDiceButton)); // tap again while rolling
    await tester.pump();
    expect(tapCount, 2);

    await tester.pumpAndSettle();
    expect(tapCount, 2);
  });
}
