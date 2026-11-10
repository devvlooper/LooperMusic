import 'package:flutter/widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Row ids that only show while online music is on.
const onlineHomeRowIds = ['online_feed', 'online_artists', 'online_more'];

/// Puts the reordered visible rows back into the full saved order,
/// leaving hidden rows in their slots.
List<String> mergeHomeOrder(List<String> saved, List<String> draft) {
  final visible = draft.toSet();
  final next = draft.iterator;
  return [
    for (final id in saved)
      visible.contains(id) && next.moveNext() ? next.current : id,
  ];
}

/// Adds rows missing from a saved order: Quick picks first (the old Settings
/// sheet dropped it while it was pinned), then the online rows right after it.
List<String> withHomeRowIds(List<String> order) {
  final out = order.contains('quick_picks')
      ? [...order]
      : ['quick_picks', ...order];
  final missing = onlineHomeRowIds.where((id) => !out.contains(id)).toList();
  out.insertAll(out.indexOf('quick_picks') + 1, missing);
  return out;
}

/// Title, description and icon of a Home row, shared by Home's reorder mode
/// and the Settings reorder sheet.
({String title, String description, IconData icon}) homeRowInfo(
  String id,
  AppLocalizations l10n,
) => switch (id) {
  'quick_picks' => (
    title: l10n.quickPicks,
    description: l10n.quickPicksRowDesc,
    icon: LucideIcons.sparkles,
  ),
  'online_feed' => (
    title: l10n.onlineFeedRow,
    description: l10n.onlineFeedRowDesc,
    icon: LucideIcons.globe,
  ),
  'online_artists' => (
    title: l10n.artistsForYou,
    description: l10n.artistsForYouRowDesc,
    icon: LucideIcons.users,
  ),
  'online_more' => (
    title: l10n.onlineMoreRow,
    description: l10n.onlineMoreRowDesc,
    icon: LucideIcons.layers,
  ),
  'playlists' => (
    title: l10n.playlists,
    description: l10n.playlistsRowDesc,
    icon: LucideIcons.listMusic,
  ),
  'songs' => (
    title: l10n.songs,
    description: l10n.recentlyAddedSongsRowDesc,
    icon: LucideIcons.music,
  ),
  'albums' => (
    title: l10n.albums,
    description: l10n.albumsRowDesc,
    icon: LucideIcons.disc,
  ),
  'artists' => (
    title: l10n.artists,
    description: l10n.artistsRowDesc,
    icon: LucideIcons.user,
  ),
  'genres' => (
    title: l10n.genres,
    description: l10n.genresRowDesc,
    icon: LucideIcons.library,
  ),
  'recent' => (
    title: l10n.recentPlayed,
    description: l10n.recentRowDesc,
    icon: LucideIcons.history,
  ),
  _ => (title: id, description: '', icon: LucideIcons.layers),
};

/// Set while Home is in reorder mode; system back calls it to cancel.
VoidCallback? homeReorderCancel;
