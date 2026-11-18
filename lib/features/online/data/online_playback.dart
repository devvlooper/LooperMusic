import 'dart:async';

import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/online/data/online_cache.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';
import 'package:looper_player/features/search/domain/artist_credits.dart';

/// What mpv should open for a song.
class PlayableSource {
  const PlayableSource(
    this.path, {
    this.userAgent,
    this.streamed = false,
    this.loudnessDb,
  });
  final String path;

  /// The User-Agent the stream URL was issued for (null for files).
  final String? userAgent;

  /// True when playing from the network (not a cached or local file).
  final bool streamed;

  /// Track loudness in dB above YouTube's -14 LKFS target; null = unknown.
  final double? loudnessDb;
}

/// Glue between the player and the online layer.
abstract final class OnlinePlayback {
  /// The source for an online song: a matching local file (when allowed),
  /// the cached file, or a fresh stream URL. Streaming also starts caching
  /// the song so a replay or offline listen comes from disk.
  static Future<PlayableSource> sourceFor(
    Song song, {
    bool allowNetwork = true,
  }) async {
    final id = song.videoId!;
    final settings = OnlineSettingsNotifier.current;
    if (settings.preferLocal) {
      final twin = await localTwin(song);
      if (twin != null) return PlayableSource(twin.path);
    }
    final cached = await OnlineCache.instance.cachedPath(id);
    if (cached != null) return PlayableSource(cached);
    if (!settings.enabled || !allowNetwork) {
      throw StreamUnavailableException('online music is turned off');
    }

    final pick = await StreamResolver.instance.resolve(id);
    final metered = await isNetworkMetered();
    if (settings.cachePlayed && (settings.cachePlayedOnMobile || !metered)) {
      unawaited(
        OnlineCache.instance.download(
          id,
          song: song,
          pick: pick,
          automatic: false,
        ),
      );
    }
    return PlayableSource(
      pick.url,
      userAgent: pick.userAgent,
      streamed: true,
      loudnessDb: pick.loudnessDb,
    );
  }

  static final _decoration = RegExp(
    r'[\(\[][^\)\]]*\b(official|lyrics?|audio|video|visuali[sz]er|remaster(ed)?|feat\.?|ft\.?|with)\b[^\)\]]*[\)\]]',
    caseSensitive: false,
  );
  static final _trailingFeat = RegExp(
    r'\s+(feat\.?|ft\.?|featuring)\s.*$',
    caseSensitive: false,
  );
  static final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static String normalizeTitle(String t) => t
      .replaceAll(_decoration, ' ')
      .replaceAll(_trailingFeat, '')
      .toLowerCase()
      .replaceAll(_nonWord, ' ')
      .trim();

  /// The same song in the local library: same cleaned title, a shared
  /// credited artist (whole names) and a duration within 3 seconds.
  static Future<Song?> localTwin(Song online) async {
    final title = normalizeTitle(online.title);
    if (title.isEmpty) return null;
    // The longest word narrows best. No row limit: rows come oldest first,
    // so a cap on a common word ("I", "Love") cut off fresh downloads.
    final word = title.split(' ').reduce((a, b) => b.length > a.length ? b : a);
    final candidates = await DbService.isar.songs
        .filter()
        .not()
        .pathStartsWith('yt:')
        .titleContains(word, caseSensitive: false)
        .findAll();
    final onlineArtists = creditedArtists(
      online,
    ).map((a) => a.toLowerCase()).toSet();
    for (final s in candidates) {
      if (normalizeTitle(s.title) != title) continue;
      final shared = creditedArtists(
        s,
      ).any((a) => onlineArtists.contains(a.toLowerCase()));
      if (!shared) continue;
      final a = s.duration, b = online.duration;
      if (a != null && b != null && (a - b).abs() > 3000) continue;
      return s;
    }
    return null;
  }

  /// Give unsaved online songs a database row (and id), so a saved queue,
  /// favorite or playlist entry survives a restart. Existing rows win.
  static Future<void> persist(Iterable<Song> songs) async {
    final fresh = [
      for (final s in songs)
        if (s.isOnline && s.id == Isar.autoIncrement) s,
    ];
    if (fresh.isEmpty) return;
    await DbService.isar.writeTxn(() async {
      final existing = await DbService.isar.songs.getAllByPath(
        fresh.map((s) => s.path).toList(),
      );
      final toInsert = <Song>[];
      final byPath = <String, Song>{};
      for (var i = 0; i < fresh.length; i++) {
        final row = existing[i];
        if (row != null) {
          fresh[i].id = row.id;
        } else if (byPath[fresh[i].path] case final first?) {
          fresh[i].id = first.id; // same song twice in one batch
        } else {
          try {
            fresh[i].dateAdded;
          } catch (_) {
            fresh[i].dateAdded = DateTime.now();
          }
          byPath[fresh[i].path] = fresh[i];
          toInsert.add(fresh[i]);
        }
      }
      await DbService.isar.songs.putAll(toInsert);
      for (final s in fresh) {
        if (s.id == Isar.autoIncrement) s.id = byPath[s.path]!.id;
      }
    });
  }
}

/// Which fetched radio songs may still be appended. The radio was asked for
/// [requestedFor] while the queue held [queueThen]; it applies only if that
/// song is still playing and the queue was not replaced meanwhile (every
/// entry it had is still there). Songs already queued are dropped.
List<Song> continuationToAppend({
  required String requestedFor,
  required Set<String> queueThen,
  required String? currentNow,
  required List<String> queueNow,
  required List<Song> fetched,
}) {
  if (currentNow != requestedFor) return const [];
  final now = queueNow.toSet();
  if (!now.containsAll(queueThen)) return const [];
  final seen = <String>{...now};
  return [
    for (final s in fetched)
      if (seen.add(s.path)) s,
  ];
}
