import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/core/providers/player_expand_provider.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/player/expanded/android_expanded_player.dart';
import 'package:looper_player/ui/android/shell/music_bar/premium_music_bar.dart';

import 'package:looper_player/ui/widgets/common/optimized_image.dart';

class _FakeSettings extends Settings {
  final String playerStyle;
  _FakeSettings({this.playerStyle = 'classic'});

  @override
  AppSettings build() => AppSettings()
    ..enableSlideGesture = true
    ..playerStyle = playerStyle;
}

class _FakePlayback extends Playback {
  _FakePlayback(this.initialState);
  final PlaybackState initialState;
  final List<String> calls = [];

  @override
  PlaybackState build() => initialState;

  @override
  Future<void> skipNext({bool isManual = true}) async {
    calls.add('skipNext');
  }

  @override
  Future<void> skipPrevious({bool force = false}) async {
    calls.add('skipPrevious:$force');
  }

  @override
  Future<void> togglePlay() async {
    calls.add('togglePlay');
  }

  @override
  Future<void> clearQueue() async {
    calls.add('clearQueue');
  }
}

Song _testSong(String id, String title) => Song()
  ..path = id
  ..title = title
  ..artist = 'Artist'
  ..album = 'Album'
  ..duration = 180;

void main() {
  testWidgets('horizontal drag on mini bar does not expand the player', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final s2 = _testSong('2', 'Song 2');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s1,
        queue: [s1, s2],
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barFinder = find.byKey(const ValueKey('music_bar'));
    expect(barFinder, findsOneWidget);

    final titleFinder = find.text('Song 1');
    expect(titleFinder, findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(barFinder));
    expect(container.read(playerExpandProgressProvider).value, closeTo(0.0, 1e-4));

    // Diagonal drag that is mostly horizontal (dx: -100, dy: -30).
    // Without directional locking, dy: -30 moves _dragController and expands the player.
    // With directional locking, it locks horizontal and keeps expand progress at 0.0.
    await tester.drag(titleFinder, const Offset(-100, -30));
    await tester.pump();
    expect(container.read(playerExpandProgressProvider).value, closeTo(0.0, 1e-4));

    await tester.pumpAndSettle();
  });

  testWidgets('swiping left past threshold on mini bar triggers skipNext', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final s2 = _testSong('2', 'Song 2');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s1,
        queue: [s1, s2],
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Song 1');
    expect(titleFinder, findsOneWidget);

    // Fling left past threshold (-120px)
    await tester.fling(titleFinder, const Offset(-120, 0), 800.0);
    await tester.pumpAndSettle();

    expect(playback.calls, contains('skipNext'));
  });

  testWidgets('swiping right past threshold on mini bar triggers skipPrevious', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final s2 = _testSong('2', 'Song 2');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s2,
        queue: [s1, s2],
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Song 2');
    expect(titleFinder, findsOneWidget);

    // Fling right past threshold (+120px)
    await tester.fling(titleFinder, const Offset(120, 0), 800.0);
    await tester.pumpAndSettle();

    expect(playback.calls, contains('skipPrevious:true'));
  });

  testWidgets('swiping below threshold springs back without skipping', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final s2 = _testSong('2', 'Song 2');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s1,
        queue: [s1, s2],
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Song 1');
    expect(titleFinder, findsOneWidget);

    // Small drag below threshold without velocity
    final gesture = await tester.startGesture(tester.getCenter(titleFinder));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(playback.calls, isEmpty);
    final barState = tester.state<PremiumMusicBarState>(find.byKey(const ValueKey('music_bar')));
    expect(barState.miniHorizontalOffset, closeTo(0.0, 1e-4));
  });

  testWidgets('swiping left when at end of queue rubber-bands and does not skip', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s1,
        queue: [s1], // only 1 song in queue
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Song 1');
    await tester.fling(titleFinder, const Offset(-150, 0), 1000.0);
    await tester.pumpAndSettle();

    expect(playback.calls, isEmpty);
    final barState = tester.state<PremiumMusicBarState>(find.byKey(const ValueKey('music_bar')));
    expect(barState.miniHorizontalOffset, closeTo(0.0, 1e-4));
  });

  testWidgets('horizontal swipe on expanded fluid player skips track without collapsing', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final s2 = _testSong('2', 'Song 2');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s1,
        queue: [s1, s2],
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barFinder = find.byKey(const ValueKey('music_bar'));
    final barState = tester.state<PremiumMusicBarState>(barFinder);
    barState.expandForTesting();
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(barFinder));
    expect(container.read(playerExpandProgressProvider).value, closeTo(1.0, 1e-4));

    // Fling horizontally across the screen
    await tester.fling(barFinder, const Offset(-150, 0), 800.0);
    await tester.pumpAndSettle();

    expect(playback.calls, contains('skipNext'));
    expect(container.read(playerExpandProgressProvider).value, closeTo(1.0, 1e-4));
  });

  testWidgets('reduced motion triggers skip immediately without spring translation', (tester) async {
    final s1 = _testSong('1', 'Song 1');
    final s2 = _testSong('2', 'Song 2');
    final playback = _FakePlayback(
      PlaybackState(
        currentSong: s1,
        queue: [s1, s2],
        isPlaying: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          playbackProvider.overrideWith(() => playback),
          currentSongAnalysisProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(
            body: Stack(
              children: [
                PremiumMusicBar(key: ValueKey('music_bar')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Song 1');
    await tester.fling(titleFinder, const Offset(-120, 0), 800.0);
    // Instant pump without waiting for spring animation
    await tester.pump();

    expect(playback.calls, contains('skipNext'));
  });

  for (final style in ['card', 'arc', 'linear']) {
    testWidgets('style $style: horizontal swipe outside artwork does NOT skip song', (tester) async {
      final s1 = _testSong('1', 'Song 1');
      final s2 = _testSong('2', 'Song 2');
      final playback = _FakePlayback(
        PlaybackState(
          currentSong: s1,
          queue: [s1, s2],
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettings(playerStyle: style)),
            playbackProvider.overrideWith(() => playback),
            currentSongAnalysisProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: Stack(
                children: [
                  PremiumMusicBar(key: ValueKey('music_bar')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final barFinder = find.byKey(const ValueKey('music_bar'));
      final barState = tester.state<PremiumMusicBarState>(barFinder);
      barState.expandForTesting();
      await tester.pumpAndSettle();

      // Swipe on the title area (outside artwork)
      final titleFinder = find.text('Song 1');
      expect(titleFinder, findsOneWidget);
      await tester.fling(titleFinder, const Offset(-150, 0), 800.0);
      await tester.pumpAndSettle();

      expect(playback.calls, isEmpty);
    });

    testWidgets('style $style: horizontal swipe on artwork skips song', (tester) async {
      final s1 = _testSong('1', 'Song 1');
      final s2 = _testSong('2', 'Song 2');
      final playback = _FakePlayback(
        PlaybackState(
          currentSong: s1,
          queue: [s1, s2],
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettings(playerStyle: style)),
            playbackProvider.overrideWith(() => playback),
            currentSongAnalysisProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: Stack(
                children: [
                  PremiumMusicBar(key: ValueKey('music_bar')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final barFinder = find.byKey(const ValueKey('music_bar'));
      final barState = tester.state<PremiumMusicBarState>(barFinder);
      barState.expandForTesting();
      await tester.pumpAndSettle();

      final artFinder = find.byType(OptimizedImage);
      expect(artFinder, findsOneWidget);
      await tester.fling(artFinder, const Offset(-150, 0), 800.0);
      await tester.pumpAndSettle();

      expect(playback.calls, contains('skipNext'));
    });
  }
}
