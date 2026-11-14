import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/widgets/animated_dice_button.dart';
import 'package:looper_player/ui/android/widgets/queue_bottom_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Song _song(String path, String title, String artist) => Song()
  ..id = path.hashCode
  ..path = path
  ..title = title
  ..artist = artist;

class _FakeSettings extends Settings {
  _FakeSettings({
    this.alwaysBlurSheets = false,
    this.enableDynamicTheming = false,
    this.disableBlur = true,
  });

  final bool alwaysBlurSheets;
  final bool enableDynamicTheming;
  final bool disableBlur;

  @override
  AppSettings build() => AppSettings()
    ..alwaysBlurSheets = alwaysBlurSheets
    ..enableDynamicTheming = enableDynamicTheming
    ..disableBlur = disableBlur
    ..darkTheme = true
    ..accentColor = Colors.red.value;
}

class _FakePlayback extends Playback {
  _FakePlayback(this.initialQueue, {this.initialIndex = 0});
  final List<Song> initialQueue;
  final int initialIndex;

  final List<String> calls = [];

  @override
  PlaybackState build() {
    return PlaybackState(
      currentSong: initialQueue.isNotEmpty ? initialQueue[initialIndex] : null,
      queue: List.unmodifiable(initialQueue),
      isPlaying: true,
    );
  }

  @override
  Future<void> shuffleUpcomingQueue({String? rotationSongPath}) async {
    calls.add('shuffleUpcomingQueue');
  }

  @override
  Future<void> removeFromQueue(int index) async {
    calls.add('removeFromQueue:$index');
  }

  @override
  Future<void> togglePlay() async {
    calls.add('togglePlay');
  }
}

void main() {
  testWidgets('QueueBottomSheet renders pinned continuation card, dice button, and reorder toggle', (tester) async {
    final songs = [
      _song('/s0.mp3', 'Current Song', 'Current Artist'),
      _song('/s1.mp3', 'Upcoming 1', 'Artist 1'),
      _song('/s2.mp3', 'Upcoming 2', 'Artist 2'),
    ];
    final fakePlayback = _FakePlayback(songs, initialIndex: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettings(alwaysBlurSheets: false, enableDynamicTheming: false),
          ),
          playbackProvider.overrideWith(() => fakePlayback),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QueueBottomSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 0. When alwaysBlurSheets is false, BackdropFilter must NOT be rendered (no background blur)
    expect(find.byType(BackdropFilter), findsNothing);

    // 1. Pinned continuation card shows current song and play/pause toggle
    expect(find.text('Current Song'), findsOneWidget);
    expect(find.text('Current Artist'), findsOneWidget);
    final pauseFinder = find.byIcon(LucideIcons.pause);
    expect(pauseFinder, findsOneWidget);
    await tester.tap(pauseFinder);
    await tester.pump();
    expect(fakePlayback.calls, contains('togglePlay'));

    // 2. Animated dice button exists and tapping it invokes shuffleUpcomingQueue
    expect(find.byType(AnimatedDiceButton), findsOneWidget);
    await tester.tap(find.byType(AnimatedDiceButton));
    await tester.pump();
    expect(fakePlayback.calls, contains('shuffleUpcomingQueue'));

    // 3. Upcoming songs are visible
    expect(find.text('Upcoming 1'), findsOneWidget);
    expect(find.text('Upcoming 2'), findsOneWidget);

    // 4. Default mode shows 3-dots menu icon and no drag handles
    expect(find.byIcon(LucideIcons.ellipsisVertical), findsWidgets);
    expect(find.byIcon(LucideIcons.gripVertical), findsNothing);

    // 5. Tapping Reorder toggle reveals drag handles
    final reorderFinder = find.byKey(const ValueKey('queue_reorder_toggle'));
    expect(reorderFinder, findsOneWidget);
    await tester.tap(reorderFinder);
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.gripVertical), findsWidgets);

    // 6. Horizontal swipe to dismiss removes song
    await tester.drag(find.text('Upcoming 1'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(fakePlayback.calls, contains('removeFromQueue:1'));
  });

  testWidgets('QueueBottomSheet applies BackdropFilter blur when alwaysBlurSheets is true (dynamicTheming off)', (tester) async {
    final songs = [
      _song('/s0.mp3', 'Current Song', 'Current Artist'),
      _song('/s1.mp3', 'Upcoming 1', 'Artist 1'),
    ];
    final fakePlayback = _FakePlayback(songs, initialIndex: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettings(alwaysBlurSheets: true, enableDynamicTheming: false),
          ),
          playbackProvider.overrideWith(() => fakePlayback),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QueueBottomSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // When alwaysBlurSheets is true, BackdropFilter is applied to blur the background
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('QueueBottomSheet does not blur when dynamicTheming is true and disableBlur is true', (tester) async {
    final songs = [
      _song('/s0.mp3', 'Current Song', 'Current Artist'),
      _song('/s1.mp3', 'Upcoming 1', 'Artist 1'),
    ];
    final fakePlayback = _FakePlayback(songs, initialIndex: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettings(
              enableDynamicTheming: true,
              disableBlur: true,
              alwaysBlurSheets: true, // even if alwaysBlurSheets was left true
            ),
          ),
          playbackProvider.overrideWith(() => fakePlayback),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QueueBottomSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // When dynamicTheming is on and disableBlur is true, BackdropFilter must NOT be rendered
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('QueueBottomSheet blurs when dynamicTheming is true and disableBlur is false', (tester) async {
    final songs = [
      _song('/s0.mp3', 'Current Song', 'Current Artist'),
      _song('/s1.mp3', 'Upcoming 1', 'Artist 1'),
    ];
    final fakePlayback = _FakePlayback(songs, initialIndex: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettings(
              enableDynamicTheming: true,
              disableBlur: false,
              alwaysBlurSheets: false, // even if alwaysBlurSheets was left false
            ),
          ),
          playbackProvider.overrideWith(() => fakePlayback),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QueueBottomSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // When dynamicTheming is on and disableBlur is false, BackdropFilter is applied
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}
