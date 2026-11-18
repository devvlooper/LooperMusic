import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_grids.g.dart';

// Providers for Albums and Artists
@Riverpod(keepAlive: true)
Stream<List<Album>> albums(Ref ref) {
  return DbService.isar.albums.where().sortByDateAddedDesc().watch(
    fireImmediately: true,
  );
}

@Riverpod(keepAlive: true)
Stream<List<Artist>> artists(Ref ref) {
  return DbService.isar.artists.where().sortByName().watch(
    fireImmediately: true,
  );
}

/// Reactively watches every song tagged with [albumName], so a
/// CollectionDetailView opened for an album updates live when that album
/// (or one of its songs) is edited, instead of showing a stale snapshot.
@Riverpod(keepAlive: true)
Stream<List<Song>> songsForAlbum(Ref ref, String albumName) {
  return DbService.isar.songs
      .filter()
      .albumEqualTo(albumName)
      .watch(fireImmediately: true);
}
