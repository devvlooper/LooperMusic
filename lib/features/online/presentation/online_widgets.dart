import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/stream_resolver.dart';
import 'package:looper_player/features/search/presentation/screens/search_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/song_tile.dart';
import 'package:looper_player/features/microg/data/account_auth.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_collection_screen.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_shelf_styles.dart';
import 'package:looper_player/features/online/presentation/online_view_all_screen.dart';
import 'package:looper_player/features/online/presentation/taste_setup_screen.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/widgets/premium_section.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/common/mochy_card_row.dart';
import 'package:looper_player/ui/widgets/sheets/song_options_bottom_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Play [songs] as the queue, starting at [index].
void playOnlineSongs(WidgetRef ref, List<OnlineSong> songs, int index) {
  AppHaptics.light();
  ref.read(playbackProvider.notifier).setPlaylist([
    for (final s in songs) s.toSong(),
  ], initialIndex: index);
}

void openOnlineCollection(BuildContext context, OnlineCollection c) {
  AppHaptics.light();
  if (c.isRadio) {
    _startStationPlayback(context, c);
    return;
  }
  Navigator.of(context).push(
    riseRoute(
      OnlineCollectionScreen(
        collection: c.copyWith(browseId: onlinePageIdOf(c)),
      ),
    ),
  );
}

/// The browse id that opens [c] as a page (editorial playlists browse VL + id).
String onlinePageIdOf(OnlineCollection c) =>
    c.mixKind == MixKind.editorialPlaylist && !c.browseId.startsWith('VL')
    ? 'VL${c.browseId}'
    : c.browseId;

/// Play [c] straight away: stations start their radio, albums and
/// playlists play their song list from the top.
void playOnlineCollection(BuildContext context, OnlineCollection c) {
  AppHaptics.light();
  if (c.isRadio) {
    _startStationPlayback(context, c);
    return;
  }
  if (c.kind == CollectionKind.artist) {
    openOnlineCollection(context, c);
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  OnlineApi.page(onlinePageIdOf(c))
      .then((page) {
        if (page.songs.isEmpty) return;
        container.read(playbackProvider.notifier).setPlaylist([
          for (final s in page.songs) s.toSong(),
        ], initialIndex: 0);
      })
      .catchError((Object e) {
        LoggerHelper.write('playOnlineCollection failed', e);
      });
}

void _startStationPlayback(BuildContext context, OnlineCollection c) {
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    OnlineApi.radioPlaylist(c.browseId)
        .then((songs) {
          if (songs.isNotEmpty && context.mounted) {
            container.read(playbackProvider.notifier).setPlaylist([
              for (final s in songs) s.toSong(),
            ], initialIndex: 0);
          }
        })
        .catchError((e) {
          LoggerHelper.write('startStationPlayback failed', e);
        });
  } catch (e) {
    LoggerHelper.write('startStationPlayback containerOf failed', e);
  }
}

void openTasteSetup(BuildContext context) {
  Navigator.of(context).push(riseRoute(const TasteSetupScreen()));
}

String shelfTitle(AppLocalizations l10n, dynamic titleOrShelf) {
  if (titleOrShelf is OnlineShelf) {
    return switch (titleOrShelf.kind) {
      ShelfKind.discover => l10n.onlineDiscover,
      ShelfKind.guestQuickPicks => l10n.onlineGuestQuickPicks,
      ShelfKind.guestRadio => l10n.onlineGuestRadio(
        titleOrShelf.args.firstOrNull ?? titleOrShelf.title,
      ),
      ShelfKind.guestBecause => l10n.onlineGuestBecause(
        titleOrShelf.args.firstOrNull ?? titleOrShelf.title,
      ),
      ShelfKind.guestSimilar => l10n.onlineGuestSimilar(
        titleOrShelf.args.firstOrNull ?? titleOrShelf.title,
      ),
      ShelfKind.guestMoreFrom => l10n.onlineGuestMoreFrom(
        titleOrShelf.args.firstOrNull ?? titleOrShelf.title,
      ),
      ShelfKind.guestTrending => l10n.onlineGuestTrending(
        titleOrShelf.args.firstOrNull ?? titleOrShelf.title,
      ),
      ShelfKind.regular =>
        titleOrShelf.title == discoverShelf
            ? l10n.onlineDiscover
            : titleOrShelf.title,
    };
  }
  if (titleOrShelf is String) {
    if (titleOrShelf == discoverShelf) return l10n.onlineDiscover;
    return titleOrShelf;
  }
  return '';
}

/// Computes localized subtitle for an online collection (Doc 22 §4.3).
String? collectionSubtitle(AppLocalizations l10n, OnlineCollection c) {
  if (c.mixKind != null) {
    final cleanT = mixTitle(c).toLowerCase();
    final rawSub = c.subtitle?.trim();

    String normalize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'\b(mix|radio)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s•\-]+'), ' ')
        .trim();

    final normT = normalize(cleanT);
    final normS = rawSub != null ? normalize(rawSub) : '';

    if (normS.isNotEmpty && normS != normT) {
      var sub = rawSub!;
      if (sub.startsWith('Mix • ')) sub = sub.substring(6).trim();
      if (sub.startsWith('Mix - ')) sub = sub.substring(6).trim();
      if (sub.startsWith('Radio • ')) sub = sub.substring(8).trim();
      return sub;
    }

    if (c.artists.isNotEmpty) {
      return c.artists.take(3).join(', ');
    }

    return switch (c.mixKind) {
      MixKind.songRadio => l10n.onlineMixSongRadio,
      MixKind.artistRadio || MixKind.artistShuffle => l10n.onlineMixArtistRadio,
      MixKind.personalMix => l10n.onlineMixPersonal,
      MixKind.playlistRadio => l10n.onlineMixPlaylistRadio,
      _ => null,
    };
  }
  return c.subtitle;
}

class OnlineArt extends StatelessWidget {
  const OnlineArt({
    super.key,
    required this.url,
    required this.size,
    this.round = false,
    this.icon = LucideIcons.music,
    this.cornerRadius = 12,
  });
  final String? url;
  final double size;
  final bool round;
  final IconData icon;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(round ? size / 2 : cornerRadius);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: radius,
      ),
      child: Icon(icon, color: Colors.white38, size: size * 0.35),
    );
    if (url == null) return fallback;
    return OptimizedImage(
      imageUrl: url,
      width: size,
      height: size,
      borderRadius: radius,
      placeholder: fallback,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.round = false,
    this.isRadio = false,
  });
  final Widget art;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool round;
  final bool isRadio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: round
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  art,
                  if (isRadio && !round)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Semantics(
                        label:
                            AppLocalizations.of(context)?.onlineRadioStation ??
                            'Radio station',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.radio,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.jostStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.jostStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnlineSongCard extends ConsumerWidget {
  const OnlineSongCard({super.key, required this.songs, required this.index});
  final List<OnlineSong> songs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = songs[index];
    return _Card(
      art: OnlineArt(url: s.thumbnail, size: 132),
      title: s.title,
      subtitle: s.artist,
      onTap: () => playOnlineSongs(ref, songs, index),
    );
  }
}

class OnlineCollectionCard extends StatelessWidget {
  const OnlineCollectionCard({super.key, required this.collection});
  final OnlineCollection collection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final artist = collection.kind == CollectionKind.artist;
    final title = mixTitle(collection);
    final subtitle = collectionSubtitle(l10n, collection);

    return _Card(
      round: artist,
      isRadio: collection.isRadio,
      art: OnlineArt(
        url: collection.thumbnail,
        size: 132,
        round: artist,
        icon: artist ? LucideIcons.user : LucideIcons.disc3,
      ),
      title: title,
      subtitle: subtitle,
      onTap: () => openOnlineCollection(context, collection),
    );
  }
}

class OnlineSectionTitle extends StatelessWidget {
  const OnlineSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.jostStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class ViewAllHeaderButton extends StatelessWidget {
  const ViewAllHeaderButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PremiumSection(
      borderRadius: BorderRadius.circular(32),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      height: 32,
      useExpanded: false,
      useBlur: true,
      forceNoBlur: true,
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.viewAll,
            style: AppFonts.jostStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(LucideIcons.arrowRight, size: 14, color: Colors.white),
        ],
      ),
    );
  }
}

class _ViewAllCircleItem extends StatelessWidget {
  const _ViewAllCircleItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 80,
              child: Text(
                l10n.viewAll,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppFonts.jostStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openShelfViewAll(BuildContext context, OnlineShelf shelf) {
  AppHaptics.light();
  final isArtistShelf =
      shelf.collections.isNotEmpty &&
      shelf.collections.every((c) => c.kind == CollectionKind.artist);
  Navigator.of(context).push(
    riseRoute(
      OnlineViewAllScreen(
        title: shelfTitle(AppLocalizations.of(context)!, shelf.title),
        browseId: shelf.moreBrowseId,
        params: shelf.moreParams,
        initialSongs: shelf.songs,
        initialCollections: shelf.collections,
        kind: isArtistShelf ? CollectionKind.artist : null,
      ),
    ),
  );
}

/// A titled online shelf rendered using the visual archetype dictated by [shelf.type].
class OnlineShelfView extends StatelessWidget {
  const OnlineShelfView({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    switch (shelf.type) {
      case OnlineShelfType.heroSpotlight:
        return _HeroSpotlightShelf(shelf: shelf);
      case OnlineShelfType.multiRowTracks:
        return _MultiRowTrackShelf(shelf: shelf);
      case OnlineShelfType.genreGrid:
        return _GenreGridShelf(shelf: shelf);
      case OnlineShelfType.artistCircles:
        return _ArtistCircleShelf(shelf: shelf);
      case OnlineShelfType.speedDial:
        return SpeedDialShelf(shelf: shelf);
      case OnlineShelfType.videoCards:
        return VideoCardShelf(shelf: shelf);
      case OnlineShelfType.discoverCards:
        return DiscoverCardShelf(shelf: shelf);
      case OnlineShelfType.featuredRelease:
        return FeaturedReleaseShelf(shelf: shelf);
      case OnlineShelfType.playlistPreview:
        return PlaylistPreviewShelf(shelf: shelf);
      case OnlineShelfType.standardCards:
        return _StandardCardShelf(shelf: shelf);
    }
  }
}

/// Template A: Hero Spotlight Carousel (Wide Inset Cards)
class _HeroSpotlightShelf extends ConsumerWidget {
  const _HeroSpotlightShelf({required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final total = shelf.songs.length + shelf.collections.length;
    final hasViewAll = total > 5 || shelf.moreBrowseId != null;

    final shelfHeight = scaler.scale(184.0);
    final cardWidth = math.min(
      360.0,
      math.max(260.0, MediaQuery.sizeOf(context).width - 64),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnlineSectionTitle(
          shelfTitle(l10n, shelf),
          trailing: hasViewAll
              ? ViewAllHeaderButton(
                  onTap: () => openShelfViewAll(context, shelf),
                )
              : null,
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: cardWidth + 14),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: math.min(10, total),
            itemBuilder: (context, i) {
              final isSong = i < shelf.songs.length;
              final song = isSong ? shelf.songs[i] : null;
              final col = !isSong
                  ? shelf.collections[i - shelf.songs.length]
                  : null;
              final title = song?.title ?? (col != null ? mixTitle(col) : '');
              final subtitle =
                  song?.artist ??
                  (col != null ? (collectionSubtitle(l10n, col) ?? '') : '');
              final thumb = song?.thumbnail ?? col?.thumbnail;
              final isRadio = col?.isRadio ?? (song != null);

              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    if (song != null) {
                      playOnlineSongs(ref, shelf.songs, i);
                    } else if (col != null) {
                      openOnlineCollection(context, col);
                    }
                  },
                  child: Container(
                    width: cardWidth,
                    height: shelfHeight - 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 1. Blurred backdrop (§7.1, M9)
                          if (thumb != null && thumb.isNotEmpty)
                            ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 30,
                                sigmaY: 30,
                              ),
                              child: OptimizedImage(
                                imageUrl: thumb,
                                width: cardWidth,
                                height: shelfHeight - 10,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF2C1947),
                                    Color(0xFF13101E),
                                  ],
                                ),
                              ),
                            ),
                          // Dark gradient scrim (black 0 -> 72%)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.15),
                                  Colors.black.withValues(alpha: 0.72),
                                ],
                              ),
                            ),
                          ),
                          // 2. Square art inset on left at full quality, radius 12 (§7.1)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: [
                                      OnlineArt(
                                        url: thumb,
                                        size: scaler.scale(100.0),
                                        round: false,
                                      ),
                                      if (isRadio)
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Semantics(
                                            label: l10n.onlineRadioStation,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.75,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Icon(
                                                LucideIcons.radio,
                                                size: 10,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppFonts.jostStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (subtitle.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppFonts.jostStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.70,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OnlinePlayButton(
                                  light: true,
                                  onTap: () {
                                    if (song != null) {
                                      playOnlineSongs(ref, shelf.songs, i);
                                    } else if (col != null) {
                                      playOnlineCollection(context, col);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Template B: Quick Picks Multi-Row Track Carousel (4 compact rows per column)
class _MultiRowTrackShelf extends ConsumerWidget {
  const _MultiRowTrackShelf({required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shelf.songs.isEmpty) {
      return _StandardCardShelf(shelf: shelf);
    }

    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final total = shelf.songs.length;
    final hasViewAll = total > 12 || shelf.moreBrowseId != null;

    final songsPerColumn = shelf.itemsPerColumn ?? 4;
    final columnCount = (total / songsPerColumn).ceil();
    final columnWidth = math.min(
      360.0,
      MediaQuery.sizeOf(context).width * 0.88,
    );
    final shelfHeight = scaler.scale(246.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnlineSectionTitle(
          shelfTitle(l10n, shelf),
          trailing: TrackShelfActions(shelf: shelf, hasViewAll: hasViewAll),
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: columnWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: math.min(6, columnCount),
            itemBuilder: (context, colIndex) {
              final startIndex = colIndex * songsPerColumn;
              final endIndex = math.min(startIndex + songsPerColumn, total);
              final colSongs = shelf.songs.sublist(startIndex, endIndex);

              return SizedBox(
                width: columnWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var r = 0; r < colSongs.length; r++)
                        _MultiRowTrackItem(
                          song: colSongs[r],
                          onTap: () =>
                              playOnlineSongs(ref, shelf.songs, startIndex + r),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Horizontal card rows: a fling moves at most one card and settles on a
/// card edge; the ends rubber-band like the rest of the app.
class CardSnapPhysics extends ScrollPhysics {
  const CardSnapPhysics({
    required this.extent,
    super.parent = const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
  });
  final double extent;

  @override
  CardSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      CardSnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    var page = position.pixels / extent;
    if (velocity < -toleranceFor(position).velocity) {
      page -= 0.5;
    } else if (velocity > toleranceFor(position).velocity) {
      page += 0.5;
    }
    final target = (page.round() * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

class _MultiRowTrackItem extends ConsumerWidget {
  const _MultiRowTrackItem({required this.song, required this.onTap});
  final OnlineSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
        child: Row(
          children: [
            OnlineArt(
              url: song.thumbnail,
              size: 46,
              icon: LucideIcons.music,
              cornerRadius: 4,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.jostStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (song.artist != null)
                    Text(
                      song.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.jostStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onPressed: () => showSongOptionsBottomSheet(
                context: context,
                ref: ref,
                song: song.toSong(),
                showEqualizerAndTechnicalInfoOptions: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Template D: Mood & Genre Compact Grid (2 rows)
class _GenreGridShelf extends StatelessWidget {
  const _GenreGridShelf({required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final total = shelf.collections.length + shelf.songs.length;
    final hasViewAll = total > 10 || shelf.moreBrowseId != null;

    const itemsPerCol = 2;
    final colCount = (total / itemsPerCol).ceil();
    final shelfHeight = scaler.scale(152.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnlineSectionTitle(
          shelfTitle(l10n, shelf),
          trailing: hasViewAll
              ? ViewAllHeaderButton(
                  onTap: () => openShelfViewAll(context, shelf),
                )
              : null,
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: math.min(10, colCount),
            itemBuilder: (context, colIndex) {
              final startIndex = colIndex * itemsPerCol;
              final endIndex = math.min(startIndex + itemsPerCol, total);

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = startIndex; i < endIndex; i++)
                      _GenreGridItem(
                        collection: i < shelf.collections.length
                            ? shelf.collections[i]
                            : null,
                        song: i >= shelf.collections.length
                            ? shelf.songs[i - shelf.collections.length]
                            : null,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GenreGridItem extends ConsumerWidget {
  const _GenreGridItem({this.collection, this.song});
  final OnlineCollection? collection;
  final OnlineSong? song;

  Color _genreColor(String title) {
    final h = title.hashCode.abs();
    final hue = (h % 360).toDouble();
    return HSLColor.fromAHSL(0.85, hue, 0.45, 0.30).toColor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = collection?.title ?? song?.title ?? '';
    final thumb = collection?.thumbnail ?? song?.thumbnail;
    final solidColor = _genreColor(title);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (collection != null) {
          openOnlineCollection(context, collection!);
        } else if (song != null) {
          playOnlineSongs(ref, [song!], 0);
        }
      },
      child: Container(
        width: 170,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: solidColor,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (thumb != null && thumb.isNotEmpty)
                Positioned.fill(
                  child: OptimizedImage(
                    imageUrl: thumb,
                    width: 170,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.jostStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Template E: Circular Artist Bubbles (96dp round avatars)
class _ArtistCircleShelf extends StatelessWidget {
  const _ArtistCircleShelf({required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final total = shelf.collections.length;
    final displayCount = math.min(15, total);
    final hasViewAll = total > 15 || shelf.moreBrowseId != null;
    final shelfHeight = scaler.scale(154.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnlineSectionTitle(
          shelfTitle(l10n, shelf),
          trailing: hasViewAll
              ? ViewAllHeaderButton(
                  onTap: () => openShelfViewAll(context, shelf),
                )
              : null,
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayCount + (hasViewAll ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= displayCount) {
                return _ViewAllCircleItem(
                  onTap: () => openShelfViewAll(context, shelf),
                );
              }
              final artist = shelf.collections[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(48),
                  onTap: () => openOnlineCollection(context, artist),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OnlineArt(
                        url: artist.thumbnail,
                        size: 96,
                        round: true,
                        icon: LucideIcons.user,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 96,
                        child: Text(
                          artist.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppFonts.jostStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }
}

/// Template C: Standard Album / Playlist Shelf (140dp rounded cards)
class _StandardCardShelf extends StatelessWidget {
  const _StandardCardShelf({required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final total = shelf.songs.length + shelf.collections.length;
    final displayCount = math.min(15, total);
    final hasViewAll = total > 15 || shelf.moreBrowseId != null;
    final isArtistShelf =
        shelf.collections.isNotEmpty &&
        shelf.collections.every((c) => c.kind == CollectionKind.artist);
    final shelfHeight = scaler.scale(196.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnlineSectionTitle(
          shelfTitle(l10n, shelf),
          trailing: hasViewAll
              ? ViewAllHeaderButton(
                  onTap: () => openShelfViewAll(context, shelf),
                )
              : null,
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayCount + (hasViewAll ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= displayCount) {
                final subtitle = isArtistShelf
                    ? '$total ${l10n.artists.toLowerCase()}'
                    : (shelf.songs.isNotEmpty
                          ? '$total ${l10n.songs.toLowerCase()}'
                          : '$total ${l10n.albums.toLowerCase()}');
                return _Card(
                  round: isArtistShelf,
                  art: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: isArtistShelf
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: isArtistShelf
                          ? null
                          : BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Center(
                      child: Icon(
                        LucideIcons.arrowRight,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  title: l10n.viewAll,
                  subtitle: subtitle,
                  onTap: () => openShelfViewAll(context, shelf),
                );
              }
              return i < shelf.songs.length
                  ? OnlineSongCard(songs: shelf.songs, index: i)
                  : OnlineCollectionCard(
                      collection: shelf.collections[i - shelf.songs.length],
                    );
            },
          ),
        ),
      ],
    );
  }
}

/// Full screen view for an online shelf displaying all its songs and collections.
class OnlineShelfAllScreen extends ConsumerWidget {
  const OnlineShelfAllScreen({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final title = shelfTitle(l10n, shelf.title);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          title,
          style: AppFonts.jostStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          if (shelf.songs.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.play),
              onPressed: () => playOnlineSongs(ref, shelf.songs, 0),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (shelf.songs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.songs,
                      style: AppFonts.jostStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${shelf.songs.length}',
                      style: AppFonts.jostStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: shelf.songs.length,
              itemBuilder: (context, i) {
                final song = shelf.songs[i].toSong();
                return SongTile(
                  song: song,
                  l10n: l10n,
                  songs: [for (final s in shelf.songs) s.toSong()],
                  showAlbum: true,
                );
              },
            ),
          ],
          if (shelf.collections.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  l10n.albums,
                  style: AppFonts.jostStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: shelf.collections.length,
                itemBuilder: (context, i) =>
                    OnlineCollectionCard(collection: shelf.collections[i]),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

/// Small skeleton row shown while the first online load runs.
class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 186,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

/// The refresh control: spins while loading. Resets the online connection
/// (identity, cached URLs, throttle hold) and reloads.
class OnlineRefreshButton extends ConsumerWidget {
  const OnlineRefreshButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loading = ref.watch(onlineHomeProvider.select((s) => s.loading));
    return IconButton(
      tooltip: l10n.onlineRefresh,
      onPressed: loading
          ? null
          : () {
              AppHaptics.medium();
              ref.read(onlineHomeProvider.notifier).refresh();
            },
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.refreshCw, color: Colors.white, size: 20),
    );
  }
}

class _MoodChipsRow extends ConsumerWidget {
  const _MoodChipsRow({required this.moods, this.activeMood});
  final List<OnlineMood> moods;
  final OnlineMood? activeMood;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (moods.isEmpty) return const SizedBox.shrink();
    final accent = ref.watch(settingsProvider).accent;
    final loading = ref.watch(onlineHomeProvider.select((s) => s.loading));

    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: moods.length,
        itemBuilder: (context, i) {
          final mood = moods[i];
          final isSelected = activeMood == mood;
          final isRefreshing = isSelected && loading;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                AppHaptics.selection();
                ref.read(onlineHomeProvider.notifier).selectMood(mood);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? accent : Colors.white12,
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRefreshing) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      mood.title,
                      style: AppFonts.jostStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Home's online block, as one sliver.
/// The whole online block in its default order (desktop dashboard). Android
/// Home places the three parts on their own, see docs/online/27.
class OnlineHomeSliver extends StatelessWidget {
  const OnlineHomeSliver({super.key});

  @override
  Widget build(BuildContext context) => const SliverMainAxisGroup(
    slivers: [OnlineFeedSliver(), OnlineArtistsSliver(), OnlineMoreSliver()],
  );
}

/// Shelves shown before Artists for you.
const _topShelfCount = 2;

/// Mood chips, loading bar, status cards and the first 2 YouTube shelves.
class OnlineFeedSliver extends ConsumerWidget {
  const OnlineFeedSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(onlineActiveProvider)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final l10n = AppLocalizations.of(context)!;
    final home = ref.watch(onlineHomeProvider);
    final taste = ref.watch(tasteProvider);
    final firstLoad = home.loading && home.shelves.isEmpty;
    final topShelves = home.shelves.take(_topShelfCount).toList();

    return SliverMainAxisGroup(
      slivers: [
        if (home.moods.isNotEmpty)
          SliverToBoxAdapter(
            child: _MoodChipsRow(
              moods: home.moods,
              activeMood: home.activeMood,
            ),
          ),
        if (home.loading && home.shelves.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(2)),
                child: LinearProgressIndicator(
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ),
        if (!taste.seen && taste.artists.isEmpty)
          SliverToBoxAdapter(child: _PersonalizeCard(l10n: l10n)),
        if (home.error != null && home.shelves.isEmpty)
          SliverToBoxAdapter(
            child: _ErrorCard(
              message: l10n.onlineLoadFailed,
              onRetry: () => ref.read(onlineHomeProvider.notifier).refresh(),
            ),
          ),
        if (firstLoad)
          const SliverToBoxAdapter(child: _ShelfSkeleton())
        else if (topShelves.isNotEmpty)
          SliverList.builder(
            itemCount: topShelves.length,
            itemBuilder: (_, i) => OnlineShelfView(shelf: topShelves[i]),
          ),
      ],
    );
  }
}

/// Artists for you, hidden during the first load like before.
class OnlineArtistsSliver extends ConsumerWidget {
  const OnlineArtistsSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show =
        ref.watch(onlineActiveProvider) &&
        !ref.watch(
          onlineHomeProvider.select((h) => h.loading && h.shelves.isEmpty),
        );
    return SliverToBoxAdapter(
      child: show ? const _ArtistsForYouRow() : const SizedBox.shrink(),
    );
  }
}

/// The YouTube shelves after the first 2.
class OnlineMoreSliver extends ConsumerWidget {
  const OnlineMoreSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(onlineHomeProvider);
    final firstLoad = home.loading && home.shelves.isEmpty;
    if (!ref.watch(onlineActiveProvider) ||
        firstLoad ||
        home.shelves.length <= _topShelfCount) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final remaining = home.shelves.skip(_topShelfCount).toList();
    return SliverList.builder(
      itemCount: remaining.length,
      itemBuilder: (_, i) => OnlineShelfView(shelf: remaining[i]),
    );
  }
}

class _ArtistsForYouRow extends ConsumerWidget {
  const _ArtistsForYouRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = ref.watch(onlineArtistsForYouProvider);
    return artistsAsync.when(
      data: (artists) {
        if (artists.isEmpty) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context)!;
        final displayCount = math.min(20, artists.length);
        final showMore = artists.length >= 15 || AccountAuth.instance.signedIn;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnlineSectionTitle(
              l10n.artistsForYou,
              trailing: showMore
                  ? ViewAllHeaderButton(
                      onTap: () =>
                          _openOnlineArtistsViewAll(context, ref, artists),
                    )
                  : null,
            ),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: displayCount + (showMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= displayCount) {
                    return _ViewAllCircleItem(
                      onTap: () =>
                          _openOnlineArtistsViewAll(context, ref, artists),
                    );
                  }
                  final artist = artists[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () => openOnlineCollection(
                        context,
                        OnlineCollection(
                          browseId: artist.browseId,
                          title: artist.name,
                          kind: CollectionKind.artist,
                          thumbnail: artist.thumbnail,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OnlineArt(
                            url: artist.thumbnail,
                            size: 80,
                            round: true,
                            icon: LucideIcons.user,
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 80,
                            child: Text(
                              artist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppFonts.jostStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
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
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

void _openOnlineArtistsViewAll(
  BuildContext context,
  WidgetRef ref,
  List<OnlineArtistForYou> artists,
) {
  AppHaptics.light();
  final l10n = AppLocalizations.of(context)!;
  final signedIn = AccountAuth.instance.signedIn;
  Navigator.of(context).push(
    riseRoute(
      OnlineViewAllScreen(
        title: l10n.artistsForYou,
        browseId: signedIn ? 'FEmusic_library_corpus_artists' : null,
        initialCollections: [
          for (final a in artists)
            OnlineCollection(
              browseId: a.browseId,
              title: a.name,
              kind: CollectionKind.artist,
              thumbnail: a.thumbnail,
            ),
        ],
        kind: CollectionKind.artist,
      ),
    ),
  );
}

class _PersonalizeCard extends StatelessWidget {
  const _PersonalizeCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openTasteSetup(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.onlinePersonalizeTitle,
                        style: AppFonts.jostStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.onlinePersonalizeBody,
                        style: AppFonts.jostStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.cloudOff, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppFonts.jostStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.onlineRefresh)),
        ],
      ),
    );
  }
}

/// Online results under the local ones in search, as one sliver.
class OnlineSearchSliver extends ConsumerStatefulWidget {
  const OnlineSearchSliver({
    super.key,
    required this.query,
    this.hideIds = const {},
  });
  final String query;

  /// Paths already shown as local results (online twins are hidden).
  final Set<String> hideIds;

  @override
  ConsumerState<OnlineSearchSliver> createState() => _OnlineSearchSliverState();
}

class _OnlineSearchSliverState extends ConsumerState<OnlineSearchSliver> {
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(OnlineSearchSliver old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  void _search() {
    final q = widget.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(onlineSearchProvider.notifier).search(q);
    });
  }

  Widget _cards(List<OnlineCollection> items) => SizedBox(
    height: 186,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: items.length,
      itemBuilder: (_, i) => OnlineCollectionCard(collection: items[i]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(onlineActiveProvider)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(onlineSearchProvider);
    final songs = s.songs
        .where((x) => !widget.hideIds.contains(x.path))
        .toList();
    final asSongs = [for (final x in songs) x.toSong()];

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: OnlineSectionTitle(
            l10n.onlineMusic,
            trailing: s.loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (s.error != null)
          SliverToBoxAdapter(
            child: _ErrorCard(
              message: l10n.onlineLoadFailed,
              onRetry: () async {
                await ref.read(onlineHomeProvider.notifier).refresh();
                await ref.read(onlineSearchProvider.notifier).retry();
              },
            ),
          )
        else if (!s.loading && s.isEmpty && s.query.length >= 2)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.onlineNoResults,
                style: AppFonts.jostStyle(color: Colors.white54),
              ),
            ),
          ),
        if (s.artists.isNotEmpty) ...[
          SliverToBoxAdapter(child: OnlineSectionTitle(l10n.artists)),
          SliverToBoxAdapter(child: _cards(s.artists)),
        ],
        if (asSongs.isNotEmpty) ...[
          SliverToBoxAdapter(child: OnlineSectionTitle(l10n.songs)),
          SliverList.builder(
            itemCount: asSongs.length,
            itemBuilder: (context, i) => SongTile(
              key: ValueKey('online-${asSongs[i].path}'),
              song: asSongs[i],
              songs: asSongs,
              l10n: l10n,
              // Searches feed the taste profile, like local search does.
              onPlay: () =>
                  ref.read(recentSearchesProvider.notifier).add(widget.query),
            ),
          ),
          if (s.continuation != null)
            SliverToBoxAdapter(
              child: Center(
                child: s.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () =>
                            ref.read(onlineSearchProvider.notifier).loadMore(),
                        child: Text(l10n.onlineLoadMore),
                      ),
              ),
            ),
        ],
        if (s.albums.isNotEmpty) ...[
          SliverToBoxAdapter(child: OnlineSectionTitle(l10n.albums)),
          SliverToBoxAdapter(child: _cards(s.albums)),
        ],
        if (s.playlists.isNotEmpty) ...[
          SliverToBoxAdapter(child: OnlineSectionTitle(l10n.playlists)),
          SliverToBoxAdapter(child: _cards(s.playlists)),
        ],
      ],
    );
  }
}

/// A button indicating the online connection state matching the top bar button style.
/// Tapping opens Settings > Online music; long-pressing triggers a refresh.
class OnlineStatusIndicator extends ConsumerWidget {
  const OnlineStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(onlineActiveProvider)) return const SizedBox.shrink();

    final status = ref.watch(onlineStatusProvider);
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    final l10n = AppLocalizations.of(context)!;

    final (icon, color, semanticLabel) = switch (status) {
      OnlineStatus.online => (LucideIcons.cloud, accent, l10n.onlineStatusOn),
      OnlineStatus.limited => (
        LucideIcons.cloud,
        Colors.amber,
        l10n.onlineStatusLimited,
      ),
      OnlineStatus.offline => (
        LucideIcons.cloudOff,
        Colors.white38,
        l10n.onlineStatusOffline,
      ),
    };

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Tooltip(
        message: semanticLabel,
        child: GestureDetector(
          onLongPress: () async {
            AppHaptics.medium();
            await ref.read(onlineHomeProvider.notifier).refresh();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.onlineRefreshed)));
            }
          },
          child: PremiumSection(
            borderRadius: BorderRadius.circular(10),
            width: 48,
            height: 48,
            useExpanded: false,
            useBlur: true,
            forceNoBlur: true,
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            onTap: () {
              AppHaptics.light();
              ref
                  .read(appNavigationProvider.notifier)
                  .showSettingsCategory(id: 'online', title: l10n.onlineMusic);
            },
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}

/// A footer card shown at the end of the home screen when online mode is disabled,
/// prompting the user to enable online mode in Settings.
class OnlineDisabledHomeFooter extends ConsumerWidget {
  const OnlineDisabledHomeFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(onlineActiveProvider)) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    return MochyCardRow(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      icon: LucideIcons.cloud,
      title: '${l10n.onlineMusic} is off',
      subtitle: 'Enable online mode in Settings to stream and discover music.',
      trailing: const Icon(
        LucideIcons.chevronRight,
        color: MochyColors.secondary,
        size: 20,
      ),
      onTap: () {
        AppHaptics.light();
        ref
            .read(appNavigationProvider.notifier)
            .showSettingsCategory(id: 'online', title: l10n.onlineMusic);
      },
    );
  }
}
