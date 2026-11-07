import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/looper_scroll_physics.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/song_tile.dart';
import 'package:looper_player/features/online/data/online_api.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/collection_detail/collection_pinned_bar.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Full screen paginated view for online shelves, online artists, and
/// online playlists/albums. Supports infinite scrolling with continuation tokens.
class OnlineViewAllScreen extends ConsumerStatefulWidget {
  const OnlineViewAllScreen({
    super.key,
    required this.title,
    this.browseId,
    this.params,
    this.initialSongs = const [],
    this.initialCollections = const [],
    this.kind,
  });

  final String title;
  final String? browseId;
  final String? params;
  final List<OnlineSong> initialSongs;
  final List<OnlineCollection> initialCollections;
  final CollectionKind? kind;

  @override
  ConsumerState<OnlineViewAllScreen> createState() =>
      _OnlineViewAllScreenState();
}

class _OnlineViewAllScreenState extends ConsumerState<OnlineViewAllScreen> {
  late final ScrollController _controller = ScrollController();
  final GlobalKey _titleKey = GlobalKey();

  late final List<OnlineSong> _songs = List.from(widget.initialSongs);
  late final List<OnlineCollection> _collections =
      List.from(widget.initialCollections);

  String? _continuationToken;
  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;
  bool _hasAttemptedFirstFetch = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    if (widget.browseId != null) {
      unawaited(_fetchInitial());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 350 &&
        !_isLoadingMore &&
        !_isLoadingInitial &&
        _continuationToken != null) {
      _loadMore();
    }
  }

  Future<void> _fetchInitial() async {
    if (_hasAttemptedFirstFetch || widget.browseId == null) return;
    _hasAttemptedFirstFetch = true;

    if (_songs.isEmpty && _collections.isEmpty) {
      setState(() => _isLoadingInitial = true);
    }

    try {
      final (shelf, token) = await OnlineApi.listPage(
        widget.browseId,
        widget.title,
        params: widget.params,
        automatic: true,
      );

      if (!mounted) return;
      setState(() {
        final seenSongs = {for (final s in _songs) s.videoId};
        final seenCards = {for (final c in _collections) c.browseId};

        _songs.addAll(shelf.songs.where((s) => seenSongs.add(s.videoId)));
        _collections.addAll(
          shelf.collections.where((c) => seenCards.add(c.browseId)),
        );
        _continuationToken = token;
        _isLoadingInitial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _loadMore() async {
    final token = _continuationToken;
    if (token == null || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final (shelf, nextToken) = await OnlineApi.listPage(
        null,
        widget.title,
        continuation: token,
        automatic: true,
      );

      if (!mounted) return;
      setState(() {
        final seenSongs = {for (final s in _songs) s.videoId};
        final seenCards = {for (final c in _collections) c.browseId};

        _songs.addAll(shelf.songs.where((s) => seenSongs.add(s.videoId)));
        _collections.addAll(
          shelf.collections.where((c) => seenCards.add(c.browseId)),
        );
        _continuationToken = nextToken;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalCount = _songs.length + _collections.length;
    final isArtistMode = widget.kind == CollectionKind.artist ||
        (_collections.isNotEmpty &&
            _collections.every((c) => c.kind == CollectionKind.artist));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(
            parent: LooperScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: CollectionPinnedBar(
                controller: _controller,
                titleKey: _titleKey,
                title: widget.title,
                onBack: () => Navigator.of(context).maybePop(),
                onAdd: _songs.isNotEmpty
                    ? () => playOnlineSongs(ref, _songs, 0)
                    : null,
                actionIcon: _songs.isNotEmpty ? LucideIcons.play : null,
              ),
            ),

            // Header Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      key: _titleKey,
                      style: AppFonts.jostStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isArtistMode
                          ? '$totalCount ${l10n.artists.toLowerCase()}'
                          : (_songs.isNotEmpty
                              ? '$totalCount ${l10n.songs.toLowerCase()}'
                              : '$totalCount ${l10n.albums.toLowerCase()}'),
                      style: AppFonts.jostStyle(
                        fontSize: 13,
                        color: Colors.white38,
                      ),
                    ),
                    if (_songs.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              AppHaptics.light();
                              playOnlineSongs(ref, _songs, 0);
                            },
                            icon: const Icon(LucideIcons.play, size: 18),
                            label: Text(l10n.playAll),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              AppHaptics.light();
                              final shuffled = List<OnlineSong>.from(_songs)
                                ..shuffle();
                              ref.read(playbackProvider.notifier).setPlaylist(
                                    [for (final s in shuffled) s.toSong()],
                                    initialIndex: 0,
                                  );
                            },
                            icon: const Icon(LucideIcons.shuffle, size: 18),
                            label: Text(l10n.shuffleTitle),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Initial Loading Spinner
            if (_isLoadingInitial)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // Songs Section
              if (_songs.isNotEmpty)
                SliverList.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, i) {
                    final song = _songs[i].toSong();
                    return SongTile(
                      key: ValueKey('online-view-all-$i-${song.path}'),
                      song: song,
                      songs: [for (final s in _songs) s.toSong()],
                      l10n: l10n,
                      showAlbum: true,
                    );
                  },
                ),

              // Collections Section (Artists Grid vs Card Grid)
              if (_collections.isNotEmpty)
                isArtistMode
                    ? SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: _collections.length,
                          itemBuilder: (context, i) {
                            final artist = _collections[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(50),
                              onTap: () => openOnlineCollection(context, artist),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipOval(
                                    child: SizedBox(
                                      width: 88,
                                      height: 88,
                                      child: OptimizedImage(
                                        imageUrl: artist.thumbnail,
                                        fit: BoxFit.cover,
                                        placeholder: Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.05),
                                          child: const Center(
                                            child: Icon(
                                              LucideIcons.user,
                                              size: 32,
                                              color: Colors.white38,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    artist.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: AppFonts.jostStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: _collections.length,
                          itemBuilder: (context, i) => OnlineCollectionCard(
                            collection: _collections[i],
                          ),
                        ),
                      ),

              // Bottom Pagination Loading Indicator
              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 180)),
            ],
          ],
        ),
      ),
    );
  }
}
