import 'package:looper_player/features/online/data/taste_profile_engine.dart';

/// What a song is beyond its artist, as `kind:value` traits the taste
/// profile learns like artists:
/// - `genre:` from its tags (or, for online songs with none, the artist's
///   usual genre),
/// - `mood:` from mood words in its title, album and genre,
/// - `type:` the kind of recording (remix, live, lofi, slowed, ...),
/// - `lang:` the script its title is written in.
Set<String> songTraits({
  required String title,
  String? genre,
  String? album,
  String? artistGenre,
}) {
  final traits = <String>{};
  final tags = genreTags(genre ?? artistGenre);
  for (final g in tags) {
    traits.add('genre:$g');
  }
  final text = '$title ${album ?? ''} ${tags.join(' ')}'.toLowerCase();
  for (final MapEntry(key: type, value: pattern) in _types.entries) {
    if (pattern.hasMatch(text)) traits.add('type:$type');
  }
  for (final mood in moodsIn(text)) {
    traits.add('mood:$mood');
  }
  final script = UnicodeScript.detect(title);
  if (script != UnicodeScript.other) traits.add('lang:${script.label}');
  return traits;
}

/// A genre tag split into its parts, lower case: "Pop; Dance/EDM" gives
/// pop, dance, edm. `&` is kept: "R&B" is one genre.
List<String> genreTags(String? genre) {
  if (genre == null) return const [];
  return {
    for (final part in genre.toLowerCase().split(RegExp(r'\s*[;,/|]\s*')))
      if (part.trim().isNotEmpty) _genreAlias[part.trim()] ?? part.trim(),
  }.toList();
}

/// Canonical moods named by [text] (a title, a mood chip, a genre).
Set<String> moodsIn(String text) {
  final t = text.toLowerCase();
  return {
    for (final MapEntry(key: mood, value: pattern) in _moods.entries)
      if (pattern.hasMatch(t)) mood,
  };
}

/// Words for a search query that finds more songs with [trait], or null
/// when the trait is no good as a query (a bare language).
String? traitQuery(String trait, {String? language}) {
  final i = trait.indexOf(':');
  if (i < 0) return null;
  final kind = trait.substring(0, i);
  final value = trait.substring(i + 1);
  final lang = language == null ? '' : '$language ';
  return switch (kind) {
    'genre' || 'mood' => '$lang$value songs',
    'type' => '$lang${_typeQuery[value] ?? value} songs',
    _ => null,
  };
}

/// The language people search in for a script trait (`lang:Devanagari`
/// gives hindi), or null for Latin and unknown scripts.
String? languageWord(String trait) => switch (trait) {
  'lang:Devanagari' => 'hindi',
  'lang:Arabic' => 'arabic',
  'lang:Hangul' => 'korean',
  'lang:Kana/Han' => 'japanese',
  'lang:Cyrillic' => 'russian',
  _ => null,
};

RegExp _w(String words) => RegExp('\\b(?:$words)\\b');

final _types = <String, RegExp>{
  'remix': _w(r'remix|rmx|edit mix|bootleg|vip mix'),
  'live': _w(r'live|concert|live at|unplugged session'),
  'acoustic': _w(r'acoustic|unplugged|stripped'),
  'lofi': _w(r'lo-?fi'),
  'slowed': _w(r'slowed|reverb'),
  'sped-up': _w(r'sped up|speed up|nightcore'),
  'instrumental': _w(r'instrumental|karaoke|backing track|bgm'),
  'cover': _w(r'cover|covered by|tribute'),
  'mashup': _w(r'mashup|medley|megamix'),
  'remaster': _w(r'remaster(?:ed)?'),
  'bass-boosted': _w(r'bass boosted|8d audio|8d'),
};

const _typeQuery = {
  'slowed': 'slowed reverb',
  'sped-up': 'sped up',
  'bass-boosted': 'bass boosted',
  'remaster': 'remastered',
};

final _moods = <String, RegExp>{
  'chill': _w(r'chill|chillout|lo-?fi|relax\w*|calm|ambient|mellow|sleep'),
  'sad': _w(r'sad|broken|heartbreak|cry\w*|tears|alone|lonely|dard|tanha'),
  'romantic': _w(r'love|romantic|romance|ishq|pyaar|pyar|mohabbat|valentine'),
  'party': _w(r'party|dance|club|edm|house|disco|dj|banger'),
  'workout': _w(r'workout|gym|pump|phonk|hardstyle|metal|motivation\w*'),
  'focus': _w(r'focus|study|piano|classical|meditation|concentration'),
  'happy': _w(r'happy|feel good|good vibes|sunshine|summer'),
  'devotional': _w(r'bhajan|aarti|devotional|gospel|worship|qawwali|kirtan'),
};

const _genreAlias = {
  'hip hop': 'hip-hop',
  'hiphop': 'hip-hop',
  'rap': 'hip-hop',
  'rnb': 'r&b',
  'r and b': 'r&b',
  'electronic dance music': 'edm',
  'lo-fi': 'lofi',
  'lo fi': 'lofi',
  'bollywood music': 'bollywood',
  'filmi': 'bollywood',
};
