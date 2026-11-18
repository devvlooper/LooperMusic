import 'dart:math' as math;

import 'package:looper_player/features/analyze/domain/analyze_models.dart';
import 'package:looper_player/features/online/data/online_playback.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/song_traits.dart';

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

  factory TastePlayEventDTO.fromJson(Map<String, dynamic> j) =>
      TastePlayEventDTO(
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
    this.moodPicks = const [],
  });

  final List<String> artists;
  final List<String> genres;
  final List<String> recentSearches;
  final Set<String> hiddenProfileKeys;

  /// Mood chips the user picked on Home, and when.
  final List<(String, DateTime)> moodPicks;

  Map<String, dynamic> toJson() => {
    'a': artists,
    'g': genres,
    's': recentSearches,
    'h': hiddenProfileKeys.toList(),
    'm': [
      for (final (mood, at) in moodPicks) [mood, at.millisecondsSinceEpoch],
    ],
  };

  factory TasteInputDTO.fromJson(Map<String, dynamic> j) => TasteInputDTO(
    artists: [for (final a in (j['a'] as List? ?? const [])) a.toString()],
    genres: [for (final g in (j['g'] as List? ?? const [])) g.toString()],
    recentSearches: [
      for (final s in (j['s'] as List? ?? const [])) s.toString(),
    ],
    hiddenProfileKeys: {
      for (final k in (j['h'] as List? ?? const [])) k.toString(),
    },
    moodPicks: [
      for (final m in (j['m'] as List? ?? const []))
        if (m is List && m.length == 2 && m[1] is int)
          (m[0].toString(), DateTime.fromMillisecondsSinceEpoch(m[1] as int)),
    ],
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

  factory TasteProfileCluster.fromJson(
    Map<String, dynamic> j,
  ) => TasteProfileCluster(
    key: j['k'] as String? ?? '',
    dominantGenre: j['dg'] as String? ?? '',
    script: j['sc'] as String? ?? '',
    score: (j['s'] as num? ?? 0.0).toDouble(),
    topArtists: [for (final a in (j['a'] as List? ?? const [])) a.toString()],
    topGenres: [for (final g in (j['g'] as List? ?? const [])) g.toString()],
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
    this.risingArtists = const [],
    this.dayPartArtists = const [],
    this.fadingArtists = const [],
    this.traitScores = const {},
    this.risingTraits = const [],
    this.dayPartTraits = const [],
    this.fadingTraits = const [],
    this.artistGenres = const {},
  });

  final DateTime builtAt;
  final List<String> topArtists;
  final List<String> topOnlineIds;
  final List<String> recentSearches;
  final List<String> genres;
  final List<TasteProfileCluster> profiles;
  final Map<String, double> artistScores;

  /// Artists taking a bigger share of the last week than of all time: where
  /// taste is heading right now.
  final List<String> risingArtists;

  /// Artists usually played at this time of day ([builtAt]'s [DayPart]).
  final List<String> dayPartArtists;

  /// Artists the user keeps skipping lately.
  final List<String> fadingArtists;

  /// Learned weight of each song trait (`genre:`, `mood:`, `type:`,
  /// `lang:`; see [songTraits]), like [artistScores].
  final Map<String, double> traitScores;

  /// Traits taking a bigger share of this week, played at this time of day,
  /// and skipped lately - the trait versions of the artist lists.
  final List<String> risingTraits;
  final List<String> dayPartTraits;
  final List<String> fadingTraits;

  /// Each artist's usual genre, to give online songs (which have no tags)
  /// their genre traits.
  final Map<String, String> artistGenres;

  /// [songTraits] of [song], filling its genre in from its artist.
  Set<String> traitsOf(OnlineSong song) => songTraits(
    title: song.title,
    album: song.album,
    artistGenre: artistGenres[song.artist?.trim()],
  );

  /// The best traits to search for, where taste is heading first, as
  /// queries ("hindi chill songs"). Languages only flavour other traits.
  List<String> traitQueries({int max = 3}) {
    final langs =
        (traitScores.entries.where((e) => e.key.startsWith('lang:')).toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .map((e) => languageWord(e.key));
    final language = langs.firstOrNull;
    final faded = fadingTraits.toSet();
    final ordered = <String>{
      ...risingTraits,
      ...dayPartTraits,
      ...(traitScores.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => e.key),
    }.where((tr) => !faded.contains(tr));
    return [
      for (final tr in ordered) ?traitQuery(tr, language: language),
    ].take(max).toList();
  }

  /// Rebuild when the time of day moves on: [dayPartArtists] is for then.
  bool isStaleAt(DateTime now) =>
      DayPart.fromHour(now.hour) != DayPart.fromHour(builtAt.hour);

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
    'rising': risingArtists,
    'dayPart': dayPartArtists,
    'fading': fadingArtists,
    'traits': traitScores,
    'risingTraits': risingTraits,
    'dayPartTraits': dayPartTraits,
    'fadingTraits': fadingTraits,
    'artistGenres': artistGenres,
  };

  factory TasteProfileSnapshot.fromJson(
    Map<String, dynamic> j,
  ) => TasteProfileSnapshot(
    builtAt: DateTime.fromMillisecondsSinceEpoch(j['builtAt'] as int? ?? 0),
    topArtists: [
      for (final a in (j['topArtists'] as List? ?? const [])) a.toString(),
    ],
    topOnlineIds: [
      for (final o in (j['topOnlineIds'] as List? ?? const [])) o.toString(),
    ],
    recentSearches: [
      for (final s in (j['recentSearches'] as List? ?? const [])) s.toString(),
    ],
    genres: [for (final g in (j['genres'] as List? ?? const [])) g.toString()],
    profiles: [
      for (final p in (j['profiles'] as List? ?? const []))
        if (p is Map) TasteProfileCluster.fromJson(p.cast<String, dynamic>()),
    ],
    artistScores: {
      for (final e in ((j['artistScores'] as Map?) ?? const {}).entries)
        e.key.toString(): (e.value as num).toDouble(),
    },
    risingArtists: _strings(j['rising']),
    dayPartArtists: _strings(j['dayPart']),
    fadingArtists: _strings(j['fading']),
    traitScores: {
      for (final e in ((j['traits'] as Map?) ?? const {}).entries)
        e.key.toString(): (e.value as num).toDouble(),
    },
    risingTraits: _strings(j['risingTraits']),
    dayPartTraits: _strings(j['dayPartTraits']),
    fadingTraits: _strings(j['fadingTraits']),
    artistGenres: {
      for (final e in ((j['artistGenres'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
  );

  static List<String> _strings(Object? raw) => [
    for (final a in (raw is List ? raw : const [])) a.toString(),
  ];
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

  Iterable<String> creditNames(String? artistName, String title) {
    if (artistName == null || artistName.trim().isEmpty) return const [];
    final names = splitArtistCredits(artistName, title).toSet();
    if (names.length > 1) names.remove(artistName.trim());
    return names.map((n) => n.trim()).where((n) => n.isNotEmpty);
  }

  void creditArtist(String? artistName, String title, double weight) {
    if (weight <= 0) return;
    for (final name in creditNames(artistName, title)) {
      artistScores.update(name, (v) => v + weight, ifAbsent: () => weight);
    }
  }

  // Listening patterns: the last week, this time of day, recent skips.
  final nowPart = DayPart.fromHour(current.hour);
  final weekArtists = <String, double>{};
  final weekPlays = <String, int>{};
  final partArtists = <String, double>{};
  final partPlays = <String, int>{};
  final skips = <String, int>{};
  final fullPlays = <String, int>{};
  // The same, per song trait (genre, mood, kind of recording, language).
  final traitScores = <String, double>{};
  final weekTraits = <String, double>{};
  final weekTraitPlays = <String, int>{};
  final partTraits = <String, double>{};
  final partTraitPlays = <String, int>{};
  final traitSkips = <String, int>{};
  final traitFull = <String, int>{};
  void creditTraits(Iterable<String> traits, double w) {
    for (final tr in traits) {
      traitScores.update(tr, (v) => v + w, ifAbsent: () => w);
    }
  }

  // Each artist's usual genre, so untagged (online) plays get one.
  final genreVotes = <String, Map<String, int>>{};
  void voteGenre(String? artist, String? genre) {
    final a = artist?.trim();
    final g = genre?.trim();
    if (a == null || a.isEmpty || g == null || g.isEmpty) return;
    genreVotes
        .putIfAbsent(a, () => {})
        .update(g, (v) => v + 1, ifAbsent: () => 1);
  }

  for (final s in songs) {
    voteGenre(s.artist, s.genre);
  }
  for (final e in events) {
    voteGenre(e.artist, e.genre);
  }
  final artistGenre = {
    for (final MapEntry(key: a, value: votes) in genreVotes.entries)
      a: (votes.entries.toList()..sort((x, y) => y.value.compareTo(x.value)))
          .first
          .key,
  };
  Set<String> traitsFor(String title, String? genre, String? artist) =>
      songTraits(
        title: title,
        genre: genre,
        artistGenre: artistGenre[artist?.trim()],
      );

  void bump<K>(Map<K, int> m, K k) =>
      m.update(k, (v) => v + 1, ifAbsent: () => 1);

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
      artistGenres
          .putIfAbsent(clean, () => {})
          .update(g, (v) => v + 1, ifAbsent: () => 1);
    }
    final script = UnicodeScript.detect(title);
    artistScripts
        .putIfAbsent(clean, () => {})
        .update(script, (v) => v + 1, ifAbsent: () => 1);
    if (path.startsWith('yt:')) {
      artistOnlineSongs.putIfAbsent(clean, () => []).add(path.substring(3));
    }
  }

  // 1. Process play events
  for (final e in events) {
    recordArtistMetadata(e.artist, e.songTitle, e.genre, e.songPath);
    final ageDays = current.difference(e.playedAt).inMinutes / 1440.0;
    final dur = e.durationMs ?? 0;
    final listened = e.listenedMs;
    // Still playing (listened time is topped up later): not a skip yet.
    if (listened == 0 && ageDays * 1440 < 15) continue;
    final names = creditNames(e.artist, e.songTitle);
    final traits = traitsFor(e.songTitle, e.genre, e.artist);

    if (dur > 0 && listened < 30000) {
      // Skip under 30s: -0.3 to song, 0 to artist
      songScores.update(e.songPath, (v) => v - 0.3, ifAbsent: () => -0.3);
      if (ageDays < 14) {
        for (final n in names) {
          bump(skips, n);
        }
        for (final tr in traits) {
          bump(traitSkips, tr);
        }
      }
    } else {
      final heard = dur > 0 && listened > 0
          ? (listened / dur).clamp(0.1, 1.0)
          : 0.5;
      final w = math.pow(0.5, ageDays / halfLifeDays) * heard;
      songScores.update(e.songPath, (v) => v + w, ifAbsent: () => w);
      creditArtist(e.artist, e.songTitle, w);
      creditTraits(traits, w);
      final inPart = DayPart.fromHour(e.playedAt.hour) == nowPart;
      for (final tr in traits) {
        if (ageDays < 14) bump(traitFull, tr);
        if (ageDays < 7) {
          weekTraits.update(tr, (v) => v + w, ifAbsent: () => w);
          bump(weekTraitPlays, tr);
        }
        if (ageDays < 30 && inPart) {
          partTraits.update(tr, (v) => v + w, ifAbsent: () => w);
          bump(partTraitPlays, tr);
        }
      }
      for (final n in names) {
        if (ageDays < 14) bump(fullPlays, n);
        if (ageDays < 7) {
          weekArtists.update(n, (v) => v + w, ifAbsent: () => w);
          bump(weekPlays, n);
        }
        if (ageDays < 30 && DayPart.fromHour(e.playedAt.hour) == nowPart) {
          partArtists.update(n, (v) => v + w, ifAbsent: () => w);
          bump(partPlays, n);
        }
      }
    }
  }

  // 2. Process songs (favorites, downloads, local collection)
  final localCounts = <String, int>{};
  for (final s in songs) {
    recordArtistMetadata(s.artist, s.title, s.genre, s.path);

    if (s.isFavorite) {
      songScores.update(
        s.path,
        (v) => v + likedBonus,
        ifAbsent: () => likedBonus,
      );
      creditArtist(s.artist, s.title, likedBonus);
      creditTraits(traitsFor(s.title, s.genre, s.artist), likedBonus);
    }
    if (s.isDownloaded) {
      songScores.update(
        s.path,
        (v) => v + downloadBonus,
        ifAbsent: () => downloadBonus,
      );
      creditArtist(s.artist, s.title, downloadBonus);
      creditTraits(traitsFor(s.title, s.genre, s.artist), downloadBonus);
    }

    if (!s.path.startsWith('yt:')) {
      var songCredit = localSongBase;
      if (current.difference(s.dateAdded).inDays < 30) {
        songCredit += recentLocalBonus;
      }
      songScores.update(
        s.path,
        (v) => v + songCredit,
        ifAbsent: () => songCredit,
      );

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

  // 4. Taste over time. Rising: a bigger share of this week's listening
  // than of the all-time score (which includes the library's weight).
  final allTotal = artistScores.values.fold<double>(0, (a, v) => a + v);
  final weekTotal = weekArtists.values.fold<double>(0, (a, v) => a + v);
  final rising =
      weekArtists.entries
          .where(
            (e) =>
                (weekPlays[e.key] ?? 0) >= 2 &&
                e.value / weekTotal >=
                    1.5 * (artistScores[e.key] ?? 0) / math.max(allTotal, 1e-9),
          )
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final risingArtists = rising.take(5).map((e) => e.key).toList();
  final dayPartArtists =
      (partArtists.entries.where((e) => (partPlays[e.key] ?? 0) >= 2).toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => e.key)
          .toList();
  // Skipped at least 3 times in two weeks, and far more than heard.
  final fadingArtists = [
    for (final e in skips.entries)
      if (e.value >= 3 && e.value > 2 * (fullPlays[e.key] ?? 0)) e.key,
  ];
  final fadingLower = {for (final a in fadingArtists) a.toLowerCase()};

  // Mood chips picked on Home count as stated moods, fading like plays.
  for (final (chip, at) in taste.moodPicks) {
    final ageDays = current.difference(at).inMinutes / 1440.0;
    final w = math.pow(0.5, ageDays / halfLifeDays).toDouble();
    final moods = moodsIn(chip);
    creditTraits(
      moods.isEmpty
          ? ['mood:${chip.trim().toLowerCase()}']
          : [for (final m in moods) 'mood:$m'],
      w,
    );
  }

  // Trait trends, as for artists.
  final traitTotal = traitScores.values.fold<double>(0, (a, v) => a + v);
  final weekTraitTotal = weekTraits.values.fold<double>(0, (a, v) => a + v);
  final risingTraits =
      (weekTraits.entries
              .where(
                (e) =>
                    (weekTraitPlays[e.key] ?? 0) >= 2 &&
                    e.value / weekTraitTotal >=
                        1.5 *
                            (traitScores[e.key] ?? 0) /
                            math.max(traitTotal, 1e-9),
              )
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(6)
          .map((e) => e.key)
          .toList();
  final dayPartTraits =
      (partTraits.entries
              .where((e) => (partTraitPlays[e.key] ?? 0) >= 2)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(6)
          .map((e) => e.key)
          .toList();
  final fadingTraits = [
    for (final e in traitSkips.entries)
      if (e.value >= 3 && e.value > 2 * (traitFull[e.key] ?? 0)) e.key,
  ];

  // 5. Stated taste artists; rising ones lead, fading ones drop out.
  final playedArtists = <String>[
    ...risingArtists,
    ...(artistScores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key)
        .where((a) => !risingArtists.contains(a)),
  ].where((a) => !fadingLower.contains(a.toLowerCase())).take(8).toList();

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
  final topOnlineIds =
      (songScores.entries
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
      dominantGenre =
          (gMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    } else if (taste.genres.isNotEmpty) {
      dominantGenre = taste.genres.first;
    }

    final sMap = artistScripts[artist] ?? {};
    var dominantScript = UnicodeScript.detect(artist);
    if (sMap.isNotEmpty) {
      dominantScript =
          (sMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
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
      gMap.forEach(
        (g, count) => cg.update(g, (v) => v + count, ifAbsent: () => count),
      );
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
    artistsInCluster.sort(
      (a, b) => (artistScores[b] ?? 0.0).compareTo(artistScores[a] ?? 0.0),
    );

    final gMap = clusterGenres[entry.key] ?? {};
    final topG =
        (gMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
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
        topOnlineSeedIds: (clusterOnlineSongs[entry.key] ?? {})
            .take(5)
            .toList(),
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
    risingArtists: risingArtists,
    dayPartArtists: dayPartArtists,
    fadingArtists: fadingArtists,
    traitScores: traitScores,
    risingTraits: risingTraits,
    dayPartTraits: dayPartTraits,
    fadingTraits: fadingTraits,
    artistGenres: artistGenre,
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
  Set<String> lower(List<String> l) => {
    for (final a in l) a.trim().toLowerCase(),
  };
  final rising = lower(profile.risingArtists);
  final dayPart = lower(profile.dayPartArtists);
  final fading = lower(profile.fadingArtists);
  final maxTrait = profile.traitScores.values.fold<double>(
    1.0,
    (m, v) => math.max(m, v),
  );
  final risingTraits = profile.risingTraits.toSet();
  final partTraits = profile.dayPartTraits.toSet();
  final fadingTraits = profile.fadingTraits.toSet();

  final maxScore = profile.artistScores.values.fold<double>(
    1.0,
    (m, v) => math.max(m, v),
  );

  final scoredCandidates =
      <({OnlineSong song, double score, bool isProfileArtist})>[];
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

    final isProfile =
        artistLower != null &&
        !fading.contains(artistLower) &&
        (profileTopArtistsLower.contains(artistLower) ||
            rising.contains(artistLower));
    final profileMatch = isProfile ? 0.5 : 0.0;
    final heardPenalty = recentPaths.contains(song.path) ? 1.0 : 0.0;
    // Where taste is heading now, and what fits this time of day.
    final trend =
        (rising.contains(artistLower) ? 0.4 : 0.0) +
        (dayPart.contains(artistLower) ? 0.25 : 0.0) -
        (fading.contains(artistLower) ? 0.6 : 0.0);

    // What the song is: its genre, mood, kind of recording and language,
    // against what the user plays (and lately skips) of each.
    final traits = profile.traitsOf(song);
    var traitFit = 0.0;
    if (traits.isNotEmpty) {
      // Language is near-universal, so it counts on its own; the rest add
      // up (two strong matches fill it) rather than average, so a song
      // with more of what the user likes outranks one with less.
      var lang = 0.0;
      var other = 0.0;
      for (final tr in traits) {
        final fit = ((profile.traitScores[tr] ?? 0) / maxTrait).clamp(0.0, 1.0);
        if (tr.startsWith('lang:')) {
          lang = math.max(lang, fit);
        } else {
          other += fit;
        }
      }
      traitFit = 0.25 * lang + 0.5 * math.min(1.0, other / 2);
      if (traits.any(risingTraits.contains)) traitFit += 0.2;
      if (traits.any(partTraits.contains)) traitFit += 0.15;
      if (traits.any(fadingTraits.contains)) traitFit -= 0.4;
    }

    final score =
        artistAffinity + profileMatch + trend + traitFit - heardPenalty;
    scoredCandidates.add((
      song: song,
      score: score,
      isProfileArtist: isProfile,
    ));
  }

  final profileSongs =
      scoredCandidates.where((item) => item.isProfileArtist).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  final exploreSongs =
      scoredCandidates.where((item) => !item.isProfileArtist).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  // 20% of slots held back for exploration
  final exploreCount = (limit * 0.2).round();
  final profileCount = limit - exploreCount;

  final selected = <OnlineSong>[];
  final selectedIds = <String>{};

  void pick(
    List<({OnlineSong song, double score, bool isProfileArtist})> list,
    int n,
  ) {
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
