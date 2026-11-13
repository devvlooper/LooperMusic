import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/ui/android/widgets/library_skeletons.dart';
import 'package:looper_player/ui/widgets/common/app_skeleton.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Home Skeletons (Online and Offline matching)', () {
    testWidgets('OnlineCardSkeleton builds matching standard card dimensions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSkeleton(
              child: OnlineCardSkeleton(round: false),
            ),
          ),
        ),
      );

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).toList();
      final cardBox = sizedBoxes.firstWhere((s) => s.width == 140);
      expect(cardBox.width, equals(140));
      expect(find.byType(OnlineCardSkeleton), findsOneWidget);
    });

    testWidgets('OfflineCardRowSkeleton builds matching album card dimensions (120x120)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSkeleton(
              child: OfflineCardRowSkeleton(circle: false),
            ),
          ),
        ),
      );

      final cardContainers = tester.widgetList<Container>(find.byType(Container)).toList();
      final albumCards = cardContainers.where((c) => (c.constraints?.minWidth ?? 0) == 120 || (c.constraints?.maxWidth ?? 0) == 120);
      expect(albumCards.isNotEmpty, isTrue);
    });

    testWidgets('HomeSkeleton selects OnlineHomeSkeleton when onlineActive is true',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineActiveProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: HomeSkeleton(),
            ),
          ),
        ),
      );

      expect(find.byType(OnlineHomeSkeleton), findsOneWidget);
      expect(find.byType(OfflineHomeSkeleton), findsNothing);
      expect(find.byType(OnlineMoodChipsSkeleton), findsOneWidget);
    });

    testWidgets('HomeSkeleton selects OfflineHomeSkeleton when onlineActive is false',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineActiveProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: HomeSkeleton(),
            ),
          ),
        ),
      );

      expect(find.byType(OfflineHomeSkeleton), findsOneWidget);
      expect(find.byType(OnlineHomeSkeleton), findsNothing);
      expect(find.byType(OnlineMoodChipsSkeleton), findsNothing);
    });
  });
}
