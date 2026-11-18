import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:looper_player/ui/widgets/common/home_design_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/common/premium_section.dart';
import 'package:looper_player/ui/widgets/sheets/song_options_bottom_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Round play button with its own tap target. [light]: white disc, black
/// icon (on artwork); otherwise a translucent disc (on dark cards).
class OnlinePlayButton extends StatelessWidget {
  const OnlinePlayButton({
    super.key,
    required this.onTap,
    this.light = false,
    this.size = 44,
  });
  final VoidCallback onTap;
  final bool light;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)?.play ?? 'Play',
      excludeSemantics: true,
      child: Material(
        color: light ? Colors.white : Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              Icons.play_arrow_rounded,
              size: size * 0.62,
              color: light ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Header actions for song shelves: a "Play all" pill and, when the shelf
/// has more to show, an arrow to its full list.
class TrackShelfActions extends ConsumerWidget {
  const TrackShelfActions({
    super.key,
    required this.shelf,
    required this.hasViewAll,
  });
  final OnlineShelf shelf;
  final bool hasViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shelf.songs.isNotEmpty)
          // Round play button, as in the design.
          HomeRoundButton(
            semanticLabel: l10n.playAll,
            onTap: () {
              AppHaptics.light();
              playOnlineSongs(ref, shelf.songs, 0);
            },
            child: homeSectionPlayIcon,
          ),
        if (hasViewAll) ...[
          const SizedBox(width: 6),
          ViewAllHeaderButton(onTap: () => openShelfViewAll(context, shelf)),
        ],
      ],
    );
  }
}

Widget _header(BuildContext context, OnlineShelf shelf, {bool tracks = false}) {
  final l10n = AppLocalizations.of(context)!;
  final total = shelf.songs.length + shelf.collections.length;
  final hasViewAll = shelf.moreBrowseId != null || total > 10;
  return OnlineSectionTitle(
    shelfTitle(l10n, shelf),
    name: shelf.args.firstOrNull,
    trailing: tracks
        ? TrackShelfActions(shelf: shelf, hasViewAll: hasViewAll)
        : hasViewAll
        ? ViewAllHeaderButton(onTap: () => openShelfViewAll(context, shelf))
        : null,
  );
}

/// Falls back to plain cards when a shelf lacks what a style needs.
Widget _standard(OnlineShelf shelf) => OnlineShelfView(
  shelf: shelf.copyWith(shelfType: OnlineShelfType.standardCards),
);

void _songMenu(BuildContext context, WidgetRef ref, OnlineSong s) =>
    showSongOptionsBottomSheet(
      context: context,
      ref: ref,
      song: s.toSong(),
      showEqualizerAndTechnicalInfoOptions: false,
    );

TextStyle _title(double size) => homeDisplay(
  color: Colors.white,
  fontSize: size,
  fontWeight: FontWeight.w600,
);

/// Grey card subtitle ("AutoFidelity · 334K Views").
TextStyle get _cardSub =>
    homeDisplay(color: kHomeGrey, fontSize: 14, fontWeight: FontWeight.w500);

TextStyle _sub(double size) => AppFonts.jostStyle(
  color: Colors.white.withValues(alpha: 0.6),
  fontSize: size,
);

/// Speed dial: pages of 3x3 square tiles with the title over the artwork.
class SpeedDialShelf extends ConsumerStatefulWidget {
  const SpeedDialShelf({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  ConsumerState<SpeedDialShelf> createState() => _SpeedDialShelfState();
}

class _SpeedDialShelfState extends ConsumerState<SpeedDialShelf> {
  final _page = ValueNotifier(0);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.shelf.songs;
    if (songs.length < 9) return _standard(widget.shelf);
    const gap = 8.0;
    final size = MediaQuery.sizeOf(context);
    final avail = size.width - 32;
    // 3 rows that fit in 3/4 of the screen height; landscape adds columns.
    final maxTile = math.min(150.0, (size.height * 0.75 - gap * 2) / 3);
    final cols = math.max(3, ((avail + gap) / (maxTile + gap)).ceil());
    final tile = (avail - gap * (cols - 1)) / cols;
    final perPage = cols * 3;
    final count = songs.length < perPage
        ? songs.length
        : math.min(perPage * 3, songs.length) ~/ perPage * perPage;
    final pages = (count / perPage).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, widget.shelf, tracks: true),
        SizedBox(
          height: tile * 3 + gap * 2,
          child: PageView.builder(
            itemCount: pages,
            onPageChanged: (p) => _page.value = p,
            itemBuilder: (context, p) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (
                    var i = p * perPage;
                    i < math.min(count, p * perPage + perPage);
                    i++
                  )
                    _SpeedDialTile(songs: songs, index: i, size: tile),
                ],
              ),
            ),
          ),
        ),
        if (pages > 1)
          ValueListenableBuilder(
            valueListenable: _page,
            builder: (_, current, _) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var p = 0; p < pages; p++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p == current ? Colors.white : Colors.white30,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SpeedDialTile extends ConsumerWidget {
  const _SpeedDialTile({
    required this.songs,
    required this.index,
    required this.size,
  });
  final List<OnlineSong> songs;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = songs[index];
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            OnlineArt(url: s.thumbnail, size: size, cornerRadius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _title(14).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => playOnlineSongs(ref, songs, index),
                onLongPress: () => _songMenu(context, ref, s),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Music videos: wide 16:9 cards with a duration badge.
class VideoCardShelf extends ConsumerWidget {
  const VideoCardShelf({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = shelf.songs;
    if (songs.isEmpty) return _standard(shelf);
    final scaler = MediaQuery.textScalerOf(context);
    final cardW = math.min(400.0, MediaQuery.sizeOf(context).width * 0.82);
    final artH = cardW * 9 / 16;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, shelf, tracks: true),
        SizedBox(
          height: artH + 8 + scaler.scale(44),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: cardW + 12),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: math.min(15, songs.length),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final s = songs[i];
              final d = s.durationMs;
              return SizedBox(
                width: cardW,
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => playOnlineSongs(ref, songs, i),
                  onLongPress: () => _songMenu(context, ref, s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          OptimizedImage(
                            imageUrl: s.thumbnail,
                            width: cardW,
                            height: artH,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          if (d != null && d > 0)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  formatOnlineDuration(d),
                                  style: _title(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _title(15),
                      ),
                      if (s.artist != null)
                        Text(
                          s.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sub(13),
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

/// `m:ss`, or `h:mm:ss` past an hour.
String formatOnlineDuration(int ms) {
  final d = Duration(milliseconds: ms);
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours == 0) return '${d.inMinutes}:$s';
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  return '${d.inHours}:$m:$s';
}

/// Daily discover: large artwork cards, title on top, play at the bottom.
class DiscoverCardShelf extends ConsumerWidget {
  const DiscoverCardShelf({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = shelf.songs;
    if (songs.isEmpty) return _standard(shelf);
    final size = MediaQuery.sizeOf(context);
    final cardW = math.min(
      360.0,
      math.min(size.width * 0.84, size.height * 0.7),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, shelf, tracks: true),
        SizedBox(
          height: cardW,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: cardW + 12),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: math.min(10, songs.length),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final s = songs[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => playOnlineSongs(ref, songs, i),
                onLongPress: () => _songMenu(context, ref, s),
                child: SizedBox.square(
                  dimension: cardW,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        OnlineArt(
                          url: s.thumbnail,
                          size: cardW,
                          cornerRadius: 0,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _title(17),
                              ),
                              if (s.artist != null)
                                Text(
                                  s.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _sub(14),
                                ),
                              const Spacer(),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.album == s.title ? '' : s.album ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: _sub(13),
                                    ),
                                  ),
                                  OnlinePlayButton(
                                    light: true,
                                    onTap: () => playOnlineSongs(ref, songs, i),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

/// New releases: text and play button on the left, big artwork on the right.
class FeaturedReleaseShelf extends StatelessWidget {
  const FeaturedReleaseShelf({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    final items = shelf.collections;
    if (items.isEmpty) return _standard(shelf);
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final cardW = math.min(480.0, width * 0.9);
    final art = math.min(180.0, cardW * 0.44);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, shelf),
        SizedBox(
          height: math.max(art, scaler.scale(150)),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: cardW),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: math.min(10, items.length),
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final c = items[i];
              final sub = collectionSubtitle(l10n, c);
              return SizedBox(
                width: cardW - 16,
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => openOnlineCollection(context, c),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mixTitle(c),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _title(18),
                              ),
                              if (sub != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _sub(14),
                                ),
                              ],
                              const Spacer(),
                              OnlinePlayButton(
                                onTap: () => playOnlineCollection(context, c),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: OnlineArt(
                          url: c.thumbnail,
                          size: art,
                          cornerRadius: 5,
                          icon: LucideIcons.disc3,
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

/// Playlist cards: artwork, title, play button and the first 3 songs.
class PlaylistPreviewShelf extends StatelessWidget {
  const PlaylistPreviewShelf({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context) {
    final items = shelf.collections;
    if (items.isEmpty) return _standard(shelf);
    final scaler = MediaQuery.textScalerOf(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > size.height;
    final cardW = wide
        ? math.min(680.0, size.width * 0.8)
        : math.min(400.0, size.width * 0.74);
    final rows = _PlaylistPreviewCard.rowCount * scaler.scale(56);
    final height = wide
        ? 18 + math.max(128 + scaler.scale(56), rows) + 14.0
        : 18 + math.max(54.0, scaler.scale(56)) + 18 + rows + 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, shelf),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: cardW + 20),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: math.min(10, items.length),
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder: (context, i) => _PlaylistPreviewCard(
              collection: items[i],
              width: cardW,
              wide: wide,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistPreviewCard extends ConsumerWidget {
  const _PlaylistPreviewCard({
    required this.collection,
    required this.width,
    required this.wide,
  });
  final OnlineCollection collection;
  final double width;

  /// Landscape: artwork and title on the left, songs on the right.
  final bool wide;

  static const rowCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final c = collection;
    final sub = collectionSubtitle(l10n, c);
    final hue = (c.title.hashCode.abs() % 360).toDouble();
    final page = ref.watch(onlinePageProvider(onlinePageIdOf(c)));
    final songs = page.value?.songs ?? const <OnlineSong>[];

    Widget art(double size) => OnlineArt(
      url: c.thumbnail,
      size: size,
      cornerRadius: 5,
      icon: LucideIcons.listMusic,
    );
    final header = SizedBox(
      height: math.max(54.0, scaler.scale(56)),
      child: Row(
        children: [
          if (!wide) ...[art(54), const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  mixTitle(c),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _title(18).copyWith(fontWeight: FontWeight.bold),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _cardSub,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: OnlinePlayButton(
              light: true,
              size: 49,
              onTap: () => songs.isNotEmpty
                  ? playOnlineSongs(ref, songs, 0)
                  : playOnlineCollection(context, c),
            ),
          ),
        ],
      ),
    );
    final rows = [
      for (var i = 0; i < rowCount; i++)
        SizedBox(
          height: scaler.scale(56),
          child: i < songs.length
              ? _PreviewRow(songs: songs, index: i)
              : const SizedBox.shrink(),
        ),
    ];

    return Material(
      color: HSLColor.fromAHSL(1, hue, 0.15, 0.075).toColor(),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openOnlineCollection(context, c),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 8, 14),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            art(120),
                            const SizedBox(height: 8),
                            header,
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(children: rows)),
                    ],
                  )
                : Column(
                    children: [header, const SizedBox(height: 18), ...rows],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends ConsumerWidget {
  const _PreviewRow({required this.songs, required this.index});
  final List<OnlineSong> songs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = songs[index];
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => playOnlineSongs(ref, songs, index),
      child: Row(
        children: [
          OnlineArt(url: s.thumbnail, size: 42, cornerRadius: 5),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: homeCardTitle(),
                ),
                if (s.artist != null)
                  Text(
                    s.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: homeCardSub(),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            icon: const Icon(Icons.more_vert, size: 22, color: Colors.white),
            onPressed: () => _songMenu(context, ref, s),
          ),
        ],
      ),
    );
  }
}

/// Mixes ("My Mix 1"…): wide short cards with the cover, title, subtitle
/// and a white play button on a dark gradient tinted per mix.
class MixCardShelf extends ConsumerWidget {
  const MixCardShelf({super.key, required this.shelf});
  final OnlineShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = shelf.collections;
    if (items.isEmpty) return _standard(shelf);
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.sizeOf(context).width;
    final cardW = math.min(400.0, width * 0.74);
    final height = math.max(96.0, MediaQuery.textScalerOf(context).scale(96));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, shelf),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: CardSnapPhysics(extent: cardW + 20),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: math.min(10, items.length),
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder: (context, i) {
              final c = items[i];
              final sub = collectionSubtitle(l10n, c);
              final hue = (c.title.hashCode.abs() % 360).toDouble();
              return Material(
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  width: cardW,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        HSLColor.fromAHSL(1, hue, 0.25, 0.07).toColor(),
                        HSLColor.fromAHSL(
                          1,
                          (hue + 25) % 360,
                          0.55,
                          0.1,
                        ).toColor(),
                      ],
                    ),
                  ),
                  child: InkWell(
                    onTap: () => openOnlineCollection(context, c),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      child: Row(
                        children: [
                          OnlineArt(
                            url: c.thumbnail,
                            size: 54,
                            cornerRadius: 5,
                            icon: LucideIcons.listMusic,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  mixTitle(c),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _title(
                                    18,
                                  ).copyWith(fontWeight: FontWeight.bold),
                                ),
                                if (sub != null)
                                  Text(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _cardSub,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OnlinePlayButton(
                            light: true,
                            size: 49,
                            onTap: () => playOnlineCollection(context, c),
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
