import 'package:flutter/foundation.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/features/online/data/parsers.dart';

/// Persisted store for user "Not interested" signals (hidden songs and blocked artists).
/// Used to filter recommendations, auto-queue, and discovery feeds.
abstract final class NotInterestedStore {
  static const _key = 'not_interested';
  static Set<String> _hiddenSongIds = {};
  static Set<String> _blockedArtists = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final raw = await LocalJsonStore.read(_key);
    if (raw is Map) {
      _hiddenSongIds = {
        for (final id in (raw['songs'] as List? ?? const []))
          if (id is String && id.trim().isNotEmpty) id.trim(),
      };
      _blockedArtists = {
        for (final a in (raw['artists'] as List? ?? const []))
          if (a is String && a.trim().isNotEmpty) a.trim().toLowerCase(),
      };
    }
    _loaded = true;
  }

  static Set<String> get hiddenSongIds => Set.unmodifiable(_hiddenSongIds);
  static Set<String> get blockedArtists => Set.unmodifiable(_blockedArtists);

  static Future<void> hideSong(String videoId) async {
    await load();
    if (_hiddenSongIds.add(videoId.trim())) {
      await _persist();
    }
  }

  static Future<void> unhideSong(String videoId) async {
    await load();
    if (_hiddenSongIds.remove(videoId.trim())) {
      await _persist();
    }
  }

  static Future<void> blockArtist(String artist) async {
    await load();
    final clean = artist.trim().toLowerCase();
    if (clean.isNotEmpty && _blockedArtists.add(clean)) {
      await _persist();
    }
  }

  static Future<void> unblockArtist(String artist) async {
    await load();
    final clean = artist.trim().toLowerCase();
    if (_blockedArtists.remove(clean)) {
      await _persist();
    }
  }

  static bool isSongHidden(String videoId) {
    return _hiddenSongIds.contains(videoId.trim());
  }

  static bool isArtistBlocked(String? artist) {
    if (artist == null || artist.trim().isEmpty) return false;
    return _blockedArtists.contains(artist.trim().toLowerCase());
  }

  static bool isBlocked(OnlineSong song) {
    if (isSongHidden(song.videoId)) return true;
    if (isArtistBlocked(song.artist)) return true;
    return false;
  }

  static List<OnlineSong> filter(Iterable<OnlineSong> songs) {
    return songs.where((s) => !isBlocked(s)).toList();
  }

  static Future<void> _persist() async {
    await LocalJsonStore.write(_key, {
      'songs': _hiddenSongIds.toList(),
      'artists': _blockedArtists.toList(),
    });
  }

  @visibleForTesting
  static void resetForTesting({
    Set<String>? songs,
    Set<String>? artists,
  }) {
    _hiddenSongIds = songs != null ? Set.from(songs) : {};
    _blockedArtists = artists != null
        ? {for (final a in artists) a.trim().toLowerCase()}
        : {};
    _loaded = true;
  }
}
