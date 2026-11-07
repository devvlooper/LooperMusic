import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
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
import 'package:looper_player/features/online/presentation/online_view_all_screen.dart';
import 'package:looper_player/features/online/presentation/taste_setup_screen.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/widgets/premium_section.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Play [songs] as the queue, starting at [index].
void playOnlineSongs(WidgetRef ref, List<OnlineSong> songs, int index) {
  AppHaptics.light();
  ref
      .read(playbackProvider.notifier)
      .setPlaylist([for (final s in songs) s.toSong()], initialIndex: index);
}

void openOnlineCollection(BuildContext context, OnlineCollection c) {
  AppHaptics.light();
  Navigator.of(context).push(riseRoute(OnlineCollectionScreen(collection: c)));
}

void openTasteSetup(BuildContext context) {
  Navigator.of(context).push(riseRoute(const TasteSetupScreen()));
}

String shelfTitle(AppLocalizations l10n, String title) => switch (title) {
  discoverShelf => l10n.onlineDiscover,
  _ => title,
};

class OnlineArt extends StatelessWidget {
  const OnlineArt({
    super.key,
    required this.url,
    required this.size,
    this.round = false,
    this.icon = LucideIcons.music,
  });
  final String? url;
  final double size;
  final bool round;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(round ? size / 2 : 12);
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
  });
  final Widget art;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool round;

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
              art,
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
    final artist = collection.kind == CollectionKind.artist;
    return _Card(
      round: artist,
      art: OnlineArt(
        url: collection.thumbnail,
        size: 132,
        round: artist,
        icon: artist ? LucideIcons.user : LucideIcons.disc3,
      ),
      title: collection.title,
      subtitle: collection.subtitle,
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
                child: Icon(LucideIcons.arrowRight, size: 24, color: Colors.white),
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

void _openShelfViewAll(BuildContext context, OnlineShelf shelf) {
  AppHaptics.light();
  final isArtistShelf = shelf.collections.isNotEmpty &&
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

/// A titled horizontal row of song and/or collection cards.
class OnlineShelfView extends StatelessWidget {
  const OnlineShelfView({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = shelf.songs.length + shelf.collections.length;
    final displayCount = math.min(15, total);
    final hasViewAll = total > 15 || shelf.moreBrowseId != null;
    final isArtistShelf = shelf.collections.isNotEmpty &&
        shelf.collections.every((c) => c.kind == CollectionKind.artist);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnlineSectionTitle(
          shelfTitle(l10n, shelf.title),
          trailing: hasViewAll
              ? ViewAllHeaderButton(
                  onTap: () => _openShelfViewAll(context, shelf),
                )
              : null,
        ),
        SizedBox(
          height: 186,
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
                      shape:
                          isArtistShelf ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius:
                          isArtistShelf ? null : BorderRadius.circular(12),
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
                  onTap: () => _openShelfViewAll(context, shelf),
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
                itemBuilder: (context, i) => OnlineCollectionCard(
                  collection: shelf.collections[i],
                ),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
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
class OnlineHomeSliver extends ConsumerWidget {
  const OnlineHomeSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(onlineActiveProvider)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final l10n = AppLocalizations.of(context)!;
    final home = ref.watch(onlineHomeProvider);
    final taste = ref.watch(tasteProvider);
    final firstLoad = home.loading && home.shelves.isEmpty;

    // Position Artists For You between online shelves (after the first 2 shelves)
    final topShelvesCount = math.min(2, home.shelves.length);
    final topShelves = home.shelves.take(topShelvesCount).toList();
    final remainingShelves = home.shelves.skip(topShelvesCount).toList();

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
        if (firstLoad) ...[
          const SliverToBoxAdapter(child: _ShelfSkeleton()),
        ] else ...[
          if (topShelves.isNotEmpty)
            SliverList.builder(
              itemCount: topShelves.length,
              itemBuilder: (_, i) => OnlineShelfView(shelf: topShelves[i]),
            ),
          const SliverToBoxAdapter(child: _ArtistsForYouRow()),
          if (remainingShelves.isNotEmpty)
            SliverList.builder(
              itemCount: remainingShelves.length,
              itemBuilder: (_, i) => OnlineShelfView(shelf: remainingShelves[i]),
            ),
        ],
      ],
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
    final songs = s.songs.where((x) => !widget.hideIds.contains(x.path)).toList();
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.onlineRefreshed)),
              );
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
              ref.read(appNavigationProvider.notifier).showSettingsCategory(
                    id: 'online',
                    title: l10n.onlineMusic,
                  );
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
    final accent = ref.watch(settingsProvider.select((s) => s.accent));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AppHaptics.light();
          ref.read(appNavigationProvider.notifier).showSettingsCategory(
                id: 'online',
                title: l10n.onlineMusic,
              );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.cloud,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.onlineMusic} is off',
                      style: AppFonts.jostStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enable online mode in Settings to stream and discover music.',
                      style: AppFonts.jostStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                LucideIcons.chevronRight,
                color: Colors.white38,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
