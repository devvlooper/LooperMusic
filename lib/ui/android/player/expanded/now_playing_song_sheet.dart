import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/core/providers/collection_navigation.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/core/providers/player_expand_provider.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/utils/song_metadata.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/android/player/expanded/quality_details_sheet.dart';
import 'package:looper_player/ui/android/widgets/song_details_bottom_sheet.dart';
import 'package:looper_player/ui/widgets/common/song_artist_picker.dart';
import 'package:looper_player/ui/widgets/common/song_artwork.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Opens the small song sheet from the now playing title or artist.
Future<void> showNowPlayingSongSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Song song,
  required bool enableSlide,
}) async {
  final String albumName = song.album?.trim() ?? '';
  // Looked up first so the sheet opens at its final height.
  final Album? album = albumName.isEmpty
      ? null
      : await DbService.isar.albums.filter().nameEqualTo(albumName).findFirst();
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;

  void leavePlayer() {
    if (enableSlide) {
      ref.read(playerCollapseTriggerProvider.notifier).bump();
    } else {
      Navigator.pop(context);
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetContext) {
      void close() => Navigator.pop(sheetContext);
      return NowPlayingSongSheet(
        song: song,
        onDone: close,
        onViewArtist: () async {
          close();
          final name = await pickSongArtist(context, song);
          if (name == null || !context.mounted) return;
          final navigation = ref.read(appNavigationProvider.notifier);
          leavePlayer();
          await navigation.showArtistNamed(
            name,
            subtitle: l10n.artists,
            fallbackArt: song.artPath,
          );
        },
        onViewAlbum: album == null
            ? null
            : () async {
                close();
                final navigation = ref.read(appNavigationProvider.notifier);
                leavePlayer();
                await navigation.showAlbum(
                  album,
                  unknownArtist: l10n.unknownArtist,
                );
              },
        onAbout: () {
          close();
          showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => SongDetailsBottomSheet(song: song),
          );
        },
        onStreamInfo: () {
          close();
          showQualityDetailsSheet(context, song);
        },
      );
    },
  );
}

class NowPlayingSongSheet extends StatelessWidget {
  const NowPlayingSongSheet({
    super.key,
    required this.song,
    required this.onViewArtist,
    required this.onViewAlbum,
    required this.onAbout,
    required this.onStreamInfo,
    required this.onDone,
    @visibleForTesting this.artworkBuilder,
  });

  final Song song;
  final VoidCallback onViewArtist;

  /// Null hides the row: the album isn't in the library.
  final VoidCallback? onViewAlbum;
  final VoidCallback onAbout;
  final VoidCallback onStreamInfo;
  final VoidCallback onDone;
  final Widget Function(double size, BorderRadius radius)? artworkBuilder;

  static const Color _sheet = Color(0xFF0B0B0C);
  static const Color _row = Color(0xFF17171A);
  static const Color _done = Color(0xFF3F3F42);

  static TextStyle _text(double size, {double alpha = 1}) => TextStyle(
    fontFamily: 'Space Grotesk',
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: 1.25,
    letterSpacing: -0.02 * size,
    color: Colors.white.withValues(alpha: alpha),
  );

  Widget _action({
    required Widget leading,
    required String label,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _row,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox.square(dimension: 28, child: leading),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(17),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _art(double size, BorderRadius radius) =>
      artworkBuilder?.call(size, radius) ??
      SongArtwork(song: song, size: size, borderRadius: radius);

  Widget _iconTile(IconData icon) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFEDEDED),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, size: 16, color: const Color(0xFF3A3A3C)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String artist = song.artist?.trim() ?? '';
    final String album = song.album?.trim() ?? '';
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: _sheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 53,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      _art(52, BorderRadius.circular(8)),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(18),
                            ),
                            Text(
                              artistAlbumLabel(song, l10n, showAlbum: false),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(15, alpha: 0.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (artist.isNotEmpty)
                    _action(
                      leading: _art(28, BorderRadius.circular(14)),
                      label: l10n.viewItem(artist),
                      onTap: onViewArtist,
                    ),
                  if (onViewAlbum != null && album.isNotEmpty)
                    _action(
                      leading: _art(28, BorderRadius.circular(5)),
                      label: l10n.viewItem(album),
                      onTap: onViewAlbum!,
                    ),
                  _action(
                    leading: _iconTile(LucideIcons.info),
                    label: l10n.aboutSong,
                    onTap: onAbout,
                  ),
                  _action(
                    leading: _iconTile(LucideIcons.audioLines),
                    label: l10n.streamInfo,
                    onTap: onStreamInfo,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: onDone,
                      style: TextButton.styleFrom(
                        backgroundColor: _done,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(l10n.done, style: _text(17)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
