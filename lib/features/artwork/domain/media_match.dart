/// Strict yes/no matching for animated artwork (doc 26 §2-§3.1).
/// "A canvas from another song is a bug, while no canvas is fine."
library;

// Latin-1 Supplement and Latin Extended-A only; other scripts compare as-is.
const Map<String, String> _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'ð': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'ħ': 'h',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ĩ': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ı': 'i',
  'ĳ': 'ij',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ŀ': 'l',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ŉ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ŕ': 'r',
  'ŗ': 'r',
  'ř': 'r',
  'ś': 's',
  'ŝ': 's',
  'ş': 's',
  'š': 's',
  'ß': 'ss',
  'ţ': 't',
  'ť': 't',
  'ŧ': 't',
  'þ': 'th',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ŵ': 'w',
  'ý': 'y',
  'ÿ': 'y',
  'ŷ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'ſ': 's',
};

/// Lowercase and fold Latin accents (é → e, ß → ss).
String foldText(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

final _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final _dashTail = RegExp(r'\s+[-–—]\s+.*$');
final _nonAlnum = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Title (or album) key: folded, brackets and ` - …` tails removed,
/// only letters and digits kept.
String titleKey(String s) => foldText(s)
    .replaceAll(_brackets, ' ')
    .replaceAll(_dashTail, '')
    .replaceAll(_nonAlnum, '');

final _takeWords = RegExp(
  r'\b(live|remix|instrumental|acoustic|karaoke|sped up|slowed|nightcore|8d|demo|inst)\b',
);

Set<String> _takes(String s) =>
    _takeWords.allMatches(foldText(s)).map((m) => m.group(1)!).toSet();

/// True when [candidate] is another take (live, remix, ...) that [wanted] isn't.
bool isOtherTake(String candidate, String wanted) =>
    !_takes(wanted).containsAll(_takes(candidate));

/// Same title key, and not another take.
bool sameSong(String candidate, String wanted) {
  final c = titleKey(candidate);
  return c.isNotEmpty &&
      c == titleKey(wanted) &&
      !isOtherTake(candidate, wanted);
}

/// After folding, one artist name contains the other.
bool sameArtist(String candidate, String wanted) {
  final c = titleKey(candidate);
  final w = titleKey(wanted);
  if (c.isEmpty || w.isEmpty) return false;
  return c.contains(w) || w.contains(c);
}

/// Within [tolerance]; an unknown length on either side passes.
bool closeDuration(
  Duration? candidate,
  Duration? wanted, {
  Duration tolerance = const Duration(seconds: 4),
}) {
  if (candidate == null || wanted == null) return true;
  if (candidate == Duration.zero || wanted == Duration.zero) return true;
  return (candidate - wanted).abs() <= tolerance;
}

/// Hard yes/no test (doc 26 §2). Song results need the same title key,
/// no other take and a length within 4 s; album results need the same
/// album key and no other take.
bool strictMatch({
  required String wantArtist,
  required String resultArtist,
  String? wantAlbum,
  String? resultAlbum,
  String? wantTitle,
  String? resultTitle,
  Duration? wantDuration,
  Duration? resultDuration,
}) {
  if (!sameArtist(resultArtist, wantArtist)) return false;
  if (resultTitle != null) {
    return wantTitle != null &&
        sameSong(resultTitle, wantTitle) &&
        closeDuration(resultDuration, wantDuration);
  }
  if (resultAlbum != null && wantAlbum != null) {
    final k = titleKey(resultAlbum);
    return k.isNotEmpty &&
        k == titleKey(wantAlbum) &&
        !isOtherTake(resultAlbum, wantAlbum);
  }
  return false;
}

/// Parse a millisecond count from JSON (int, double or string).
Duration? msDuration(Object? v) {
  final ms = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  return ms == null || ms <= 0 ? null : Duration(milliseconds: ms);
}
