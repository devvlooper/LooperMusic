import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/core/utils/motion.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/setup_kit.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Fixed genre list: YouTube Music's own genre grid is per country and
/// mostly languages and regions, so it does not work as a taste list.
/// Provides over 70 familiar genres, moods, and styles.
const _genres = [
  'Pop', 'Hip-hop', 'Rock', 'Electronic', 'R&B', 'Indie', 'Jazz',
  'Classical', 'Metal', 'Country', 'Latin', 'K-pop', 'Bollywood', 'Punjabi',
  'Lo-fi', 'Reggae', 'Blues', 'Folk', 'Soul', 'Afrobeats', 'EDM', 'Devotional',
  'Acoustic',
  'Ambient',
  'Funk',
  'House',
  'Techno',
  'Punk',
  'Disco',
  'Synthwave',
  'Soundtracks', 'Sufi',
  // Expanded 35+ familiar genres, moods, and styles
  'Dance',
  'Alternative',
  'Hard Rock',
  'Classic Rock',
  'Indie Rock',
  'Indie Pop',
  'Trap', 'Old School Hip-Hop', 'Drill', 'Deep House', 'Dubstep', 'Drum & Bass',
  'Trance',
  'Heavy Metal',
  'Nu-Metal',
  'Acoustic Pop',
  'Chill & Relax',
  'Workout',
  'Focus & Study', 'Sleep', 'Party', '80s Retro', '90s Hits', '2000s Nostalgia',
  'Ghazals', 'Bhangra', 'Telugu', 'Tamil', 'Kannada', 'Malayalam', 'Reggaeton',
  'Bachata',
  'Salsa',
  'Anime & J-Rock',
  'J-Pop',
  'C-Pop',
  'Gospel',
  'Piano & Instrumental',
  'Chillhop', 'Post-Punk', 'Grunge', 'Progressive Rock', 'Ska',
];

/// Sub-genres or similar genres to expand dynamically when a genre is picked.
const Map<String, List<String>> _similarGenres = {
  'Rock': [
    'Hard Rock',
    'Alternative Rock',
    'Classic Rock',
    'Indie Rock',
    'Grunge',
    'Progressive Rock',
  ],
  'Hip-hop': [
    'Trap',
    'Old School Hip-Hop',
    'Drill',
    'Boom Bap',
    'Conscious Rap',
  ],
  'Pop': ['Dance Pop', 'Synthpop', 'Indie Pop', 'Electropop', 'Teen Pop'],
  'Electronic': [
    'House',
    'Techno',
    'Dubstep',
    'Drum & Bass',
    'Trance',
    'Deep House',
  ],
  'EDM': ['Progressive House', 'Future Bass', 'Electro House', 'Hardstyle'],
  'Metal': [
    'Heavy Metal',
    'Nu-Metal',
    'Death Metal',
    'Thrash Metal',
    'Power Metal',
  ],
  'R&B': ['Contemporary R&B', 'Neo-Soul', 'Quiet Storm', 'Alternative R&B'],
  'Jazz': ['Smooth Jazz', 'Bebop', 'Fusion', 'Vocal Jazz', 'Bossa Nova'],
  'Classical': ['Baroque', 'Romantic', 'Orchestral', 'Contemporary Classical'],
  'Country': ['Contemporary Country', 'Bluegrass', 'Country Pop', 'Americana'],
  'Latin': ['Reggaeton', 'Bachata', 'Salsa', 'Latin Pop', 'Cumbia'],
  'K-pop': ['K-R&B', 'K-Hip Hop', 'K-Indie', 'K-Rock'],
  'Bollywood': [
    'Bollywood Romantic',
    'Bollywood Dance',
    'Retro Bollywood',
    'Sufi Bollywood',
    'Ghazals',
  ],
  'Punjabi': ['Punjabi Pop', 'Bhangra', 'Punjabi Hip-hop', 'Punjabi Folk'],
  'Indie': ['Indie Folk', 'Dream Pop', 'Shoegaze', 'Post-Punk'],
  'Lo-fi': ['Lo-fi Beats', 'Chillhop', 'Study Beats', 'Sleep Lo-fi'],
  'Reggae': ['Roots Reggae', 'Dub', 'Dancehall', 'Ska'],
  'Blues': ['Delta Blues', 'Chicago Blues', 'Blues Rock', 'Electric Blues'],
  'Folk': [
    'Contemporary Folk',
    'Traditional Folk',
    'Folk Rock',
    'Acoustic Folk',
  ],
  'Soul': ['Southern Soul', 'Motown', 'Northern Soul', 'Neo-Soul'],
  'Afrobeats': ['Amapiano', 'Afro-pop', 'Highlife'],
  'House': ['Deep House', 'Tech House', 'Progressive House'],
  'Techno': ['Melodic Techno', 'Industrial Techno', 'Peak Time Techno'],
  'Punk': ['Pop Punk', 'Hardcore Punk', 'Post-Punk'],
  'Disco': ['Nu-Disco', 'Italo Disco', 'Euro Disco'],
  'Synthwave': ['Retrowave', 'Darksynth', 'Chillwave'],
  'Devotional': ['Bhajans', 'Kirtan', 'Gospel', 'Chants'],
  'Sufi': ['Qawwali', 'Sufi Rock', 'Mystic Sufi'],
  'Soundtracks': ['Film Scores', 'Video Game Music', 'Anime OST'],
  'Ambient': ['Dark Ambient', 'Drone', 'Space Ambient'],
  'Acoustic': ['Acoustic Pop', 'Acoustic Rock', 'Fingerstyle Guitar'],
  'Funk': ['P-Funk', 'Funk Rock', 'Boogie'],
  'Dance': ['Dance Pop', 'Club Dance', 'Eurodance', 'Electro Pop', 'Nu-Disco'],
  'Alternative': [
    'Alternative Rock',
    'Indie Alternative',
    'Grunge',
    'Post-Grunge',
    'Emo',
  ],
  'Alternative Rock': ['Post-Grunge', 'Britpop', 'Shoegaze', 'Modern Rock'],
  'Hard Rock': ['Arena Rock', 'Glam Metal', 'Blues Rock', 'Stoner Rock'],
  'Classic Rock': [
    'Psychedelic Rock',
    'Southern Rock',
    'Heartland Rock',
    'Folk Rock',
  ],
  'Indie Rock': ['Garage Rock', 'Post-Punk Revival', 'Math Rock', 'Indie Pop'],
  'Indie Pop': ['Chamber Pop', 'Twee Pop', 'Dream Pop', 'Bedroom Pop'],
  'Trap': ['Southern Trap', 'Melodic Trap', 'Cloud Rap', 'Latin Trap'],
  'Old School Hip-Hop': [
    'Golden Age Hip Hop',
    'East Coast Hip Hop',
    'West Coast Rap',
    'G-Funk',
  ],
  'Drill': ['UK Drill', 'Chicago Drill', 'Brooklyn Drill'],
  'Deep House': ['Melodic Deep House', 'Soulful House', 'Vocal Deep House'],
  'Dubstep': ['Brostep', 'Melodic Dubstep', 'Riddim', 'Tearout'],
  'Drum & Bass': ['Liquid DnB', 'Jump Up', 'Neurofunk', 'Jungle'],
  'Trance': [
    'Uplifting Trance',
    'Psytrance',
    'Progressive Trance',
    'Vocal Trance',
  ],
  'Heavy Metal': ['Speed Metal', 'Groove Metal', 'Doom Metal', 'Power Metal'],
  'Nu-Metal': ['Rap Metal', 'Alternative Metal', 'Industrial Metal'],
  'Acoustic Pop': ['Singer-Songwriter', 'Folk Pop', 'Unplugged', 'Coffeehouse'],
  'Chill & Relax': ['Chillout', 'Downtempo', 'Ambient Chill', 'Lounge'],
  'Workout': ['Cardio Pop', 'Workout EDM', 'Gym Hip Hop', 'High Energy'],
  'Focus & Study': [
    'Brain Food',
    'Study Lo-fi',
    'Classical Focus',
    'Deep Concentration',
  ],
  'Sleep': ['Sleep Ambient', 'White Noise', 'Peaceful Piano', 'Nature Sounds'],
  'Party': ['Club Bangers', 'Party Anthems', 'Festival Hits', 'Mashups'],
  '80s Retro': [
    '80s Synthpop',
    '80s New Wave',
    '80s Hair Metal',
    '80s Pop Hits',
  ],
  '90s Hits': ['90s Dance', '90s R&B', '90s Alt Rock', '90s Pop'],
  '2000s Nostalgia': ['2000s Pop', '2000s Hip Hop', '2000s Emo', '2000s R&B'],
  'Ghazals': ['Classic Ghazal', 'Modern Ghazal', 'Sufi Ghazal'],
  'Bhangra': ['Modern Bhangra', 'Desi Hip Hop', 'Folk Bhangra'],
  'Telugu': [
    'Tollywood Hits',
    'Telugu Melody',
    'Telugu Folk',
    'Telugu Mass Beats',
  ],
  'Tamil': ['Kollywood Hits', 'Tamil Melody', 'Tamil Kuthu', 'Tamil Indie'],
  'Kannada': ['Chandanavana Hits', 'Kannada Melody', 'Kannada Folk'],
  'Malayalam': ['Mollywood Hits', 'Malayalam Melody', 'Malayalam Indie'],
  'Reggaeton': ['Old School Reggaeton', 'Perreo', 'Urbano Latino'],
  'Bachata': ['Bachata Sensual', 'Traditional Bachata', 'Urban Bachata'],
  'Salsa': ['Salsa Dura', 'Salsa Romantica', 'Timba'],
  'Anime & J-Rock': [
    'Anime Openings',
    'J-Rock Hits',
    'Vocaloid',
    'Japanese City Pop',
  ],
  'J-Pop': ['City Pop', 'J-Pop Idol', 'Shibuya-kei', 'J-Dance'],
  'C-Pop': ['Mandopop', 'Cantopop', 'Chinese Hip Hop'],
  'Gospel': ['Contemporary Gospel', 'Urban Gospel', 'Praise & Worship'],
  'Piano & Instrumental': [
    'Solo Piano',
    'Cinematic Strings',
    'Neo-Classical',
    'Film Scores',
  ],
  'Chillhop': ['Jazzhop', 'Chill Beats', 'Instrumental Hip Hop'],
  'Post-Punk': ['Gothic Rock', 'Darkwave', 'Coldwave', 'No Wave'],
  'Grunge': ['Seattle Sound', 'Riot Grrrl', 'Sludge Rock'],
  'Progressive Rock': ['Art Rock', 'Symphonic Rock', 'Space Rock', 'Krautrock'],
  'Ska': ['2 Tone', 'Ska Punk', 'Third Wave Ska'],
};

/// Universal pool of familiar household-name artists to ensure initial list
/// is instantly recognizable and easy to pick from.
const _familiarArtistSeeds = [
  'Taylor Swift',
  'The Weeknd',
  'Drake',
  'Eminem',
  'Billie Eilish',
  'Ed Sheeran',
  'Ariana Grande',
  'Coldplay',
  'Bruno Mars',
  'Dua Lipa',
  'Justin Bieber',
  'Post Malone',
  'Kendrick Lamar',
  'Imagine Dragons',
  'Queen',
  'BTS',
  'Bad Bunny',
  'Arijit Singh',
  'Diljit Dosanjh',
  'Shreya Ghoshal',
  'AP Dhillon',
  'Sidhu Moose Wala',
  'Pritam',
  'A.R. Rahman',
  'Karan Aujla',
  'Anirudh Ravichander',
  'Lana Del Rey',
  'Arctic Monkeys',
  'Linkin Park',
  'Nirvana',
  'David Guetta',
  'Calvin Harris',
  'Avicii',
  'Alan Walker',
  'Travis Scott',
  'Olivia Rodrigo',
  'Harry Styles',
  'SZA',
  'Katy Perry',
  'Lady Gaga',
  'Shakira',
  'Maroon 5',
  'Adele',
  'Beyoncé',
  'Rihanna',
  'Michael Jackson',
  'Charlie Puth',
  'Shawn Mendes',
  'Daft Punk',
  'Twenty One Pilots',
  'Marshmello',
  'Martin Garrix',
  'Kygo',
  'Kanye West',
];

/// First-run interest profile: genres, then artists. Every pick is saved as
/// it is made, so leaving half-way keeps it.
class TasteSetupScreen extends ConsumerStatefulWidget {
  const TasteSetupScreen({
    super.key,
    this.steps,
    this.onBack,
    this.onDone,
    this.startOnArtists = false,
  });

  /// Set when embedded in first-run setup: the step label, and where back
  /// (from genres) and done (after artists) go. Standalone it pops itself.
  /// Step labels for (genres, artists) in first-run setup.
  final (String, String)? steps;
  final VoidCallback? onBack;
  final VoidCallback? onDone;
  final bool startOnArtists;

  @override
  ConsumerState<TasteSetupScreen> createState() => _TasteSetupScreenState();
}

class _TasteSetupScreenState extends ConsumerState<TasteSetupScreen> {
  int _step = 0;
  bool _reverse = false;
  List<String> _localGenres = const [];
  final List<String> _expandedGenres = [];
  List<OnlineCollection> _artists = const [];
  bool _loadingArtists = false;
  final _search = TextEditingController();
  final _genreSearch = TextEditingController();
  Timer? _debounce;

  // Similar / "Fans might also like" state
  /// Artists whose similar artists were already pulled in, so re-picking
  /// one doesn't fetch again.
  final Set<String> _expandedArtists = {};

  /// Freshly added suggestions, faded in once when they land in the grid.
  final Set<String> _fresh = {};

  @override
  void initState() {
    super.initState();
    _loadLocalGenres();
    if (widget.startOnArtists) _step = 1;
    _loadArtists();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _genreSearch.dispose();
    super.dispose();
  }

  static Future<List<String>> _topLocal(
    Future<List<String?>> Function() read,
    int n,
  ) async {
    final counts = <String, int>{};
    for (final v in await read()) {
      final k = v?.trim();
      if (k != null && k.isNotEmpty) {
        counts.update(k, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  /// Top genres from the user's own songs. On first setup they arrive
  /// picked, like the library's top artists do on the next step.
  Future<void> _loadLocalGenres() async {
    final g = await _topLocal(() async {
      final tags = await DbService.isar.songs
          .filter()
          .not()
          .pathStartsWith('yt:')
          .genreProperty()
          .findAll();
      // One tag often holds several genres: "Pop; Dance" or "Rock/Indie".
      return [for (final t in tags) ...?t?.split(RegExp(r'[;/,|]'))];
    }, 6);
    if (!mounted) return;
    setState(() => _localGenres = g);
    if (ref.read(tasteProvider).genres.isEmpty) {
      for (final genre in g) {
        await ref.read(tasteProvider.notifier).toggleGenre(genre);
      }
    }
  }

  /// Adds artists not in the grid yet ([front]: ahead of the rest).
  void _addArtists(Iterable<OnlineCollection> xs, {bool front = false}) {
    if (!mounted) return;
    final have = {for (final a in _artists) a.title.toLowerCase()};
    final fresh = <OnlineCollection>[];
    for (final c in xs) {
      if (have.add(c.title.toLowerCase())) fresh.add(c);
    }
    if (fresh.isEmpty) return;
    setState(
      () =>
          _artists = front ? [...fresh, ..._artists] : [..._artists, ...fresh],
    );
  }

  Future<List<OnlineCollection>> _searchArtists(String q) async {
    try {
      return await OnlineApi.searchCollections(q, CollectionKind.artist);
    } catch (_) {
      return const [];
    }
  }

  /// Exact-name match for [name], or null.
  Future<OnlineCollection?> _resolveArtist(
    String name, {
    bool loose = false,
  }) async {
    final r = await _searchArtists(name);
    return r
            .where((c) => c.title.toLowerCase() == name.toLowerCase())
            .firstOrNull ??
        (loose ? r.firstOrNull : null);
  }

  /// Artists start from the user: their library's top artists arrive picked
  /// and go first, then popular artists. Starts while the genres step is
  /// still open; every search runs in parallel and lands in the grid as soon
  /// as it answers, so the first artists show after one round trip.
  Future<void> _loadArtists() async {
    if (_loadingArtists || _artists.isNotEmpty) return;
    setState(() => _loadingArtists = true);
    final notifier = ref.read(tasteProvider.notifier);

    Future<void> mine() async {
      final local = await _topLocal(
        () => DbService.isar.songs
            .filter()
            .not()
            .pathStartsWith('yt:')
            .artistProperty()
            .findAll(),
        8,
      );
      final found = (await Future.wait(
        local.map(_resolveArtist),
      )).whereType<OnlineCollection>().toList();
      _addArtists(found, front: true);
      if (ref.read(tasteProvider).artists.isEmpty) {
        for (final c in found) {
          await notifier.toggleArtist(
            TasteArtist(c.title, browseId: c.browseId, thumbnail: c.thumbnail),
          );
        }
      }
    }

    // Familiar names resolve one each; fired together, they fill the grid
    // with recognisable faces while the broader searches come back.
    Future<void> familiar() => Future.wait(
      _familiarArtistSeeds.take(24).map((name) async {
        final c = await _resolveArtist(name, loose: true);
        if (c != null) _addArtists([c]);
      }),
    );

    Future<void> popular() => Future.wait(
      const [
        'top global artists',
        'billboard hot 100 artists',
        'popular artists hits',
        'trending music artists',
      ].map((q) async => _addArtists(await _searchArtists(q))),
    );

    await Future.wait([mine(), familiar(), popular()]);
    if (mounted) setState(() => _loadingArtists = false);
  }

  /// Artists for the genres picked on step one, added when moving on.
  Future<void> _loadGenreArtists() async {
    final genres = ref.read(tasteProvider).genres;
    await Future.wait(
      [
        for (final g in genres.take(8)) '$g top artists',
      ].map((q) async => _addArtists(await _searchArtists(q))),
    );
  }

  /// Fetches up to 10 similar / "Fans might also like" artists for [artist]
  /// and slots them into the grid right after it.
  Future<void> _expandSimilarArtists(OnlineCollection artist) async {
    if (!_expandedArtists.add(artist.title.toLowerCase())) return;
    final results = <OnlineCollection>[];
    final seen = <String>{artist.title.toLowerCase()};

    // 1. YouTube Music's official "Fans might also like" shelf on artist page
    if (artist.browseId.isNotEmpty) {
      try {
        final page = await OnlineApi.page(artist.browseId);
        for (final shelf in page.shelves) {
          final lower = shelf.title.toLowerCase();
          if (lower.contains('fans') ||
              lower.contains('similar') ||
              lower.contains('like')) {
            for (final c in shelf.collections) {
              if (c.kind == CollectionKind.artist &&
                  seen.add(c.title.toLowerCase())) {
                results.add(c);
                if (results.length >= 10) break;
              }
            }
          }
          if (results.length >= 10) break;
        }
      } catch (_) {}
    }

    // 2. Supplementary search if under 10
    if (results.length < 10) {
      final searchQueries = [
        '${artist.title} fans also like',
        '${artist.title} similar artists',
        '${artist.title} radio artists',
      ];
      for (final q in searchQueries) {
        if (results.length >= 10) break;
        try {
          final list = await OnlineApi.searchCollections(
            q,
            CollectionKind.artist,
          );
          for (final c in list) {
            if (seen.add(c.title.toLowerCase())) {
              results.add(c);
              if (results.length >= 10) break;
            }
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() {
      final have = {for (final a in _artists) a.title.toLowerCase()};
      final toAdd = results
          .where((a) => !have.contains(a.title.toLowerCase()))
          .take(10)
          .toList();
      if (toAdd.isEmpty) return;
      _fresh.addAll(toAdd.map((a) => a.title.toLowerCase()));
      final at = _artists.indexWhere(
        (a) => a.title.toLowerCase() == artist.title.toLowerCase(),
      );
      _artists = [..._artists]..insertAll(at + 1, toAdd);
    });
  }

  void _onSearch(String q) {
    setState(() {}); // Updates filter immediately
    _debounce?.cancel();
    if (q.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final r = await OnlineApi.searchCollections(q, CollectionKind.artist);
        if (!mounted) return;
        setState(() {
          final names = {for (final a in _artists) a.title.toLowerCase()};
          _artists = [
            ...r.where((c) => !names.contains(c.title.toLowerCase())),
            ..._artists,
          ];
        });
      } catch (_) {}
    });
  }

  Future<void> _finish() async {
    await ref.read(tasteProvider.notifier).markSeen();
    unawaited(ref.read(onlineHomeProvider.notifier).load(force: true));
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _back() {
    if (_step == 1) {
      setState(() {
        _reverse = true;
        _step = 0;
      });
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _next() {
    if (_step == 0) {
      setState(() {
        _reverse = false;
        _step = 1;
      });
      _loadArtists();
      _loadGenreArtists();
    } else {
      _finish();
    }
  }

  Widget _buildArtistCard(OnlineCollection a, Taste taste, Color accent) {
    final picked = taste.hasArtist(a.title);
    final tile = _ArtistTile(
      picked: picked,
      name: a.title,
      art: OnlineArt(
        url: a.thumbnail,
        size: 60,
        round: true,
        icon: LucideIcons.user,
      ),
    );
    return SetupPressable(
      onTap: () {
        AppHaptics.selection();
        final willBePicked = !picked;
        ref
            .read(tasteProvider.notifier)
            .toggleArtist(
              TasteArtist(
                a.title,
                browseId: a.browseId,
                thumbnail: a.thumbnail,
              ),
            );
        if (willBePicked) unawaited(_expandSimilarArtists(a));
      },
      // Always the same wrapper: swapping it out when the fade ended rebuilt
      // the tile and reloaded its picture (a second flicker). The tween only
      // runs on the first build, so non-fresh tiles start at 1 and stay put.
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: _fresh.contains(a.title.toLowerCase()) ? 0 : 1,
          end: 1,
        ),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        onEnd: () => _fresh.remove(a.title.toLowerCase()),
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        ),
        child: tile,
      ),
    );
  }

  Widget _genreChip(String g, Taste taste) {
    final picked = taste.genres.contains(g);
    return SetupPressable(
      onTap: () {
        AppHaptics.selection();
        ref.read(tasteProvider.notifier).toggleGenre(g);
        final sub = _similarGenres[g];
        if (!picked && sub != null) {
          setState(() {
            for (final item in sub) {
              if (!_expandedGenres.contains(item)) _expandedGenres.add(item);
            }
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 39,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: picked ? kSetupInner : kSetupInner.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(8.5),
          border: Border.all(
            color: picked ? const Color(0xFF2A2A2A) : kSetupLine,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The width changes once, not per frame: an AnimatedSize here
            // re-flowed the whole Wrap for 220 ms and made the card shimmer.
            if (picked)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (context, t, child) => Transform.scale(
                  scale: t,
                  child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                ),
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SetupCheck(on: true, size: 16),
                ),
              ),
            Text(g, style: setupBody(size: 15, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _genresPage(AppLocalizations l10n, Taste taste) {
    final baseGenres = [
      ..._localGenres,
      ..._genres.where(
        (g) => !_localGenres.any((l) => l.toLowerCase() == g.toLowerCase()),
      ),
    ];
    final genreList = [
      ...baseGenres,
      ..._expandedGenres.where((g) => !baseGenres.contains(g)),
    ];
    final q = _genreSearch.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? genreList
        : genreList.where((g) => g.toLowerCase().contains(q)).toList();
    return SetupPage(
      step: widget.steps?.$1,
      expand: true,
      // Title and description sit right above the card; the card takes 80%
      // of the space under them, so picking chips (and the genres they
      // reveal) scrolls inside it instead of growing it.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(l10n.tasteGenresTitle, style: setupTitleStyle()),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(l10n.setupGenresDesc, style: setupBody()),
          ),
          const SizedBox(height: 16),
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                color: kSetupCard,
                borderRadius: BorderRadius.circular(15),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 15, 15, 0),
                    child: _searchField(
                      _genreSearch,
                      l10n.setupSearchGenre,
                      (_) => setState(() {}),
                    ),
                  ),
                  Expanded(
                    child: _fadeBottom(
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
                        child: shown.isEmpty
                            ? Text(
                                l10n.noResultsFound,
                                textAlign: TextAlign.center,
                                style: setupBody(size: 14),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 12,
                                children: [
                                  for (final g in shown) _genreChip(g, taste),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottom: SetupBottomBar(
        label: l10n.setupContinue,
        onBack: _back,
        onNext: _next,
      ),
    );
  }

  /// Fades the last bit of a scrolling card into it, like the design.
  static Widget _fadeBottom(Widget child) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (r) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, 0.86, 1],
      colors: [Colors.white, Colors.white, Colors.transparent],
    ).createShader(r),
    child: child,
  );

  SliverGrid _grid(
    List<OnlineCollection> items,
    Taste taste,
    int count,
    double width,
  ) {
    final cellW = (width - 14 * (count - 1)) / count;
    final cellH = cellW / (101 / 116);
    Offset at(int i) =>
        Offset((i % count) * (cellW + 14), (i ~/ count) * (cellH + 16));
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        childAspectRatio: 101 / 116,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
      ),
      // Keyed by artist so an insert moves tiles instead of handing every
      // later slot a different artist (which reloaded each picture).
      delegate: SliverChildBuilderDelegate(
        (_, i) => _SlideToSlot(
          key: ValueKey(items[i].title.toLowerCase()),
          offset: at(i),
          child: _buildArtistCard(items[i], taste, kSetupAccent),
        ),
        childCount: items.length,
        findChildIndexCallback: (key) {
          final name = (key as ValueKey<String>).value;
          final i = items.indexWhere((a) => a.title.toLowerCase() == name);
          return i < 0 ? null : i;
        },
      ),
    );
  }

  Widget _artistGrid(Taste taste) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 110).floor().clamp(3, 8);
        if (_loadingArtists && _artists.isEmpty) {
          // Placeholder tiles instead of a spinner while artists load.
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              childAspectRatio: 101 / 116,
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
            ),
            itemCount: count * 4,
            itemBuilder: (_, _) => const _ArtistTile(
              picked: false,
              name: null,
              art: CircleAvatar(radius: 30, backgroundColor: Color(0xFF3B3B3B)),
            ),
          );
        }
        final q = _search.text.trim().toLowerCase();
        final displayed = q.isEmpty
            ? _artists
            : _artists.where((a) => a.title.toLowerCase().contains(q)).toList();
        if (displayed.isEmpty && !_loadingArtists) {
          return Center(
            child: Text(
              AppLocalizations.of(context)!.noArtistsFound,
              style: setupBody(size: 14),
            ),
          );
        }

        final slivers = <Widget>[
          _grid(displayed, taste, count, constraints.maxWidth),
        ];
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 40)));
        return _fadeBottom(CustomScrollView(slivers: slivers));
      },
    );
  }

  /// The rounded search box the genre and artist cards open with.
  Widget _searchField(
    TextEditingController controller,
    String hint,
    ValueChanged<String> onChanged,
  ) => TextField(
    controller: controller,
    onChanged: onChanged,
    cursorColor: kSetupAccent,
    style: setupBody(size: 15, color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: setupBody(size: 15, color: const Color(0xFF808080)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Color(0xFF808080),
              ),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.5),
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.5),
        borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
    ),
  );

  Widget _artistsPage(AppLocalizations l10n, Taste taste) {
    return SetupPage(
      step: widget.steps?.$2,
      title: l10n.setupArtistsTitle,
      description: l10n.setupArtistsDesc,
      expand: true,
      body: Container(
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 0),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(15),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _searchField(_search, l10n.setupSearchArtist, _onSearch),
            const SizedBox(height: 16),
            Expanded(child: _artistGrid(taste)),
          ],
        ),
      ),
      bottom: SetupBottomBar(
        label: l10n.setupAlmostThere,
        onBack: _back,
        onNext: _next,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final taste = ref.watch(tasteProvider);
    final pages = SetupSwitcher(
      reverse: _reverse,
      child: KeyedSubtree(
        key: ValueKey(_step),
        child: _step == 0
            ? _genresPage(l10n, taste)
            : _artistsPage(l10n, taste),
      ),
    );
    // Embedded in first-run setup, which already draws the backdrop.
    if (widget.onDone != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: pages,
      );
    }
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: kSetupBg,
        body: SetupBackground(child: pages),
      ),
    );
  }
}

/// Glides a grid tile from its previous slot to its new one when artists
/// are inserted ahead of it, instead of jumping there.
class _SlideToSlot extends StatefulWidget {
  const _SlideToSlot({super.key, required this.offset, required this.child});

  /// This tile's slot position inside the grid.
  final Offset offset;
  final Widget child;

  @override
  State<_SlideToSlot> createState() => _SlideToSlotState();
}

class _SlideToSlotState extends State<_SlideToSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  Offset _from = Offset.zero;

  @override
  void didUpdateWidget(_SlideToSlot old) {
    super.didUpdateWidget(old);
    if (old.offset == widget.offset || Motion.reducedOf(context)) return;
    // Start from wherever it is drawn right now, so back-to-back inserts
    // chain smoothly.
    final t = Curves.easeOutCubic.transform(_c.value);
    _from = old.offset + _from * (1 - t) - widget.offset;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(
      offset: _c.isAnimating
          ? _from * (1 - Curves.easeOutCubic.transform(_c.value))
          : Offset.zero,
      child: child,
    ),
    child: widget.child,
  );
}

/// Grey rounded tile: round avatar with a check badge, name underneath.
class _ArtistTile extends StatelessWidget {
  const _ArtistTile({
    required this.picked,
    required this.name,
    required this.art,
  });

  final bool picked;
  final String? name;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: picked ? kSetupInner : kSetupInner.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(8.5),
        border: Border.all(
          color: picked ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: Column(
        children: [
          SizedBox(
            width: 66,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                art,
                Positioned(
                  top: 0,
                  right: 0,
                  child: AnimatedScale(
                    scale: picked ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: picked ? Curves.easeOutBack : Curves.easeIn,
                    child: const SetupCheck(on: true, size: 16),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (name != null)
            Text(
              name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: setupBody(size: 14, color: Colors.white, height: 1.2),
            ),
        ],
      ),
    );
  }
}
