import 'package:looper_player/core/motion/list_wave.dart';
import 'package:looper_player/ui/android/tabs/library/categories/category_detail_wrapper.dart'
    show CategorySearch;
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:looper_player/features/playlists/presentation/widgets/playlist_artwork.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/services/storage/import_export_service.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/core/utils/l10n.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/ui/widgets/common/filter_pill.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';

part 'playlist_view.g.dart';

// Named 'PlaylistList' (not 'Playlist') to avoid colliding with the
// Playlist model class from library/domain/models - `name: 'playlist'`
// keeps the generated provider as `playlistProvider`, matching every
// existing call site.
@Riverpod(keepAlive: true, name: 'playlistProvider')
class PlaylistList extends _$PlaylistList {
  @override
  List<Playlist> build() {
    _loadPlaylists();
    return [];
  }

  void _loadPlaylists() {
    DbService.isar.playlists
        .where()
        .sortByDateModifiedDesc()
        .watch(fireImmediately: true)
        .listen((playlists) {
          state = playlists;
        });
  }

  Future<void> createPlaylist(String name) async {
    final playlist = Playlist()
      ..name = name
      ..songPaths = []
      ..dateCreated = DateTime.now()
      ..dateModified = DateTime.now();

    await DbService.isar.writeTxn(() => DbService.isar.playlists.put(playlist));
  }

  Future<void> deletePlaylist(int id) async {
    await DbService.isar.writeTxn(() => DbService.isar.playlists.delete(id));
  }
}

// Keep the playlist record and its songs reactive independently: importing,
// enrichment, file removal and metadata edits need not modify the playlist.
final _playlistRecordProvider = StreamProvider.autoDispose
    .family<Playlist?, int>(
      (ref, playlistId) => DbService.isar.playlists.watchObject(
        playlistId,
        fireImmediately: true,
      ),
    );

@Riverpod(keepAlive: true)
Stream<List<Playlist>> dashboardPlaylists(Ref ref) {
  return DbService.isar.playlists
      .where()
      .sortByLastPlayedDesc()
      .thenByDateModifiedDesc()
      .watch(fireImmediately: true);
}

@Riverpod(keepAlive: true)
Stream<List<Song>> playlistSongs(Ref ref, int playlistId) async* {
  final playlist = await ref.watch(_playlistRecordProvider(playlistId).future);
  if (playlist == null || playlist.songPaths.isEmpty) {
    yield <Song>[];
    return;
  }
  yield* DbService.isar.songs
      .filter()
      .anyOf(playlist.songPaths, (q, path) => q.pathEqualTo(path))
      .watch(fireImmediately: true)
      .map((songs) {
        final songMap = {for (final song in songs) song.path: song};
        // Preserve saved order and repeated entries; unavailable songs are
        // omitted consistently with the playable song list.
        return playlist.songPaths
            .map((path) => songMap[path])
            .whereType<Song>()
            .toList();
      });
}

enum _PlaylistSourceFilter { all, onDevice, youtube }

class PlaylistView extends ConsumerStatefulWidget {
  const PlaylistView({super.key});

  @override
  ConsumerState<PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends ConsumerState<PlaylistView> {
  _PlaylistSourceFilter _filter = _PlaylistSourceFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final playlists = ref.watch(playlistProvider);
    final onlinePlaylistsAsync = ref.watch(onlineAccountPlaylistsProvider);
    final onlinePlaylists =
        onlinePlaylistsAsync.value ?? const <OnlineCollection>[];
    final hasActiveSong = ref.watch(
      playbackProvider.select((s) => s.currentSong != null),
    );
    final accent = ref.watch(settingsProvider).accent;

    final showOnline = onlinePlaylists.isNotEmpty;
    final totalCount =
        playlists.length + (showOnline ? onlinePlaylists.length : 0);

    final showLocal =
        _filter == _PlaylistSourceFilter.all ||
        _filter == _PlaylistSourceFilter.onDevice;
    final showCloud =
        showOnline &&
        (_filter == _PlaylistSourceFilter.all ||
            _filter == _PlaylistSourceFilter.youtube);

    final q = CategorySearch.of(context);
    final displayLocal = showLocal
        ? [
            for (final p in playlists)
              if (CategorySearch.matches(q, [p.name])) p,
          ]
        : const <Playlist>[];
    final displayOnline = showCloud
        ? [
            for (final p in onlinePlaylists)
              if (CategorySearch.matches(q, [p.title])) p,
          ]
        : const <OnlineCollection>[];
    final totalDisplayCount = displayLocal.length + displayOnline.length;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: totalCount == 0
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.listMusic,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noPlaylistsYet,
                    style: AppFonts.jostStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: _PlaylistActions(
                      accent: accent,
                      onCreate: () => _showCreateDialog(context, ref),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: _PlaylistActions(
                    accent: accent,
                    onCreate: () => _showCreateDialog(context, ref),
                  ),
                ),
                if (showOnline)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterPill(
                            label:
                                'All (${playlists.length + onlinePlaylists.length})',
                            isSelected: _filter == _PlaylistSourceFilter.all,
                            accent: accent,
                            onTap: () => setState(
                              () => _filter = _PlaylistSourceFilter.all,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterPill(
                            label: 'On Device (${playlists.length})',
                            isSelected:
                                _filter == _PlaylistSourceFilter.onDevice,
                            accent: accent,
                            onTap: () => setState(
                              () => _filter = _PlaylistSourceFilter.onDevice,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterPill(
                            label: 'YouTube Music (${onlinePlaylists.length})',
                            isSelected:
                                _filter == _PlaylistSourceFilter.youtube,
                            accent: accent,
                            onTap: () => setState(
                              () => _filter = _PlaylistSourceFilter.youtube,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: totalDisplayCount == 0
                      ? Center(
                          child: Text(
                            l10n.noPlaylistsYet,
                            style: AppFonts.jostStyle(color: Colors.grey),
                          ),
                        )
                      : ListWave(
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 180),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  childAspectRatio: 0.85,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 20,
                                ),
                            itemCount: totalDisplayCount,
                            itemBuilder: waveItems((context, index) {
                              if (index < displayLocal.length) {
                                return PlaylistCard(
                                  playlist: displayLocal[index],
                                );
                              }
                              final onlineIndex = index - displayLocal.length;
                              return _OnlinePlaylistCard(
                                collection: displayOnline[onlineIndex],
                              );
                            }),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    showTaskDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newPlaylist),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: l10n.playlistNameHint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref
                    .read(playlistProvider.notifier)
                    .createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }
}

/// Opens [playlist]'s collection page with its songs in playlist order.
Future<void> openPlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final subtitle = context.l10n.playlist;
  final songs = await DbService.isar.songs
      .filter()
      .anyOf(playlist.songPaths, (q, path) => q.pathEqualTo(path))
      .findAll();

  final songMap = {for (var s in songs) s.path: s};
  final orderedSongs = playlist.songPaths
      .map((path) => songMap[path])
      .whereType<Song>()
      .toList();

  ref
      .read(appNavigationProvider.notifier)
      .showCollection(
        title: playlist.name,
        subtitle: subtitle,
        songs: orderedSongs,
        playlist: playlist,
      );
}

class PlaylistCard extends ConsumerWidget {
  final Playlist playlist;

  /// Home sets the design's card text; elsewhere the app font.
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  const PlaylistCard({
    super.key,
    required this.playlist,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => openPlaylist(context, ref, playlist),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PlaylistArtwork(
              songPaths: playlist.songPaths,
              coverPath: playlist.coverPath,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
            style:
                titleStyle ?? AppFonts.jostStyle(fontWeight: FontWeight.normal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            context.l10n.songsCount(playlist.songPaths.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                subtitleStyle ??
                AppFonts.jostStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _OnlinePlaylistCard extends StatelessWidget {
  final OnlineCollection collection;
  const _OnlinePlaylistCard({required this.collection});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openOnlineCollection(context, collection),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OptimizedImage(
                    imageUrl: collection.thumbnail,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Center(
                        child: Icon(
                          LucideIcons.listMusic,
                          size: 36,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.cloud,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            collection.title,
            style: AppFonts.jostStyle(fontWeight: FontWeight.normal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              const Icon(LucideIcons.cloud, size: 11, color: Colors.white38),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  collection.subtitle ?? 'YouTube Music',
                  style: AppFonts.jostStyle(color: Colors.grey, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// New playlist and Import, side by side at the top of Playlists.
class _PlaylistActions extends StatelessWidget {
  final Color accent;
  final VoidCallback onCreate;

  const _PlaylistActions({required this.accent, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget button({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required bool primary,
    }) => Expanded(
      child: Material(
        color: primary ? accent : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            AppHaptics.light();
            onTap();
          },
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: primary ? _onAccent(accent) : Colors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.jostStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: primary ? _onAccent(accent) : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        button(
          icon: LucideIcons.plus,
          label: l10n.newPlaylist,
          onTap: onCreate,
          primary: true,
        ),
        const SizedBox(width: 10),
        button(
          icon: LucideIcons.fileInput,
          label: l10n.importLabel,
          onTap: () => ImportExportService.importM3uPlaylists(context),
          primary: false,
        ),
      ],
    );
  }

  static Color _onAccent(Color accent) =>
      accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}
