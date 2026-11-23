import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/core/services/screen_awake.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/playback/domain/lyric_models.dart';
import 'package:looper_player/features/playback/presentation/providers/lyrics/lyrics_notifier.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/player/expanded/android_expanded_player.dart';
import 'package:looper_player/ui/android/player/expanded/styled_player_layout.dart';
import 'package:looper_player/ui/android/player/lyrics/android_lyrics_screen.dart';

class _FakeSettings extends Settings {
  final AppSettings _initial;
  _FakeSettings([AppSettings? initial]) : _initial = initial ?? AppSettings() {
    initialization = Future.value();
  }

  @override
  AppSettings build() => _initial;
}

class _FakePlayback extends Playback {
  final PlaybackState _state;
  _FakePlayback([PlaybackState? state]) : _state = state ?? PlaybackState();

  @override
  PlaybackState build() => _state;
}

class _FakeLyrics extends Lyrics {
  final LyricsState _state;
  _FakeLyrics([LyricsState? state]) : _state = state ?? LyricsState();

  @override
  LyricsState build() => _state;
}

Song _mockSong() => Song()
  ..id = 1
  ..title = 'Awake Test Song'
  ..artist = 'Awake Test Artist'
  ..album = 'Awake Test Album'
  ..duration = 180000
  ..path = '/music/test.mp3';

Widget _wrapApp({
  required Widget child,
  AppSettings? settings,
  PlaybackState? playbackState,
  LyricsState? lyricsState,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettings(settings)),
      playbackProvider.overrideWith(() => _FakePlayback(playbackState)),
      lyricsProvider.overrideWith(() => _FakeLyrics(lyricsState)),
      currentSongAnalysisProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    ScreenAwake.resetForTesting();
  });

  tearDown(() {
    ScreenAwake.resetForTesting();
  });

  group('ScreenAwake service', () {
    test('activates and deactivates reference-counted holders correctly', () {
      final holderA = Object();
      final holderB = Object();

      expect(ScreenAwake.isActive, isFalse);

      ScreenAwake.set(holderA, true);
      expect(ScreenAwake.isActive, isTrue);
      expect(ScreenAwake.holds(holderA), isTrue);
      expect(ScreenAwake.holds(holderB), isFalse);

      ScreenAwake.set(holderB, true);
      expect(ScreenAwake.isActive, isTrue);
      expect(ScreenAwake.holds(holderA), isTrue);
      expect(ScreenAwake.holds(holderB), isTrue);

      ScreenAwake.set(holderA, false);
      expect(ScreenAwake.isActive, isTrue);
      expect(ScreenAwake.holds(holderA), isFalse);
      expect(ScreenAwake.holds(holderB), isTrue);

      ScreenAwake.set(holderB, false);
      expect(ScreenAwake.isActive, isFalse);
      expect(ScreenAwake.holds(holderB), isFalse);
    });

    test('setEnabled(false) suppresses wakelock even with active holders', () {
      final holder = Object();
      ScreenAwake.set(holder, true);
      expect(ScreenAwake.isActive, isTrue);

      ScreenAwake.setEnabled(false);
      expect(ScreenAwake.isActive, isFalse);
      expect(ScreenAwake.holds(holder), isTrue);

      ScreenAwake.setEnabled(true);
      expect(ScreenAwake.isActive, isTrue);
    });
  });

  group('Now Playing ScreenAwake', () {
    testWidgets('keeps screen awake when expanded player is open and playing', (tester) async {
      final song = _mockSong();
      final playback = PlaybackState(
        currentSong: song,
        isPlaying: true,
      );

      await tester.pumpWidget(_wrapApp(
        child: const AndroidExpandedPlayer(),
        playbackState: playback,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(ScreenAwake.isActive, isTrue);
    });

    testWidgets('does not keep screen awake when playback is paused', (tester) async {
      final song = _mockSong();
      final playback = PlaybackState(
        currentSong: song,
        isPlaying: false,
      );

      await tester.pumpWidget(_wrapApp(
        child: const AndroidExpandedPlayer(),
        playbackState: playback,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(ScreenAwake.isActive, isFalse);
    });

    testWidgets('releases wakelock when player is disposed', (tester) async {
      final song = _mockSong();
      final playback = PlaybackState(
        currentSong: song,
        isPlaying: true,
      );

      await tester.pumpWidget(_wrapApp(
        child: const AndroidExpandedPlayer(),
        playbackState: playback,
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(ScreenAwake.isActive, isTrue);

      // Replace with empty container to trigger dispose
      await tester.pumpWidget(_wrapApp(
        child: const SizedBox.shrink(),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(ScreenAwake.isActive, isFalse);
    });
  });

  group('Styled Player Layout Lyrics ScreenAwake', () {
    testWidgets('keeps screen awake when lyrics are shown and playing in styled layouts', (tester) async {
      final song = _mockSong();
      final lines = [
        LyricLine(text: 'Line 1', startTime: Duration.zero, endTime: const Duration(seconds: 5)),
        LyricLine(text: 'Line 2', startTime: const Duration(seconds: 5), endTime: const Duration(seconds: 10)),
      ];
      final lyricsState = LyricsState(
        songId: song.id,
        rawLrc: '[00:00.00]Line 1\n[00:05.00]Line 2',
        isSynced: true,
        parsedLines: lines,
      );
      final playback = PlaybackState(
        currentSong: song,
        isPlaying: true,
        position: const Duration(seconds: 1),
      );

      for (final style in [PlayerLayoutStyle.card, PlayerLayoutStyle.arc, PlayerLayoutStyle.linear]) {
        ScreenAwake.resetForTesting();
        await tester.pumpWidget(_wrapApp(
          child: StyledPlayerLayout(
            style: style,
            song: song,
            playerRootKey: GlobalKey(),
            enableSlide: false,
            fadeWithSlide: (child, _) => child,
            onShowLyrics: () {},
            onShowQueue: () {},
            onShowOptions: () {},
            onShowSongInfo: () {},
          ),
          settings: AppSettings()
            ..playerStyle = style.name
            ..playerLyricLine = true,
          playbackState: playback,
          lyricsState: lyricsState,
        ));
        await tester.pump(const Duration(milliseconds: 50));

        expect(ScreenAwake.isActive, isTrue, reason: 'Failed for style ${style.name}');
      }
    });
  });

  group('Android Lyrics Screen ScreenAwake', () {
    testWidgets('keeps screen awake while lyrics screen is open and releases on dispose', (tester) async {
      final song = _mockSong();
      final playback = PlaybackState(
        currentSong: song,
        isPlaying: false, // Awake even when paused
      );

      await tester.pumpWidget(_wrapApp(
        child: const AndroidLyricsScreen(),
        playbackState: playback,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(ScreenAwake.isActive, isTrue);

      // Close lyrics screen
      await tester.pumpWidget(_wrapApp(
        child: const SizedBox.shrink(),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(ScreenAwake.isActive, isFalse);
    });
  });
}
