import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/analyze/domain/analyze_models.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'analyze_notifier.g.dart';

/// Recent play-event log, newest first, capped generously so the trend
/// chart, streaks, and activity heatmap have plenty of history to work with
/// without ever loading the entire (pruned) table into memory.
@Riverpod(keepAlive: true)
Stream<List<PlayEvent>> playEvents(Ref ref) {
  return DbService.isar.playEvents
      .where()
      .sortByPlayedAtDesc()
      .limit(5000)
      .watch(fireImmediately: true);
}

/// Online songs that have actually been played in Looper Music (play count or
/// listening time on record). Watched reactively from Isar.
@Riverpod(keepAlive: true)
Stream<List<Song>> playedOnlineSongs(Ref ref) {
  return DbService.isar.songs
      .filter()
      .pathStartsWith('yt:')
      .and()
      .group(
        (q) => q.playCountGreaterThan(0).or().totalListenedMsGreaterThan(0),
      )
      .watch(fireImmediately: true);
}

/// The full computed Looper Analyze report, recomputed whenever the library,
/// played online tracks, or play-event log changes.
@Riverpod(keepAlive: true)
AnalyzeSnapshot analyzeSnapshot(Ref ref) {
  final library = ref.watch(libraryProvider);
  final events = ref.watch(playEventsProvider).value ?? [];
  final onlineSongs = ref.watch(playedOnlineSongsProvider).value ?? [];

  if (!library.isInitialized) return AnalyzeSnapshot.empty;

  // Combine local library songs with online songs actually played in Looper.
  final allSongs = [...library.songs, ...onlineSongs];
  final allArtists = library.artists;

  return AnalyzeSnapshot.compute(
    songs: allSongs,
    events: events,
    artists: allArtists,
    totalLocalSongs: library.songs.length,
  );
}

/// The Top Songs list toggle: 10 or 20 entries shown.
@Riverpod(keepAlive: true)
class AnalyzeTopSongsLimit extends _$AnalyzeTopSongsLimit {
  @override
  int build() => 10;

  void set(int value) => state = value;
}
