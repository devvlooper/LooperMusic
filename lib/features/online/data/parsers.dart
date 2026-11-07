// InnerTube (music.youtube.com, WEB_REMIX) response parsers.
// verified November 2026 against live responses; fixtures in
// test/fixtures/innertube/. Change a parser only after capturing the new
// shape - never from memory.
//
// Rules (docs/online/09-data-display.md): artist/album are identified by
// their links, never by position; a field the response does not name stays
// null (never "Unknown").

import 'package:looper_player/features/library/domain/models/models.dart';

/// An online song as listed by search, radio, home or a collection page.
class OnlineSong {
  const OnlineSong({
    required this.videoId,
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.thumbnail,
    this.videoType,
    this.year,
  });

  final String videoId;
  final String title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final String? thumbnail;

  /// `MUSIC_VIDEO_TYPE_ATV` (the album audio), `_OMV` (official video),
  /// `_UGC` (a fan upload) or `_PODCAST_EPISODE`; null when not stated.
  final String? videoType;

  /// Release year, only where the response states it.
  final int? year;

  /// The album recording: its timing matches album-timed lyrics.
  bool get isAlbumAudio => videoType == videoTypeAlbum;

  String get path => 'yt:$videoId';

  /// An unsaved [Song] row for this song (the path is its identity).
  Song toSong() => Song()
    ..path = path
    ..title = title
    ..artist = artist
    ..album = album
    ..duration = durationMs
    ..artPath = thumbnail
    ..year = year
    ..dateAdded = DateTime.now();

  Map<String, dynamic> toJson() => {
    'v': videoId,
    't': title,
    'a': artist,
    'al': album,
    'd': durationMs,
    'th': thumbnail,
    if (videoType != null) 'vt': videoType,
    if (year != null) 'y': year,
  };

  static OnlineSong? fromJson(Object? j) {
    if (j is! Map || j['v'] is! String || j['t'] is! String) return null;
    return OnlineSong(
      videoId: j['v'] as String,
      title: j['t'] as String,
      artist: j['a'] as String?,
      album: j['al'] as String?,
      durationMs: j['d'] as int?,
      thumbnail: j['th'] as String?,
      videoType: j['vt'] as String?,
      year: j['y'] as int?,
    );
  }
}

const videoTypeAlbum = 'MUSIC_VIDEO_TYPE_ATV';
const videoTypeFanUpload = 'MUSIC_VIDEO_TYPE_UGC';
const videoTypePodcast = 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE';

enum CollectionKind { album, playlist, artist }

/// An album, playlist or artist card.
class OnlineCollection {
  const OnlineCollection({
    required this.browseId,
    required this.title,
    required this.kind,
    this.subtitle,
    this.thumbnail,
  });

  final String browseId;
  final String title;
  final CollectionKind kind;
  final String? subtitle;
  final String? thumbnail;

  Map<String, dynamic> toJson() => {
    'b': browseId,
    't': title,
    'k': kind.name,
    's': subtitle,
    'th': thumbnail,
  };

  static OnlineCollection? fromJson(Object? j) {
    if (j is! Map || j['b'] is! String || j['t'] is! String) return null;
    final kind = CollectionKind.values.where((k) => k.name == j['k']);
    if (kind.isEmpty) return null;
    return OnlineCollection(
      browseId: j['b'] as String,
      title: j['t'] as String,
      kind: kind.first,
      subtitle: j['s'] as String?,
      thumbnail: j['th'] as String?,
    );
  }
}

/// A titled row of songs and/or cards.
class OnlineShelf {
  const OnlineShelf(
    this.title, {
    this.songs = const [],
    this.collections = const [],
    this.moreBrowseId,
    this.moreParams,
  });
  final String title;
  final List<OnlineSong> songs;
  final List<OnlineCollection> collections;

  /// Where "View all" opens the whole list: the shelf's own "More" link,
  /// a library list, or a playlist (`VL...`). Null: the row is the list.
  final String? moreBrowseId;
  final String? moreParams;

  bool get isEmpty => songs.isEmpty && collections.isEmpty;

  Map<String, dynamic> toJson() => {
    't': title,
    's': [for (final s in songs) s.toJson()],
    'c': [for (final c in collections) c.toJson()],
    if (moreBrowseId != null) 'mb': moreBrowseId,
    if (moreParams != null) 'mp': moreParams,
  };

  static OnlineShelf? fromJson(Object? j) {
    if (j is! Map || j['t'] is! String) return null;
    return OnlineShelf(
      j['t'] as String,
      songs: [
        for (final s in (j['s'] as List? ?? const [])) ?OnlineSong.fromJson(s),
      ],
      collections: [
        for (final c in (j['c'] as List? ?? const []))
          ?OnlineCollection.fromJson(c),
      ],
      moreBrowseId: j['mb'] as String?,
      moreParams: j['mp'] as String?,
    );
  }
}

/// An album, playlist or artist page: header, its main song list and the
/// carousels under it.
class OnlinePage {
  const OnlinePage({
    required this.title,
    this.subtitle,
    this.thumbnail,
    this.songs = const [],
    this.shelves = const [],
    this.continuation,
  });
  final String title;
  final String? subtitle;
  final String? thumbnail;
  final List<OnlineSong> songs;
  final List<OnlineShelf> shelves;
  final String? continuation;
}

// ---------------------------------------------------------------- helpers

/// Every object stored under [key] anywhere below [node], in document order.
List<Map<String, dynamic>> findAll(Object? node, String key) {
  final out = <Map<String, dynamic>>[];
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == key && e.value is Map) {
          out.add((e.value as Map).cast<String, dynamic>());
        }
        walk(e.value);
      }
    } else if (n is List) {
      for (final v in n) {
        walk(v);
      }
    }
  }

  walk(node);
  return out;
}

Object? _at(Object? node, List<Object> path) {
  var n = node;
  for (final p in path) {
    if (p is String && n is Map) {
      n = n[p];
    } else if (p is int && n is List && p < n.length) {
      n = n[p];
    } else {
      return null;
    }
  }
  return n;
}

List<Map<String, dynamic>> _runs(Object? text) => [
  for (final r in (_at(text, ['runs']) as List? ?? const []))
    if (r is Map) r.cast<String, dynamic>(),
];

/// Text of a `{simpleText}` or `{runs: [...]}` object.
String? runText(Object? text) {
  final simple = _at(text, ['simpleText']);
  if (simple is String) return simple.isEmpty ? null : simple;
  final joined = _runs(text).map((r) => r['text'] ?? '').join();
  return joined.isEmpty ? null : joined;
}

String? _pageType(Map<String, dynamic> run) =>
    _at(run, [
          'navigationEndpoint',
          'browseEndpoint',
          'browseEndpointContextSupportedConfigs',
          'browseEndpointContextMusicConfig',
          'pageType',
        ])
        as String?;

String? _browseId(Map<String, dynamic> run) =>
    _at(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?;

bool _isArtistRun(Map<String, dynamic> r) {
  final type = _pageType(r);
  if (type != null) {
    return type == 'MUSIC_PAGE_TYPE_ARTIST' ||
        type == 'MUSIC_PAGE_TYPE_USER_CHANNEL';
  }
  return _browseId(r)?.startsWith('UC') ?? false;
}

bool _isAlbumRun(Map<String, dynamic> r) {
  final type = _pageType(r);
  if (type != null) return type == 'MUSIC_PAGE_TYPE_ALBUM';
  return _browseId(r)?.startsWith('MPRE') ?? false;
}

/// The row's own `musicVideoType` (its play link first: menu items carry
/// other links).
String? _videoType(Map<String, dynamic> r) {
  const cfg = [
    'watchEndpointMusicSupportedConfigs',
    'watchEndpointMusicConfig',
  ];
  final own = _at(r, [
    'navigationEndpoint',
    'watchEndpoint',
    ...cfg,
    'musicVideoType',
  ]);
  if (own is String) return own;
  for (final area in [r['overlay'], r['flexColumns']]) {
    final t = findAll(
      area,
      'watchEndpointMusicConfig',
    ).firstOrNull?['musicVideoType'];
    if (t is String) return t;
  }
  return null;
}

final _year = RegExp(r'^(19|20)\d{2}$');

final _durationRe = RegExp(r'^(\d+):(\d{2})(?::(\d{2}))?$');

/// "3:45" / "1:02:03" to milliseconds.
int? parseDuration(String? text) {
  final m = _durationRe.firstMatch(text?.trim() ?? '');
  if (m == null) return null;
  final a = int.parse(m[1]!), b = int.parse(m[2]!);
  final c = m[3] == null ? null : int.parse(m[3]!);
  final secs = c == null ? a * 60 + b : a * 3600 + b * 60 + c;
  return secs * 1000;
}

/// The largest thumbnail, upsized when it is a resizable Google image.
String? bestThumbnail(Object? node) {
  final lists = findAll({'x': node}, 'thumbnail');
  List? thumbs;
  for (final t in lists) {
    final l = t['thumbnails'];
    if (l is List && l.isNotEmpty) {
      thumbs = l;
      break;
    }
  }
  thumbs ??= _at(node, ['thumbnails']) as List?;
  if (thumbs == null || thumbs.isEmpty) return null;
  final url = (thumbs.last as Map?)?['url'] as String?;
  if (url == null) return null;
  final big = url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
  return big.startsWith('//') ? 'https:$big' : big;
}

/// Artist names from runs, joined the way the response joins them
/// (", " / " & "), stopping at the first " • " separator after an artist.
String? _artistsFrom(List<Map<String, dynamic>> runs) {
  final names = [
    for (final r in runs)
      if (_isArtistRun(r)) r['text'] as String,
  ];
  return names.isEmpty ? null : names.join(', ');
}

// ----------------------------------------------------------------- items

/// A `musicResponsiveListItemRenderer` row as a song, or null when the row
/// is not playable (an artist or album row).
OnlineSong? songFromListItem(
  Map<String, dynamic> r, {
  String? albumFallback,
  String? thumbFallback,
  String? artistFallback,
}) {
  final videoId =
      _at(r, ['playlistItemData', 'videoId']) as String? ??
      findAll(r['overlay'], 'watchEndpoint').firstOrNull?['videoId']
          as String? ??
      _at(r, ['navigationEndpoint', 'watchEndpoint', 'videoId']) as String?;
  if (videoId == null) return null;
  final type = _videoType(r);
  // Podcast "episodes" are channel reuploads, not songs.
  if (type == videoTypePodcast) return null;

  final columns = [
    for (final c in (r['flexColumns'] as List? ?? const []))
      _at(c, ['musicResponsiveListItemFlexColumnRenderer', 'text']),
  ];
  if (columns.isEmpty) return null;
  final title = runText(columns.first);
  if (title == null) return null;

  final restRuns = [for (final c in columns.skip(1)) ..._runs(c)];
  final albumRun = restRuns.where(_isAlbumRun).firstOrNull;
  int? duration;
  for (final c in (r['fixedColumns'] as List? ?? const [])) {
    duration ??= parseDuration(
      runText(_at(c, ['musicResponsiveListItemFixedColumnRenderer', 'text'])),
    );
  }
  for (final run in restRuns) {
    duration ??= parseDuration(run['text'] as String?);
  }

  return OnlineSong(
    videoId: videoId,
    title: title,
    artist: _artistsFrom(restRuns) ?? artistFallback,
    album: albumRun?['text'] as String? ?? albumFallback,
    durationMs: duration,
    thumbnail: bestThumbnail(r['thumbnail']) ?? thumbFallback,
    videoType: type,
  );
}

CollectionKind? _kindFor(String? pageType, String browseId) {
  switch (pageType) {
    case 'MUSIC_PAGE_TYPE_ALBUM':
      return CollectionKind.album;
    case 'MUSIC_PAGE_TYPE_PLAYLIST':
      return CollectionKind.playlist;
    case 'MUSIC_PAGE_TYPE_ARTIST':
      return CollectionKind.artist;
  }
  if (pageType != null) return null;
  if (browseId.startsWith('MPRE')) return CollectionKind.album;
  if (browseId.startsWith('VL')) return CollectionKind.playlist;
  if (browseId.startsWith('UC')) return CollectionKind.artist;
  return null;
}

OnlineCollection? _collection(
  Map<String, dynamic>? endpointHolder,
  String? title,
  String? subtitle,
  Object? thumbNode,
) {
  final browse = _at(endpointHolder, ['navigationEndpoint', 'browseEndpoint']);
  if (browse is! Map || title == null) return null;
  final id = browse['browseId'] as String?;
  if (id == null) return null;
  final kind = _kindFor(
    _at(browse, [
          'browseEndpointContextSupportedConfigs',
          'browseEndpointContextMusicConfig',
          'pageType',
        ])
        as String?,
    id,
  );
  if (kind == null) return null;
  return OnlineCollection(
    browseId: id,
    title: title,
    kind: kind,
    subtitle: subtitle,
    thumbnail: bestThumbnail(thumbNode),
  );
}

/// A list row that opens an album/playlist/artist (search results).
OnlineCollection? collectionFromListItem(Map<String, dynamic> r) {
  final columns = [
    for (final c in (r['flexColumns'] as List? ?? const []))
      runText(_at(c, ['musicResponsiveListItemFlexColumnRenderer', 'text'])),
  ];
  return _collection(
    r,
    columns.firstOrNull,
    columns.skip(1).whereType<String>().join(' • ').ifEmptyNull,
    r['thumbnail'],
  );
}

/// A `musicTwoRowItemRenderer` card: a song when it plays directly,
/// otherwise a collection.
(OnlineSong?, OnlineCollection?) _twoRow(Map<String, dynamic> r) {
  final title = runText(r['title']);
  final subtitleRuns = _runs(r['subtitle']);
  final subtitle = runText(r['subtitle']);
  final videoId =
      _at(r, ['navigationEndpoint', 'watchEndpoint', 'videoId']) as String?;
  if (videoId != null && title != null) {
    return (
      OnlineSong(
        videoId: videoId,
        title: title,
        artist: _artistsFrom(subtitleRuns),
        thumbnail: bestThumbnail(r['thumbnailRenderer']),
      ),
      null,
    );
  }
  return (null, _collection(r, title, subtitle, r['thumbnailRenderer']));
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

// ----------------------------------------------------------------- pages

OnlineShelf _shelfOf(
  String title,
  List contents, {
  String? moreBrowseId,
  String? moreParams,
}) {
  final songs = <OnlineSong>[];
  final cards = <OnlineCollection>[];
  for (final item in contents) {
    final list = _at(item, ['musicResponsiveListItemRenderer']);
    final two = _at(item, ['musicTwoRowItemRenderer']);
    if (list is Map) {
      final row = list.cast<String, dynamic>();
      final s = songFromListItem(row);
      if (s != null) {
        songs.add(s);
      } else {
        final c = collectionFromListItem(row);
        if (c != null) cards.add(c);
      }
    } else if (two is Map) {
      final (s, c) = _twoRow(two.cast<String, dynamic>());
      if (s != null) songs.add(s);
      if (c != null) cards.add(c);
    }
  }
  return OnlineShelf(
    title,
    songs: songs,
    collections: cards,
    moreBrowseId: moreBrowseId,
    moreParams: moreParams,
  );
}

OnlineShelf _carousel(Map<String, dynamic> s) {
  final header =
      _at(s, ['header', 'musicCarouselShelfBasicHeaderRenderer']) ??
      _at(s, ['header', 'musicImmersiveCarouselShelfBasicHeaderRenderer']);
  final more = _at(header, [
    'moreContentButton',
    'buttonRenderer',
    'navigationEndpoint',
    'browseEndpoint',
  ]);
  return _shelfOf(
    runText(_at(header, ['title'])) ?? '',
    s['contents'] as List? ?? const [],
    moreBrowseId: _at(more, ['browseId']) as String?,
    moreParams: _at(more, ['params']) as String?,
  );
}

/// Carousels (home, artist page), in page order. Empty shelves are dropped.
List<OnlineShelf> parseShelves(Map<String, dynamic> json) {
  final out = <OnlineShelf>[];
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        final v = e.value;
        if ((e.key == 'musicCarouselShelfRenderer' ||
                e.key == 'musicImmersiveCarouselShelfRenderer') &&
            v is Map) {
          out.add(_carousel(v.cast<String, dynamic>()));
        } else {
          walk(v);
        }
      }
    } else if (n is List) {
      n.forEach(walk);
    }
  }

  walk(json);
  return out.where((s) => !s.isEmpty && s.title.isNotEmpty).toList();
}

/// Every song and card on a list page (library grids and shelves, a
/// playlist, a "More" page, or one of their continuation pages).
OnlineShelf parseListItems(Map<String, dynamic> json, String title) =>
    _shelfOf(title, [
      for (final k in const [
        'musicResponsiveListItemRenderer',
        'musicTwoRowItemRenderer',
      ])
        for (final r in findAll(json, k)) {k: r},
    ]);

/// The next-page token of a list page, old or new style.
String? listContinuation(Map<String, dynamic> json) =>
    homeContinuation(json) ??
    findAll(json, 'continuationCommand').firstOrNull?['token'] as String?;

/// A mood/genre chip on top of home: tapping it reloads home with [params].
class OnlineMood {
  const OnlineMood(this.title, this.params);
  final String title;
  final String params;

  Map<String, dynamic> toJson() => {'t': title, 'p': params};

  static OnlineMood? fromJson(Object? j) {
    if (j is! Map || j['t'] is! String || j['p'] is! String) return null;
    return OnlineMood(j['t'] as String, j['p'] as String);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnlineMood &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          params == other.params;

  @override
  int get hashCode => Object.hash(title, params);
}

List<OnlineMood> parseMoods(Map<String, dynamic> json) => [
  for (final c in findAll(json, 'chipCloudChipRenderer'))
    if ((
          runText(c['text']) ?? runText(c['chipText']),
          _at(c, ['navigationEndpoint', 'browseEndpoint']),
        )
        case (final String title, final Map browse)
        when browse['params'] is String)
      OnlineMood(title, browse['params'] as String),
];

/// Continuation token for more home sections.
String? homeContinuation(Map<String, dynamic> json) =>
    findAll(json, 'nextContinuationData').firstOrNull?['continuation']
        as String?;

/// Song search (Songs filter), page one or a continuation page.
(List<OnlineSong>, String?) parseSongSearch(Map<String, dynamic> json) {
  final shelf =
      _at(json, ['continuationContents', 'musicShelfContinuation']) as Map? ??
      findAll(json, 'musicShelfRenderer').firstOrNull;
  if (shelf == null) return (const <OnlineSong>[], null);
  final songs = [
    for (final c in (shelf['contents'] as List? ?? const []))
      if (_at(c, ['musicResponsiveListItemRenderer']) case final Map r)
        ?songFromListItem(r.cast<String, dynamic>()),
  ];
  final token =
      _at(shelf, ['continuations', 0, 'nextContinuationData', 'continuation'])
          as String?;
  return (songs, token);
}

/// Album / artist / playlist rows from a filtered search.
List<OnlineCollection> parseCollectionSearch(Map<String, dynamic> json) => [
  for (final r in findAll(json, 'musicResponsiveListItemRenderer'))
    ?collectionFromListItem(r),
];

/// Radio ("up next") rows from `next`. Podcast "episodes" (channel
/// reuploads) are dropped.
List<OnlineSong> parseRadio(Map<String, dynamic> json) {
  final out = <OnlineSong>[];
  for (final r in findAll(json, 'playlistPanelVideoRenderer')) {
    final song = _panelSong(r);
    if (song != null && song.videoType != videoTypePodcast) out.add(song);
  }
  return out;
}

/// The song `next` was asked about, with album and year when the response
/// states them (album tracks do; fan uploads name only a channel).
OnlineSong? parseSongDetails(Map<String, dynamic> json, String videoId) {
  for (final r in findAll(json, 'playlistPanelVideoRenderer')) {
    if (r['videoId'] == videoId) return _panelSong(r);
  }
  return null;
}

OnlineSong? _panelSong(Map<String, dynamic> r) {
  final id = r['videoId'] as String?;
  final title = runText(r['title']);
  if (id == null || title == null) return null;
  final byline = _runs(r['longBylineText']);
  // Before the first " • " is the credit; after it, views/likes/album/year.
  final cut = byline.indexWhere((x) => (x['text'] as String).trim() == '•');
  final credit = cut == -1 ? byline : byline.sublist(0, cut);
  final rest = cut == -1 ? const <Map<String, dynamic>>[] : byline.sublist(cut);
  final yearText = rest
      .map((x) => (x['text'] as String).trim())
      .where(_year.hasMatch)
      .firstOrNull;
  return OnlineSong(
    videoId: id,
    title: title,
    artist:
        _artistsFrom(credit) ?? credit.map((x) => x['text']).join().ifEmptyNull,
    album: byline.where(_isAlbumRun).firstOrNull?['text'] as String?,
    durationMs: parseDuration(runText(r['lengthText'])),
    thumbnail: bestThumbnail(r['thumbnail']),
    videoType: _videoType(r),
    year: yearText == null ? null : int.parse(yearText),
  );
}

/// Album, playlist or artist page.
OnlinePage parsePage(Map<String, dynamic> json) {
  final header =
      findAll(json, 'musicResponsiveHeaderRenderer').firstOrNull ??
      findAll(json, 'musicImmersiveHeaderRenderer').firstOrNull ??
      findAll(json, 'musicVisualHeaderRenderer').firstOrNull ??
      findAll(json, 'musicDetailHeaderRenderer').firstOrNull;
  final title = runText(header?['title']) ?? '';
  final thumb = bestThumbnail(header?['thumbnail']);
  final straplineArtist = runText(header?['straplineTextOne']);
  final isAlbum =
      findAll(json, 'musicResponsiveHeaderRenderer').isNotEmpty &&
      findAll(json, 'musicPlaylistShelfRenderer').isEmpty;

  final shelf =
      findAll(json, 'musicPlaylistShelfRenderer').firstOrNull ??
      findAll(json, 'musicShelfRenderer').firstOrNull;
  final songs = <OnlineSong>[];
  String? token;
  for (final c in (shelf?['contents'] as List? ?? const [])) {
    if (_at(c, ['musicResponsiveListItemRenderer']) case final Map r) {
      final s = songFromListItem(
        r.cast<String, dynamic>(),
        albumFallback: isAlbum ? title : null,
        thumbFallback: thumb,
        artistFallback: straplineArtist,
      );
      if (s != null) songs.add(s);
    }
    token ??=
        _at(c, [
              'continuationItemRenderer',
              'continuationEndpoint',
              'continuationCommand',
              'token',
            ])
            as String?;
  }
  token ??=
      _at(shelf, ['continuations', 0, 'nextContinuationData', 'continuation'])
          as String?;

  return OnlinePage(
    title: title,
    subtitle: runText(header?['subtitle']) ?? straplineArtist,
    thumbnail: thumb,
    songs: songs,
    shelves: parseShelves(json),
    continuation: token,
  );
}

/// More rows of a long playlist. Later pages answer in a different
/// container than page one (Koda scar: playlists stopped at 100 songs).
(List<OnlineSong>, String?) parsePageContinuation(
  Map<String, dynamic> json, {
  String? thumbFallback,
}) {
  final items =
      _at(json, [
            'onResponseReceivedActions',
            0,
            'appendContinuationItemsAction',
            'continuationItems',
          ])
          as List? ??
      _at(json, [
            'continuationContents',
            'musicPlaylistShelfContinuation',
            'contents',
          ])
          as List? ??
      const [];
  final songs = <OnlineSong>[];
  String? token;
  for (final c in items) {
    if (_at(c, ['musicResponsiveListItemRenderer']) case final Map r) {
      final s = songFromListItem(
        r.cast<String, dynamic>(),
        thumbFallback: thumbFallback,
      );
      if (s != null) songs.add(s);
    }
    token ??=
        _at(c, [
              'continuationItemRenderer',
              'continuationEndpoint',
              'continuationCommand',
              'token',
            ])
            as String?;
  }
  return (songs, token);
}

/// Query completions.
List<String> parseSuggestions(Map<String, dynamic> json) => [
  for (final s in findAll(json, 'searchSuggestionRenderer'))
    ?runText(s['suggestion']),
];

/// The signed-in name from `account/account_menu`, or null when YouTube
/// answered as signed out (no active account header).
String? parseAccountName(Map<String, dynamic> json) {
  final header = findAll(json, 'activeAccountHeaderRenderer').firstOrNull;
  return header == null ? null : runText(header['accountName']) ?? '';
}

/// The lyrics tab's browse id from a `next` answer (`MPLY...`), or null
/// when YouTube has no lyrics for the song (the tab has no endpoint then).
String? parseLyricsBrowseId(Map<String, dynamic> json) {
  for (final tab in findAll(json, 'tabRenderer')) {
    final id = _at(tab, ['endpoint', 'browseEndpoint', 'browseId']);
    if (id is String && id.startsWith('MPLY')) return id;
  }
  return null;
}

/// Plain lyrics text from the lyrics tab's browse answer.
String? parseLyrics(Map<String, dynamic> json) => runText(
  findAll(json, 'musicDescriptionShelfRenderer').firstOrNull?['description'],
);
