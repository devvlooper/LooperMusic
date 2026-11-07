import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/analyze/domain/analyze_models.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
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

/// The full computed Looper Analyze report, recomputed whenever the library
/// or play-event log changes. Reuses [libraryProvider] instead of watching
/// songs a second time.
@Riverpod(keepAlive: true)
AnalyzeSnapshot analyzeSnapshot(Ref ref) {
  final library = ref.watch(libraryProvider);
  final events = ref.watch(playEventsProvider).value ?? [];

  if (!library.isInitialized) return AnalyzeSnapshot.empty;

  var allSongs = library.songs;
  var allArtists = library.artists;

  final isConnected = ref.watch(isOnlineConnectedProvider);
  if (isConnected) {
    final onlineHistory =
        ref.watch(onlineAccountHistoryProvider).value ?? const [];
    final onlineFavorites =
        ref.watch(onlineAccountFavoritesProvider).value ?? const [];
    final onlineArtists =
        ref.watch(onlineAccountArtistsProvider).value ?? const [];

    final seenPaths = {for (final s in allSongs) s.path};
    final extraSongs = <Song>[];
    for (final h in onlineHistory) {
      final s = h.toSong();
      if (seenPaths.add(s.path)) extraSongs.add(s);
    }
    for (final f in onlineFavorites) {
      final s = f.toSong()..isFavorite = true;
      if (seenPaths.add(s.path)) extraSongs.add(s);
    }

    if (extraSongs.isNotEmpty) {
      allSongs = [...allSongs, ...extraSongs];
    }

    if (onlineArtists.isNotEmpty) {
      final seenNames = {for (final a in allArtists) a.name.toLowerCase()};
      final extraArtists = [
        for (final a in onlineArtists)
          if (!seenNames.contains(a.title.toLowerCase()))
            Artist()
              ..name = a.title
              ..artistImageUrl = a.thumbnail,
      ];
      allArtists = [...allArtists, ...extraArtists];
    }
  }

  return AnalyzeSnapshot.compute(
    songs: allSongs,
    events: events,
    artists: allArtists,
  );
}

/// The Top Songs list toggle: 10 or 20 entries shown.
@Riverpod(keepAlive: true)
class AnalyzeTopSongsLimit extends _$AnalyzeTopSongsLimit {
  @override
  int build() => 10;

  void set(int value) => state = value;
}
