import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
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
  const TasteSetupScreen({super.key});

  @override
  ConsumerState<TasteSetupScreen> createState() => _TasteSetupScreenState();
}

class _TasteSetupScreenState extends ConsumerState<TasteSetupScreen> {
  int _step = 0;
  List<String> _localGenres = const [];
  final List<String> _expandedGenres = [];
  List<OnlineCollection> _artists = const [];
  bool _loadingArtists = false;
  final _search = TextEditingController();
  Timer? _debounce;

  // Similar / "Fans might also like" state
  int _similarReqCounter = 0;
  OnlineCollection? _activeSimilarArtist;
  List<OnlineCollection> _similarArtists = const [];
  bool _loadingSimilar = false;

  @override
  void initState() {
    super.initState();
    _loadLocalGenres();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
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

  /// Artists start from the user: their library's top artists arrive
  /// picked, then artists for the chosen genres, ensuring at least 60 familiar artists initially.
  Future<void> _loadArtists() async {
    setState(() => _loadingArtists = true);
    final notifier = ref.read(tasteProvider.notifier);
    final found = <String, OnlineCollection>{};
    void add(Iterable<OnlineCollection> xs) {
      for (final c in xs) {
        found.putIfAbsent(c.title.toLowerCase(), () => c);
      }
    }

    final local = await _topLocal(
      () => DbService.isar.songs
          .filter()
          .not()
          .pathStartsWith('yt:')
          .artistProperty()
          .findAll(),
      8,
    );
    final resolved = await Future.wait(
      local.map((name) async {
        try {
          final r = await OnlineApi.searchCollections(
            name,
            CollectionKind.artist,
          );
          return r
              .where((c) => c.title.toLowerCase() == name.toLowerCase())
              .firstOrNull;
        } catch (_) {
          return null;
        }
      }),
    );
    final mine = resolved.whereType<OnlineCollection>().toList();
    add(mine);
    if (ref.read(tasteProvider).artists.isEmpty) {
      for (final c in mine) {
        await notifier.toggleArtist(
          TasteArtist(c.title, browseId: c.browseId, thumbnail: c.thumbnail),
        );
      }
    }

    final genres = ref.read(tasteProvider).genres;
    final queries = [
      for (final g in genres.take(8)) '$g top artists',
      for (final g in genres.take(4)) '$g hits',
      'top global artists',
      'billboard hot 100 artists',
      'popular artists hits',
      'trending music artists',
      'all time greatest artists',
      'top hit artists',
    ];

    // Parallel fetch in batches of 3 for fast loading
    for (var i = 0; i < queries.length; i += 3) {
      if (found.length >= 60) break;
      final batch = queries.skip(i).take(3);
      final batchResults = await Future.wait(
        batch.map((q) async {
          try {
            return await OnlineApi.searchCollections(q, CollectionKind.artist);
          } catch (_) {
            return const <OnlineCollection>[];
          }
        }),
      );
      for (final list in batchResults) {
        add(list);
      }
    }

    // Ensure familiar household-name artists pool to hit at least 60 familiar choices
    if (found.length < 60) {
      for (var i = 0; i < _familiarArtistSeeds.length; i += 4) {
        if (found.length >= 60) break;
        final batch = _familiarArtistSeeds.skip(i).take(4);
        final batchResults = await Future.wait(
          batch.map((name) async {
            if (found.containsKey(name.toLowerCase())) return null;
            try {
              final list = await OnlineApi.searchCollections(
                name,
                CollectionKind.artist,
              );
              return list
                      .where((c) => c.title.toLowerCase() == name.toLowerCase())
                      .firstOrNull ??
                  list.firstOrNull;
            } catch (_) {
              return null;
            }
          }),
        );
        for (final item in batchResults) {
          if (item != null) add([item]);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _artists = found.values.toList();
      _loadingArtists = false;
    });
  }

  /// Dynamically fetches 10 similar or "Fans might also like" artists for the
  /// selected artist and displays them in a dedicated horizontal row.
  Future<void> _expandSimilarArtists(OnlineCollection artist) async {
    final reqId = ++_similarReqCounter;
    setState(() {
      _activeSimilarArtist = artist;
      _loadingSimilar = true;
      _similarArtists = const [];
    });

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

    if (!mounted || reqId != _similarReqCounter) return;

    setState(() {
      _similarArtists = results.take(10).toList();
      _loadingSimilar = false;
      // Merge into _artists catalog so they persist
      final existingNames = {for (final a in _artists) a.title.toLowerCase()};
      final toAdd = _similarArtists
          .where((a) => !existingNames.contains(a.title.toLowerCase()))
          .toList();
      if (toAdd.isNotEmpty) {
        _artists = [..._artists, ...toAdd];
      }
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
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildArtistCard(OnlineCollection a, Taste taste, Color accent) {
    final picked = taste.hasArtist(a.title);
    final isExpanded =
        _activeSimilarArtist?.title.toLowerCase() == a.title.toLowerCase();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
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
        if (willBePicked) {
          unawaited(_expandSimilarArtists(a));
        } else if (isExpanded) {
          setState(() {
            _activeSimilarArtist = null;
            _similarArtists = const [];
          });
        }
      },
      child: Column(
        children: [
          Stack(
            children: [
              OnlineArt(
                url: a.thumbnail,
                size: 84,
                round: true,
                icon: LucideIcons.user,
              ),
              if (picked)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.55),
                    ),
                    child: const Icon(
                      LucideIcons.check,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            a.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.jostStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: picked ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarArtistsSection(Taste taste, Color accent) {
    final artistName = _activeSimilarArtist?.title ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(LucideIcons.sparkles, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fans of $artistName might also like',
                    style: AppFonts.jostStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_loadingSimilar)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _activeSimilarArtist = null;
                      _similarArtists = const [];
                    }),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingSimilar && _similarArtists.isEmpty)
            SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  'Finding artists similar to $artistName...',
                  style: AppFonts.jostStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else if (_similarArtists.isEmpty)
            SizedBox(
              height: 50,
              child: Center(
                child: Text(
                  'No similar artists found',
                  style: AppFonts.jostStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 116,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _similarArtists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = _similarArtists[i];
                  final picked = taste.hasArtist(a.title);
                  return SizedBox(
                    width: 80,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        AppHaptics.selection();
                        ref
                            .read(tasteProvider.notifier)
                            .toggleArtist(
                              TasteArtist(
                                a.title,
                                browseId: a.browseId,
                                thumbnail: a.thumbnail,
                              ),
                            );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            children: [
                              OnlineArt(
                                url: a.thumbnail,
                                size: 68,
                                round: true,
                                icon: LucideIcons.user,
                              ),
                              if (picked)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: accent.withValues(alpha: 0.55),
                                    ),
                                    child: const Icon(
                                      LucideIcons.check,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.jostStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: picked
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final taste = ref.watch(tasteProvider);
    final accent = Theme.of(context).colorScheme.primary;

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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          _step == 0 ? l10n.tasteGenresTitle : l10n.tasteArtistsTitle,
          style: AppFonts.jostStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [TextButton(onPressed: _finish, child: Text(l10n.tasteSkip))],
      ),
      body: _step == 0
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in genreList)
                    FilterChip(
                      label: Text(g),
                      selected: taste.genres.contains(g),
                      selectedColor: accent.withValues(alpha: 0.35),
                      onSelected: (_) {
                        AppHaptics.selection();
                        final isSelected = taste.genres.contains(g);
                        ref.read(tasteProvider.notifier).toggleGenre(g);
                        if (!isSelected) {
                          final sub = _similarGenres[g];
                          if (sub != null) {
                            setState(() {
                              for (final item in sub) {
                                if (!_expandedGenres.contains(item)) {
                                  _expandedGenres.add(item);
                                }
                              }
                            });
                          }
                        }
                      },
                    ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    style: AppFonts.jostStyle(color: Colors.white),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(LucideIcons.search),
                      hintText: l10n.tasteSearchArtists,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _loadingArtists && _artists.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final q = _search.text.trim().toLowerCase();
                            final displayed = q.isEmpty
                                ? _artists
                                : _artists
                                      .where(
                                        (a) =>
                                            a.title.toLowerCase().contains(q),
                                      )
                                      .toList();

                            if (displayed.isEmpty && !_loadingArtists) {
                              return Center(
                                child: Text(
                                  'No artists found',
                                  style: AppFonts.jostStyle(
                                    color: Colors.white54,
                                  ),
                                ),
                              );
                            }

                            final crossAxisCount = (constraints.maxWidth / 110)
                                .floor()
                                .clamp(2, 8);
                            final slivers = <Widget>[];

                            final activeIdx = _activeSimilarArtist == null
                                ? -1
                                : displayed.indexWhere(
                                    (a) =>
                                        a.title.toLowerCase() ==
                                        _activeSimilarArtist!.title
                                            .toLowerCase(),
                                  );

                            if (activeIdx != -1) {
                              final rowEnd = math.min(
                                displayed.length,
                                ((activeIdx ~/ crossAxisCount) + 1) *
                                    crossAxisCount,
                              );

                              // Top grid up to end of row containing selected artist
                              slivers.add(
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    0,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          childAspectRatio: 0.75,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                        ),
                                    delegate: SliverChildBuilderDelegate(
                                      (_, i) => _buildArtistCard(
                                        displayed[i],
                                        taste,
                                        accent,
                                      ),
                                      childCount: rowEnd,
                                    ),
                                  ),
                                ),
                              );

                              // Horizontal row of 10 similar artists directly between the rows
                              slivers.add(
                                SliverToBoxAdapter(
                                  child: _buildSimilarArtistsSection(
                                    taste,
                                    accent,
                                  ),
                                ),
                              );

                              // Bottom grid of remaining artists
                              if (rowEnd < displayed.length) {
                                slivers.add(
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      16,
                                    ),
                                    sliver: SliverGrid(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: crossAxisCount,
                                            childAspectRatio: 0.75,
                                            mainAxisSpacing: 8,
                                            crossAxisSpacing: 8,
                                          ),
                                      delegate: SliverChildBuilderDelegate(
                                        (_, i) => _buildArtistCard(
                                          displayed[rowEnd + i],
                                          taste,
                                          accent,
                                        ),
                                        childCount: displayed.length - rowEnd,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } else if (_activeSimilarArtist != null) {
                              // Selected artist not in current filter/view
                              slivers.add(
                                SliverToBoxAdapter(
                                  child: _buildSimilarArtistsSection(
                                    taste,
                                    accent,
                                  ),
                                ),
                              );
                              slivers.add(
                                SliverPadding(
                                  padding: const EdgeInsets.all(12),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          childAspectRatio: 0.75,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                        ),
                                    delegate: SliverChildBuilderDelegate(
                                      (_, i) => _buildArtistCard(
                                        displayed[i],
                                        taste,
                                        accent,
                                      ),
                                      childCount: displayed.length,
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              // Standard grid without active similar shelf
                              slivers.add(
                                SliverPadding(
                                  padding: const EdgeInsets.all(12),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          childAspectRatio: 0.75,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                        ),
                                    delegate: SliverChildBuilderDelegate(
                                      (_, i) => _buildArtistCard(
                                        displayed[i],
                                        taste,
                                        accent,
                                      ),
                                      childCount: displayed.length,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return CustomScrollView(slivers: slivers);
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              AppHaptics.light();
              if (_step == 0) {
                setState(() => _step = 1);
                _loadArtists();
              } else {
                _finish();
              }
            },
            child: Text(_step == 0 ? l10n.nextLabel : l10n.done),
          ),
        ),
      ),
    );
  }
}
