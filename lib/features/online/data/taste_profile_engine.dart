import 'dart:math' as math;

import 'package:looper_player/features/online/data/online_playback.dart';
import 'package:looper_player/features/online/data/parsers.dart';

enum UnicodeScript {
  devanagari('Devanagari'),
  arabic('Arabic'),
  hangul('Hangul'),
  cjk('Kana/Han'),
  cyrillic('Cyrillic'),
  latin('Latin'),
  other('Other');

  const UnicodeScript(this.label);
  final String label;

  static UnicodeScript detect(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0900 && rune <= 0x097F) return UnicodeScript.devanagari;
      if ((rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF)) {
        return UnicodeScript.arabic;
      }
      if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
          (rune >= 0x1100 && rune <= 0x11FF) ||
          (rune >= 0x3130 && rune <= 0x318F)) {
        return UnicodeScript.hangul;
      }
      if ((rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0x4E00 && rune <= 0x9FFF)) {
        return UnicodeScript.cjk;
      }
      if (rune >= 0x0400 && rune <= 0x04FF) return UnicodeScript.cyrillic;
    }
    for (final rune in text.runes) {
      if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A) ||
          (rune >= 0x00C0 && rune <= 0x024F)) {
        return UnicodeScript.latin;
      }
    }
    return UnicodeScript.other;
  }
}

class TastePlayEventDTO {
  const TastePlayEventDTO({
    required this.songPath,
    required this.songTitle,
    this.artist,
    this.genre,
    this.durationMs,
    required this.listenedMs,
    required this.playedAt,
  });

  final String songPath;
  final String songTitle;
  final String? artist;
  final String? genre;
  final int? durationMs;
  final int listenedMs;
  final DateTime playedAt;

  Map<String, dynamic> toJson() => {
    'p': songPath,
    't': songTitle,
    'a': artist,
    'g': genre,
    'd': durationMs,
    'l': listenedMs,
    'at': playedAt.millisecondsSinceEpoch,
  };

  factory TastePlayEventDTO.fromJson(Map<String, dynamic> j) => TastePlayEventDTO(
    songPath: j['p'] as String? ?? '',
    songTitle: j['t'] as String? ?? '',
    artist: j['a'] as String?,
    genre: j['g'] as String?,
    durationMs: j['d'] as int?,
    listenedMs: j['l'] as int? ?? 0,
    playedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
  );
}

class TasteSongDTO {
  const TasteSongDTO({
    required this.path,
    required this.title,
    this.artist,
    this.genre,
    this.year,
    required this.dateAdded,
    this.isFavorite = false,
    this.isDownloaded = false,
  });

  final String path;
  final String title;
  final String? artist;
  final String? genre;
  final int? year;
  final DateTime dateAdded;
  final bool isFavorite;
  final bool isDownloaded;

  Map<String, dynamic> toJson() => {
    'p': path,
    't': title,
    'a': artist,
    'g': genre,
    'y': year,
    'da': dateAdded.millisecondsSinceEpoch,
    'f': isFavorite,
    'dl': isDownloaded,
  };

  factory TasteSongDTO.fromJson(Map<String, dynamic> j) => TasteSongDTO(
    path: j['p'] as String? ?? '',
    title: j['t'] as String? ?? '',
    artist: j['a'] as String?,
    genre: j['g'] as String?,
    year: j['y'] as int?,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(j['da'] as int? ?? 0),
    isFavorite: j['f'] as bool? ?? false,
    isDownloaded: j['dl'] as bool? ?? false,
  );
}

class TasteInputDTO {
  const TasteInputDTO({
    this.artists = const [],
    this.genres = const [],
    this.recentSearches = const [],
    this.hiddenProfileKeys = const {},
  });

  final List<String> artists;
  final List<String> genres;
  final List<String> recentSearches;
  final Set<String> hiddenProfileKeys;

  Map<String, dynamic> toJson() => {
    'a': artists,
    'g': genres,
    's': recentSearches,
    'h': hiddenProfileKeys.toList(),
  };

  factory TasteInputDTO.fromJson(Map<String, dynamic> j) => TasteInputDTO(
    artists: [for (final a in (j['a'] as List? ?? const [])) a.toString()],
    genres: [for (final g in (j['g'] as List? ?? const [])) g.toString()],
    recentSearches: [for (final s in (j['s'] as List? ?? const [])) s.toString()],
    hiddenProfileKeys: {for (final k in (j['h'] as List? ?? const [])) k.toString()},
  );
}

class TasteProfileCluster {
  const TasteProfileCluster({
    required this.key,
    required this.dominantGenre,
    required this.script,
    required this.score,
    required this.topArtists,
    required this.topGenres,
    required this.topOnlineSeedIds,
  });

  final String key;
  final String dominantGenre;
  final String script;
  final double score;
  final List<String> topArtists;
  final List<String> topGenres;
  final List<String> topOnlineSeedIds;

  String get displayTitle {
    if (dominantGenre.isNotEmpty &&
        dominantGenre.toLowerCase() != 'general' &&
        dominantGenre.toLowerCase() != 'unknown') {
      return 'Mix: $dominantGenre';
    }
    if (script.isNotEmpty &&
        script.toLowerCase() != 'latin' &&
        script.toLowerCase() != 'other') {
      return 'Mix: $script';
    }
    return 'Mix: Music';
  }

  Map<String, dynamic> toJson() => {
    'k': key,
    'dg': dominantGenre,
    'sc': script,
    's': score,
    'a': topArtists,
    'g': topGenres,
    'o': topOnlineSeedIds,
  };

  factory TasteProfileCluster.fromJson(Map<String, dynamic> j) =>
      TasteProfileCluster(
        key: j['k'] as String? ?? '',
        dominantGenre: j['dg'] as String? ?? '',
        script: j['sc'] as String? ?? '',
        score: (j['s'] as num? ?? 0.0).toDouble(),
        topArtists: [
          for (final a in (j['a'] as List? ?? const [])) a.toString(),
        ],
        topGenres: [
          for (final g in (j['g'] as List? ?? const [])) g.toString(),
        ],
        topOnlineSeedIds: [
          for (final o in (j['o'] as List? ?? const [])) o.toString(),
        ],
      );
}

class TasteProfileSnapshot {
  const TasteProfileSnapshot({
    required this.builtAt,
    required this.topArtists,
    required this.topOnlineIds,
    required this.recentSearches,
    required this.genres,
    required this.profiles,
    required this.artistScores,
  });

  final DateTime builtAt;
  final List<String> topArtists;
  final List<String> topOnlineIds;
  final List<String> recentSearches;
  final List<String> genres;
  final List<TasteProfileCluster> profiles;
  final Map<String, double> artistScores;

  bool get isEmpty =>
      topArtists.isEmpty &&
      topOnlineIds.isEmpty &&
      recentSearches.isEmpty &&
      genres.isEmpty &&
      profiles.isEmpty;

  Map<String, dynamic> toJson() => {
    'builtAt': builtAt.millisecondsSinceEpoch,
    'topArtists': topArtists,
    'topOnlineIds': topOnlineIds,
    'recentSearches': recentSearches,
    'genres': genres,
    'profiles': [for (final p in profiles) p.toJson()],
    'artistScores': artistScores,
  };

  factory TasteProfileSnapshot.fromJson(Map<String, dynamic> j) =>
      TasteProfileSnapshot(
        builtAt: DateTime.fromMillisecondsSinceEpoch(
          j['builtAt'] as int? ?? 0,
        ),
        topArtists: [
          for (final a in (j['topArtists'] as List? ?? const [])) a.toString(),
        ],
        topOnlineIds: [
          for (final o in (j['topOnlineIds'] as List? ?? const []))
            o.toString(),
        ],
        recentSearches: [
          for (final s in (j['recentSearches'] as List? ?? const []))
            s.toString(),
        ],
        genres: [
          for (final g in (j['genres'] as List? ?? const [])) g.toString(),
        ],
        profiles: [
          for (final p in (j['profiles'] as List? ?? const []))
            if (p is Map)
              TasteProfileCluster.fromJson(p.cast<String, dynamic>()),
        ],
        artistScores: {
          for (final e in ((j['artistScores'] as Map?) ?? const {}).entries)
            e.key.toString(): (e.value as num).toDouble(),
        },
      );
}

final _creditSeparator = RegExp(
  r'\s*[;/\\&,]\s*|\s+(?:feat\.?|ft\.?|featuring|and|with|x)\s+',
  caseSensitive: false,
);

final _titleGuests = RegExp(
  r'[(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+([^)\]]+)[)\]]'
  r'|\s(?:feat\.?|ft\.?|featuring)\s+(.+)$',
  caseSensitive: false,
);

List<String> _splitCredits(String raw) => raw
    .split(_creditSeparator)
    .map((name) => name.trim())
    .where((name) => name.isNotEmpty)
    .toList();

List<String> splitArtistCredits(String? artist, String title) {
  final a = artist?.trim() ?? '';
  return [
    if (a.isNotEmpty) ...[a, ..._splitCredits(a)],
    for (final match in _titleGuests.allMatches(title))
      ..._splitCredits(match.group(1) ?? match.group(2) ?? ''),
  ];
}

/// Pure taste profile computation.
TasteProfileSnapshot computeTasteProfile(
  List<TastePlayEventDTO> events,
  List<TasteSongDTO> songs,
  TasteInputDTO taste, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  const halfLifeDays = 14.0;
  const likedBonus = 3.0;
  const downloadBonus = 2.0;
  const localSongBase = 0.4;
  const recentLocalBonus = 0.5;
  const artistCapLocal = 8.0;

  final songScores = <String, double>{};
  final artistScores = <String, double>{};
  final artistGenres = <String, Map<String, int>>{};
  final artistScripts = <String, Map<UnicodeScript, int>>{};
  final artistOnlineSongs = <String, List<String>>{};

  void creditArtist(String? artistName, String title, double weight) {
    if (artistName == null || artistName.trim().isEmpty || weight <= 0) return;
    final names = splitArtistCredits(artistName, title).toSet();
    if (names.length > 1) names.remove(artistName.trim());
    for (final name in names) {
      final clean = name.trim();
      if (clean.isEmpty) continue;
      artistScores.update(clean, (v) => v + weight, ifAbsent: () => weight);
    }
  }

  void recordArtistMetadata(
    String? artistName,
    String title,
    String? genre,
    String path,
  ) {
    if (artistName == null || artistName.trim().isEmpty) return;
    final clean = artistName.trim();
    if (genre != null && genre.trim().isNotEmpty) {
      final g = genre.trim();
      artistGenres.putIfAbsent(clean, () => {}).update(
            g,
            (v) => v + 1,
            ifAbsent: () => 1,
          );
    }
    final script = UnicodeScript.detect(title);
    artistScripts.putIfAbsent(clean, () => {}).update(
          script,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
    if (path.startsWith('yt:')) {
      artistOnlineSongs
          .putIfAbsent(clean, () => [])
          .add(path.substring(3));
    }
  }

  // 1. Process play events
  for (final e in events) {
    recordArtistMetadata(e.artist, e.songTitle, e.genre, e.songPath);
    final ageDays = current.difference(e.playedAt).inMinutes / 1440.0;
    final dur = e.durationMs ?? 0;
    final listened = e.listenedMs;

    if (dur > 0 && listened < 30000) {
      // Skip under 30s: -0.3 to song, 0 to artist
      songScores.update(e.songPath, (v) => v - 0.3, ifAbsent: () => -0.3);
    } else {
      final heard = dur > 0 && listened > 0
          ? (listened / dur).clamp(0.1, 1.0)
          : 0.5;
      final w = math.pow(0.5, ageDays / halfLifeDays) * heard;
      songScores.update(e.songPath, (v) => v + w, ifAbsent: () => w);
      creditArtist(e.artist, e.songTitle, w);
    }
  }

  // 2. Process songs (favorites, downloads, local collection)
  final localCounts = <String, int>{};
  for (final s in songs) {
    recordArtistMetadata(s.artist, s.title, s.genre, s.path);

    if (s.isFavorite) {
      songScores.update(s.path, (v) => v + likedBonus, ifAbsent: () => likedBonus);
      creditArtist(s.artist, s.title, likedBonus);
    }
    if (s.isDownloaded) {
      songScores.update(
        s.path,
        (v) => v + downloadBonus,
        ifAbsent: () => downloadBonus,
      );
      creditArtist(s.artist, s.title, downloadBonus);
    }

    if (!s.path.startsWith('yt:')) {
      var songCredit = localSongBase;
      if (current.difference(s.dateAdded).inDays < 30) {
        songCredit += recentLocalBonus;
      }
      songScores.update(s.path, (v) => v + songCredit, ifAbsent: () => songCredit);

      if (s.artist != null && s.artist!.trim().isNotEmpty) {
        final a = s.artist!.trim();
        localCounts.update(a, (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }

  // 3. Local songs per artist credit (0.4 each, capped at 8.0)
  localCounts.forEach((artist, count) {
    final credit = math.min(count * localSongBase, artistCapLocal);
    creditArtist(artist, '', credit);
  });

  // 4. Stated taste artists
  final playedArtists = (artistScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(8)
      .map((e) => e.key)
      .toList();

  final topArtists = <String>[];
  final seenArtists = <String>{};
  final stated = taste.artists;
  final maxIter = math.max(playedArtists.length, stated.length);
  for (var i = 0; i < maxIter; i++) {
    for (final list in [playedArtists, stated]) {
      if (i < list.length && seenArtists.add(list[i].toLowerCase())) {
        topArtists.add(list[i]);
      }
    }
  }

  // 5. Radio seeds (online songs with positive score only)
  final topOnlineIds = (songScores.entries
        .where((e) => e.key.startsWith('yt:') && e.value > 0)
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(10)
      .map((e) => e.key.substring(3))
      .toList();

  // 6. Cluster profiles: key = (dominant genre of artist, language script)
  final clusterScores = <String, double>{};
  final clusterArtists = <String, List<String>>{};
  final clusterGenres = <String, Map<String, int>>{};
  final clusterOnlineSongs = <String, Set<String>>{};
  final clusterInfo = <String, ({String genre, String script})>{};

  artistScores.forEach((artist, score) {
    final gMap = artistGenres[artist] ?? {};
    var dominantGenre = 'General';
    if (gMap.isNotEmpty) {
      dominantGenre = (gMap.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
    } else if (taste.genres.isNotEmpty) {
      dominantGenre = taste.genres.first;
    }

    final sMap = artistScripts[artist] ?? {};
    var dominantScript = UnicodeScript.detect(artist);
    if (sMap.isNotEmpty) {
      dominantScript = (sMap.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
    }
    final scriptLabel = dominantScript.label;
    final clusterKey = '$dominantGenre · $scriptLabel';

    clusterScores.update(clusterKey, (v) => v + score, ifAbsent: () => score);
    clusterArtists.putIfAbsent(clusterKey, () => []).add(artist);
    clusterInfo[clusterKey] = (genre: dominantGenre, script: scriptLabel);

    if (gMap.isNotEmpty) {
      final cg = clusterGenres.putIfAbsent(clusterKey, () => {});
      gMap.forEach((g, count) => cg.update(g, (v) => v + count, ifAbsent: () => count));
    }
    final online = artistOnlineSongs[artist];
    if (online != null) {
      clusterOnlineSongs.putIfAbsent(clusterKey, () => {}).addAll(online);
    }
  });

  final sortedClusters = clusterScores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final bestScore = sortedClusters.firstOrNull?.value ?? 0.0;
  final threshold = bestScore * 0.1;

  final profiles = <TasteProfileCluster>[];
  for (final entry in sortedClusters) {
    if (entry.value < threshold && profiles.isNotEmpty) break;
    if (taste.hiddenProfileKeys.contains(entry.key)) continue;

    final info = clusterInfo[entry.key]!;
    final artistsInCluster = clusterArtists[entry.key] ?? [];
    artistsInCluster.sort((a, b) =>
        (artistScores[b] ?? 0.0).compareTo(artistScores[a] ?? 0.0));

    final gMap = clusterGenres[entry.key] ?? {};
    final topG = (gMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toList();

    profiles.add(
      TasteProfileCluster(
        key: entry.key,
        dominantGenre: info.genre,
        script: info.script,
        score: entry.value,
        topArtists: artistsInCluster.take(5).toList(),
        topGenres: topG.isNotEmpty ? topG : [info.genre],
        topOnlineSeedIds: (clusterOnlineSongs[entry.key] ?? {}).take(5).toList(),
      ),
    );
    if (profiles.length >= 4) break;
  }

  return TasteProfileSnapshot(
    builtAt: current,
    topArtists: topArtists.take(8).toList(),
    topOnlineIds: topOnlineIds,
    recentSearches: taste.recentSearches.take(5).toList(),
    genres: taste.genres,
    profiles: profiles,
    artistScores: artistScores,
  );
}

/// Ranks fetched candidates using artist affinity, seed match, recent play penalty,
/// and NotInterested filters, holding back 20% for exploration.
List<OnlineSong> rankCandidates(
  List<OnlineSong> candidates,
  TasteProfileSnapshot profile, {
  Set<String> recentPaths = const {},
  Set<String> blockedArtists = const {},
  Set<String> hiddenSongs = const {},
  int limit = 30,
}) {
  final cleanBlocked = {for (final a in blockedArtists) a.trim().toLowerCase()};
  final profileTopArtistsLower = {
    for (final a in profile.topArtists) a.trim().toLowerCase(),
  };

  final maxScore = profile.artistScores.values.fold<double>(
    1.0,
    (m, v) => math.max(m, v),
  );

  final scoredCandidates = <({OnlineSong song, double score, bool isProfileArtist})>[];
  final seenKeys = <String>{};

  for (final song in candidates) {
    if (hiddenSongs.contains(song.videoId)) continue;
    final artistLower = song.artist?.trim().toLowerCase();
    if (artistLower != null && cleanBlocked.contains(artistLower)) continue;

    final normTitle = OnlinePlayback.normalizeTitle(song.title);
    final dedupeKey = '$normTitle|${artistLower ?? ''}';
    if (!seenKeys.add(dedupeKey)) continue;

    final rawArtistScore = artistLower != null
        ? (profile.artistScores[song.artist] ??
            profile.artistScores[artistLower] ??
            0.0)
        : 0.0;
    final artistAffinity = (rawArtistScore / maxScore).clamp(0.0, 1.0);

    final isProfile = artistLower != null &&
        profileTopArtistsLower.contains(artistLower);
    final profileMatch = isProfile ? 0.5 : 0.0;
    final heardPenalty = recentPaths.contains(song.path) ? 1.0 : 0.0;

    final score = artistAffinity + profileMatch - heardPenalty;
    scoredCandidates.add((song: song, score: score, isProfileArtist: isProfile));
  }

  final profileSongs = scoredCandidates
      .where((item) => item.isProfileArtist)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  final exploreSongs = scoredCandidates
      .where((item) => !item.isProfileArtist)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  // 20% of slots held back for exploration
  final exploreCount = (limit * 0.2).round();
  final profileCount = limit - exploreCount;

  final selected = <OnlineSong>[];
  final selectedIds = <String>{};

  void pick(List<({OnlineSong song, double score, bool isProfileArtist})> list, int n) {
    var added = 0;
    for (final item in list) {
      if (added >= n) break;
      if (selectedIds.add(item.song.videoId)) {
        selected.add(item.song);
        added++;
      }
    }
  }

  pick(profileSongs, profileCount);
  pick(exploreSongs, exploreCount);

  // Fill remaining if needed
  if (selected.length < limit) {
    for (final item in [...profileSongs, ...exploreSongs]) {
      if (selected.length >= limit) break;
      if (selectedIds.add(item.song.videoId)) {
        selected.add(item.song);
      }
    }
  }

  return selected;
}
