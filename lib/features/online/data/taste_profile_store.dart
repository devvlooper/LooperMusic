import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/taste_profile_engine.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/data/online_downloader.dart';

abstract final class TasteProfileStore {
  static const _cacheKey = 'taste_profile_v2';
  static const _hiddenProfilesKey = 'hidden_taste_profiles';
  static const _moodPicksKey = 'taste_mood_picks';
  static const _freshDuration = Duration(hours: 6);
  static const _tag = 'TasteProfileStore';

  /// Plays before the profile relearns, so suggestions follow taste as it
  /// changes instead of hours later.
  static const _playsPerRebuild = 3;

  static int _playEventsSinceLastBuild = 0;
  static TasteProfileSnapshot? _cached;
  static Timer? _rebuildTimer;

  /// Bumped after every rebuild; listeners re-rank what they show.
  static final revision = ValueNotifier<int>(0);

  static void onPlayEventRecorded() {
    _playEventsSinceLastBuild++;
    if (_playEventsSinceLastBuild >= _playsPerRebuild) {
      invalidate();
      // Late enough for the previous song's listened time to be saved.
      _rebuildTimer?.cancel();
      _rebuildTimer = Timer(const Duration(seconds: 20), () {
        getOrBuild().then(
          (_) {},
          onError: (Object e) {
            LoggerHelper.write('$_tag: background rebuild failed', e);
          },
        );
      });
    }
  }

  /// Something changed (library scan, hidden profile): the next read
  /// rebuilds instead of reusing the memory or the saved copy.
  static void invalidate() {
    _cached = null;
    _dirty = true;
  }

  static bool _dirty = false;

  static Future<TasteProfileSnapshot> getOrBuild({bool force = false}) async {
    final now = DateTime.now();
    if (_dirty) force = true;

    if (!force &&
        _cached != null &&
        now.difference(_cached!.builtAt) < _freshDuration &&
        !_cached!.isStaleAt(now) &&
        _playEventsSinceLastBuild < _playsPerRebuild) {
      return _cached!;
    }

    if (!force && _playEventsSinceLastBuild < _playsPerRebuild) {
      try {
        final raw = await LocalJsonStore.read(_cacheKey);
        if (raw is Map) {
          final snapshot = TasteProfileSnapshot.fromJson(
            raw.cast<String, dynamic>(),
          );
          if (now.difference(snapshot.builtAt) < _freshDuration &&
              !snapshot.isStaleAt(now)) {
            _cached = snapshot;
            return snapshot;
          }
        }
      } catch (e) {
        LoggerHelper.write('$_tag: cache read failed', e);
      }
    }

    return _rebuild();
  }

  /// A mood chip picked on Home: a stated mood the profile learns from.
  static Future<void> recordMoodPick(String mood) async {
    final raw = await LocalJsonStore.read(_moodPicksKey);
    final picks = [
      ...(raw is List ? raw : const []).whereType<List>(),
      [mood, DateTime.now().millisecondsSinceEpoch],
    ];
    // Old picks have faded to nothing anyway.
    final kept = picks.length > 60 ? picks.sublist(picks.length - 60) : picks;
    await LocalJsonStore.write(_moodPicksKey, kept);
    invalidate();
  }

  static Future<TasteProfileSnapshot> _rebuild() async {
    final isar = DbService.isar;

    final events = await isar.playEvents
        .where()
        .sortByPlayedAtDesc()
        .limit(3000)
        .findAll();

    final songs = await isar.songs.where().findAll();

    final taste = await TasteNotifier.loaded();
    final searches = await LocalJsonStore.read('recent_searches');
    final hiddenRaw = await LocalJsonStore.read(_hiddenProfilesKey);
    final moodRaw = await LocalJsonStore.read(_moodPicksKey);
    final hiddenKeys = {
      for (final k in (hiddenRaw is List ? hiddenRaw : const []))
        if (k is String) k,
    };

    final eventDTOs = [
      for (final e in events)
        TastePlayEventDTO(
          songPath: e.songPath,
          songTitle: e.songTitle,
          artist: e.artist,
          genre: e.genre,
          durationMs: e.durationMs,
          listenedMs: e.listenedMs,
          playedAt: e.playedAt,
        ),
    ];

    final downloadDirs = await DownloadFolders.all();
    final songDTOs = [
      for (final s in songs)
        TasteSongDTO(
          path: s.path,
          title: s.title,
          artist: s.artist,
          genre: s.genre,
          year: s.year,
          dateAdded: s.dateAdded,
          isFavorite: s.isFavorite,
          isDownloaded: DownloadFolders.contains(s.path, downloadDirs),
        ),
    ];

    final tasteDTO = TasteInputDTO(
      artists: [for (final a in taste.artists) a.name],
      genres: taste.genres,
      recentSearches: [
        ...(searches is List ? searches : const []).whereType<String>().take(5),
      ],
      hiddenProfileKeys: hiddenKeys,
      moodPicks: [
        for (final m in (moodRaw is List ? moodRaw : const []))
          if (m is List && m.length == 2 && m[1] is int)
            (m[0].toString(), DateTime.fromMillisecondsSinceEpoch(m[1] as int)),
      ],
    );

    TasteProfileSnapshot snapshot;
    if (songDTOs.length > 2000) {
      snapshot = await Isolate.run(
        () => computeTasteProfile(eventDTOs, songDTOs, tasteDTO),
      );
    } else {
      snapshot = computeTasteProfile(eventDTOs, songDTOs, tasteDTO);
    }

    _playEventsSinceLastBuild = 0;
    _dirty = false;
    _cached = snapshot;
    revision.value++;

    try {
      await LocalJsonStore.write(_cacheKey, snapshot.toJson());
    } catch (e) {
      LoggerHelper.write('$_tag: cache save failed', e);
    }

    return snapshot;
  }

  static Future<Set<String>> getHiddenProfiles() async {
    final raw = await LocalJsonStore.read(_hiddenProfilesKey);
    return {
      for (final k in (raw is List ? raw : const []))
        if (k is String) k,
    };
  }

  static Future<void> hideProfile(String key) async {
    final set = await getHiddenProfiles();
    if (set.add(key)) {
      await LocalJsonStore.write(_hiddenProfilesKey, set.toList());
      invalidate();
    }
  }

  static Future<void> unhideProfile(String key) async {
    final set = await getHiddenProfiles();
    if (set.remove(key)) {
      await LocalJsonStore.write(_hiddenProfilesKey, set.toList());
      invalidate();
    }
  }

  @visibleForTesting
  static void resetForTesting({TasteProfileSnapshot? snapshot}) {
    _cached = snapshot;
    _playEventsSinceLastBuild = 0;
    _dirty = false;
  }
}
