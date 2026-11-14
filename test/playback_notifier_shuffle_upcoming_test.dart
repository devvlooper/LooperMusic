import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';

Song _song(String path, String title) => Song()
  ..id = path.hashCode
  ..path = path
  ..title = title
  ..artist = 'Artist';

class _FakeSettings extends Settings {
  @override
  AppSettings build() => AppSettings()..persistQueue = false;
}

class _TestPlayback extends Playback {
  _TestPlayback(this.initialQueue, {this.initialIndex = 0});
  final List<Song> initialQueue;
  final int initialIndex;

  @override
  PlaybackState build() {
    return PlaybackState(
      currentSong: initialQueue.isNotEmpty && initialIndex >= 0 && initialIndex < initialQueue.length
          ? initialQueue[initialIndex]
          : null,
      queue: List.unmodifiable(initialQueue),
    );
  }
}

void main() {
  group('PlaybackNotifier.shuffleUpcomingQueue', () {
    test('safely no-ops on empty queue', () async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _FakeSettings()),
          playbackProvider.overrideWith(() => _TestPlayback([])),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueueForTesting([]);
      await notifier.shuffleUpcomingQueue();
      expect(notifier.playlistForTesting, isEmpty);
      expect(container.read(playbackProvider).queue, isEmpty);
    });

    test('safely no-ops on single-song queue', () async {
      final song = _song('/song0.mp3', 'Song 0');
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _FakeSettings()),
          playbackProvider.overrideWith(() => _TestPlayback([song])),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueueForTesting([song]);
      await notifier.shuffleUpcomingQueue(rotationSongPath: song.path);
      expect(notifier.playlistForTesting.length, 1);
      expect(container.read(playbackProvider).currentSong?.path, song.path);
    });

    test('keeps current song at current position while shuffling upcoming songs', () async {
      final songs = List.generate(
        15,
        (i) => _song('/song$i.mp3', 'Song $i'),
      );
      final current = songs[2]; // current song is at index 2
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _FakeSettings()),
          playbackProvider.overrideWith(
            () => _TestPlayback(songs, initialIndex: 2),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueueForTesting(songs, currentIndex: 2);
      await notifier.shuffleUpcomingQueue(rotationSongPath: current.path);

      final state = container.read(playbackProvider);

      // Current song must remain identical and at index 2 in playlist
      expect(state.currentSong?.path, current.path);
      expect(notifier.playlistForTesting[2].path, current.path);

      // Total count remains identical
      expect(notifier.playlistForTesting.length, 15);
      expect(state.queue.length, 15);

      // All original tracks are still present in the queue
      final allPathsBefore = songs.map((s) => s.path).toSet();
      final allPathsAfter = notifier.playlistForTesting.map((s) => s.path).toSet();
      expect(allPathsAfter, equals(allPathsBefore));
    });
  });
}
