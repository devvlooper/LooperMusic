import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/storage/local_json_store.dart';
import 'package:looper_player/features/online/data/taste_profile_store.dart';

class TasteArtist {
  const TasteArtist(this.name, {this.browseId, this.thumbnail});
  final String name;
  final String? browseId;
  final String? thumbnail;

  Map<String, dynamic> toJson() => {'n': name, 'b': browseId, 't': thumbnail};
}

/// What the user said they like in taste setup. Key names are frozen.
class Taste {
  const Taste({
    this.artists = const [],
    this.genres = const [],
    this.seen = false,
  });
  final List<TasteArtist> artists;
  final List<String> genres;

  /// Taste setup was shown (finished or skipped): do not open it again.
  final bool seen;

  bool hasArtist(String name) =>
      artists.any((a) => a.name.toLowerCase() == name.toLowerCase());

  Map<String, dynamic> toJson() => {
    'artists': [for (final a in artists) a.toJson()],
    'genres': genres,
    'seen': seen,
  };

  factory Taste.fromJson(Map j) => Taste(
    artists: [
      for (final a in (j['artists'] as List? ?? const []))
        if (a is Map && a['n'] is String)
          TasteArtist(
            a['n'] as String,
            browseId: a['b'] as String?,
            thumbnail: a['t'] as String?,
          ),
    ],
    genres: [...(j['genres'] as List? ?? const []).whereType<String>()],
    seen: j['seen'] == true,
  );
}

class TasteNotifier extends Notifier<Taste> {
  static const _key = 'online_taste';
  static Taste current = const Taste();
  static Future<void>? _loading;

  @override
  Taste build() {
    loaded().then((t) {
      if (!identical(state, t)) state = t;
    });
    return current;
  }

  static Future<void> _read() async {
    final raw = await LocalJsonStore.read(_key);
    if (raw is Map) current = Taste.fromJson(raw);
  }

  /// The saved taste, once read from disk.
  static Future<Taste> loaded() async {
    await (_loading ??= _read());
    return current;
  }

  // Each pick is saved at once, so leaving setup half-way keeps it.
  Future<void> _set(Taste t) async {
    state = current = t;
    await LocalJsonStore.write(_key, t.toJson());
  }

  Future<void> toggleArtist(TasteArtist a) async {
    final willFollow = !state.hasArtist(a.name);
    await _set(
      Taste(
        artists: willFollow
            ? [
                a,
                ...state.artists.where(
                  (x) => x.name.toLowerCase() != a.name.toLowerCase(),
                ),
              ]
            : state.artists
                  .where((x) => x.name.toLowerCase() != a.name.toLowerCase())
                  .toList(),
        genres: state.genres,
        seen: state.seen,
      ),
    );
    TasteProfileStore.invalidate();
    await LocalJsonStore.delete('online_artists_for_you_v1');
  }

  Future<void> toggleGenre(String g) => _set(
    Taste(
      artists: state.artists,
      genres: state.genres.contains(g)
          ? state.genres.where((x) => x != g).toList()
          : [...state.genres, g],
      seen: state.seen,
    ),
  );

  Future<void> markSeen() =>
      _set(Taste(artists: state.artists, genres: state.genres, seen: true));

  /// Merges (or replaces) the taste profile artists and genres with real
  /// account subscriptions and likes from YouTube Music.
  Future<void> mergeAccountTaste({
    required List<TasteArtist> artists,
    List<String> genres = const [],
    bool replace = false,
  }) async {
    final mergedArtists = <String, TasteArtist>{};
    if (!replace) {
      for (final a in state.artists) {
        mergedArtists[a.name.toLowerCase()] = a;
      }
    }
    for (final a in artists) {
      mergedArtists[a.name.toLowerCase()] = a;
    }
    final mergedGenres = <String>{if (!replace) ...state.genres, ...genres};
    await _set(
      Taste(
        artists: mergedArtists.values.toList(),
        genres: mergedGenres.toList(),
        seen: true,
      ),
    );
  }
}

final tasteProvider = NotifierProvider<TasteNotifier, Taste>(TasteNotifier.new);
