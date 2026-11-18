import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';
import 'package:looper_player/features/microg/presentation/providers/auth_provider.dart';
import 'package:looper_player/features/microg/presentation/screens/account_management_screen.dart';
import 'package:looper_player/features/online/data/content_regions.dart';
import 'package:looper_player/features/online/data/innertube.dart';
import 'package:looper_player/features/online/data/online_cache.dart';
import 'package:looper_player/features/online/data/online_downloader.dart';
import 'package:looper_player/features/online/data/online_settings.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/features/online/presentation/taste_profiles_screen.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/features/settings/presentation/widgets/settings_widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/folder_picker_helper.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

TextStyle _title() =>
    AppFonts.settingsStyle(color: Colors.white, fontWeight: FontWeight.w500);
TextStyle _sub() => AppFonts.settingsStyle(color: Colors.white54, fontSize: 12);

/// Settings > Network & Internet > online music.
/// Everything past the on/off switch is hidden while online music is off;
/// the helpers below follow the same rule for their own categories.
List<({String title, List<Widget> tiles})> onlineSettingsSections(
  AppLocalizations l10n,
  WidgetRef ref,
) {
  final enabled = ref.watch(onlineSettingsProvider.select((s) => s.enabled));
  if (!enabled) {
    return [
      (title: l10n.onlineMusic, tiles: const [_EnabledTile()]),
    ];
  }
  return [
    (
      title: l10n.onlineMusic,
      tiles: const [
        _EnabledTile(),
        OnlineAccountTile(),
        _RefreshTile(),
        ContentRegionTile(),
        _TasteTile(),
        _PreferLocalTile(),
      ],
    ),
    (
      title: l10n.onlineStreaming,
      tiles: const [
        _QualityTile(mobile: false),
        _QualityTile(mobile: true),
        _PreloadTile(),
        _PreloadMobileTile(),
      ],
    ),
  ];
}

/// Online cache controls, shown under Miscellaneous > Storage.
List<Widget> onlineCacheTiles(WidgetRef ref) =>
    onlineAvailable &&
        ref.watch(onlineSettingsProvider.select((s) => s.enabled))
    ? const [
        _CachePlayedTile(),
        _CachePlayedMobileTile(),
        _CacheLimitTile(),
        _CacheTile(),
      ]
    : const [];

/// Online download folder + quality, shown under Music Management.
List<Widget> onlineDownloadTiles(WidgetRef ref) =>
    onlineAvailable &&
        ref.watch(onlineSettingsProvider.select((s) => s.enabled))
    ? const [_DownloadDirTile(), _DownloadQualityTile()]
    : const [];

/// Animated artwork look (player-screen only), shown under Now Playing.
List<Widget> animatedArtworkTiles(WidgetRef ref, {bool classic = true}) {
  // Animated artwork is fetched online, so it hides with online music.
  if (!onlineAvailable ||
      !ref.watch(onlineSettingsProvider.select((s) => s.enabled))) {
    return const [];
  }
  final artworkOn =
      ref.watch(animatedArtworkSettingsProvider.select((s) => s.mode)) !=
      AnimatedArtworkMode.never;
  return [
    const _AnimatedArtworkModeTile(),
    if (artworkOn) ...[
      const _AnimatedArtworkSourceTile(),
      const _AnimateAlbumCoverTile(),
      if (classic) ...const [_ImmersiveBackgroundTile(), _AmbientGlowTile()],
    ],
  ];
}

/// Animated artwork cache controls, shown under Miscellaneous > Storage.
List<Widget> animatedArtworkCacheTiles(WidgetRef ref) {
  // Animated artwork is fetched online, so it hides with online music.
  if (!onlineAvailable ||
      !ref.watch(onlineSettingsProvider.select((s) => s.enabled))) {
    return const [];
  }
  final artworkOn =
      ref.watch(animatedArtworkSettingsProvider.select((s) => s.mode)) !=
      AnimatedArtworkMode.never;
  return [
    if (artworkOn) const _AnimatedArtworkCacheLimitTile(),
    const _ClearAnimatedArtworkCacheTile(),
  ];
}

class _Switch extends ConsumerWidget {
  const _Switch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    secondary: Icon(icon, color: Colors.white70),
    title: Text(title, style: _title()),
    subtitle: subtitle == null ? null : Text(subtitle!, style: _sub()),
    value: value,
    onChanged: onChanged,
  );
}

class _EnabledTile extends ConsumerWidget {
  const _EnabledTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final internet = ref.watch(
      settingsProvider.select((s) => s.enableInternet),
    );
    final settings = ref.watch(onlineSettingsProvider);
    final auth = ref.watch(authProvider);
    final isGuest = auth.status != AuthStatus.signedIn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Switch(
          icon: LucideIcons.cloud,
          title: l10n.onlineMusic,
          subtitle: internet
              ? l10n.onlineEnabledDesc
              : l10n.onlineNeedsInternet,
          value: settings.enabled,
          onChanged: (v) {
            if (v && !settings.disclaimerAccepted) {
              _showDisclaimer(context, ref, l10n);
            } else {
              ref
                  .read(onlineSettingsProvider.notifier)
                  .update((s) => s.copyWith(enabled: v));
              // Off stops running downloads; cached and saved files stay.
              if (!v) ref.read(downloadsProvider.notifier).cancelAll();
            }
          },
        ),
        if (settings.enabled && isGuest)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(
              l10n.onlineGuestPrivacyNote,
              style: AppFonts.settingsStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  static void _showDisclaimer(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.cloud, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  l10n.onlineDisclaimerTitle,
                  style: AppFonts.settingsStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.onlineDisclaimerBody,
              style: AppFonts.settingsStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    l10n.onlineNotNow,
                    style: AppFonts.settingsStyle(color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ref
                        .read(onlineSettingsProvider.notifier)
                        .update(
                          (s) => s.copyWith(
                            enabled: true,
                            disclaimerAccepted: true,
                          ),
                        );
                    openTasteSetup(context);
                  },
                  child: Text(
                    l10n.onlineTurnOn,
                    style: AppFonts.settingsStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshTile extends ConsumerWidget {
  const _RefreshTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(LucideIcons.refreshCw),
      title: Text(l10n.onlineRefresh, style: _title()),
      subtitle: Text(l10n.onlineRefreshDesc, style: _sub()),
      onTap: () async {
        await ref.read(onlineHomeProvider.notifier).refresh();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.onlineRefreshed)));
        }
      },
    );
  }
}

class ContentRegionTile extends ConsumerWidget {
  const ContentRegionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(onlineSettingsProvider);
    final autoCountry = InnerTube.instance.country;
    final region = settings.contentRegion;
    final displaySubtitle = region == null
        ? l10n.onlineContentRegionAuto(ContentRegions.nameFor(autoCountry))
        : ContentRegions.nameFor(region);

    return ListTile(
      leading: const Icon(LucideIcons.globe),
      title: Text(l10n.onlineContentRegion, style: _title()),
      subtitle: Text(displaySubtitle, style: _sub()),
      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38),
      onTap: () => _showRegionPicker(context, ref, l10n, autoCountry, region),
    );
  }

  static void _showRegionPicker(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    String autoCountry,
    String? currentRegion,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RegionPickerSheet(
        autoCountry: autoCountry,
        selectedRegion: currentRegion,
        onSelected: (code) async {
          Navigator.of(ctx).pop();
          await ref
              .read(onlineSettingsProvider.notifier)
              .setContentRegion(code);
          ref.read(onlineHomeProvider.notifier).refresh();
        },
      ),
    );
  }
}

class _RegionPickerSheet extends StatefulWidget {
  const _RegionPickerSheet({
    required this.autoCountry,
    required this.selectedRegion,
    required this.onSelected,
  });

  final String autoCountry;
  final String? selectedRegion;
  final ValueChanged<String?> onSelected;

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = ContentRegions.all.where((r) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return r.name.toLowerCase().contains(q) ||
          r.code.toLowerCase().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.onlineContentRegion,
                  style: AppFonts.settingsStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.onlineContentRegionDesc,
                  style: AppFonts.settingsStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _filter = v.trim()),
                  style: AppFonts.settingsStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      size: 18,
                      color: Colors.white54,
                    ),
                    hintText: l10n.onlineContentRegionSearch,
                    hintStyle: AppFonts.settingsStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (_filter.isEmpty)
                  ListTile(
                    leading: const Icon(
                      LucideIcons.sparkles,
                      color: Colors.white70,
                    ),
                    title: Text(
                      l10n.onlineContentRegionAuto(
                        ContentRegions.nameFor(widget.autoCountry),
                      ),
                      style: AppFonts.settingsStyle(
                        color: widget.selectedRegion == null
                            ? Colors.blueAccent
                            : Colors.white,
                        fontWeight: widget.selectedRegion == null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: widget.selectedRegion == null
                        ? const Icon(
                            LucideIcons.check,
                            color: Colors.blueAccent,
                            size: 20,
                          )
                        : null,
                    onTap: () => widget.onSelected(null),
                  ),
                for (final r in filtered)
                  ListTile(
                    title: Text(
                      r.name,
                      style: AppFonts.settingsStyle(
                        color: widget.selectedRegion == r.code
                            ? Colors.blueAccent
                            : Colors.white,
                        fontWeight: widget.selectedRegion == r.code
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      r.code,
                      style: AppFonts.settingsStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    trailing: widget.selectedRegion == r.code
                        ? const Icon(
                            LucideIcons.check,
                            color: Colors.blueAccent,
                            size: 20,
                          )
                        : null,
                    onTap: () => widget.onSelected(r.code),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnlineAccountTile extends ConsumerWidget {
  const OnlineAccountTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final name = auth.session?.displayName ?? auth.session?.microgAccount;
    return ListTile(
      leading: const Icon(LucideIcons.circleUser),
      title: Text(l10n.accountTitle, style: _title()),
      subtitle: Text(switch (auth.status) {
        AuthStatus.signedIn => l10n.accountSignedInAs(name ?? ''),
        AuthStatus.expired => l10n.accountExpired,
        _ => l10n.accountSignedOutDesc,
      }, style: _sub()),
      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38),
      onTap: () => Navigator.of(
        context,
      ).push(riseRoute(const AccountManagementScreen())),
    );
  }
}

class _TasteTile extends StatelessWidget {
  const _TasteTile();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(LucideIcons.sparkles),
      title: Text(l10n.onlineYourTaste, style: _title()),
      subtitle: Text(l10n.onlineYourTasteDesc, style: _sub()),
      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38),
      onTap: () =>
          Navigator.of(context).push(riseRoute(const TasteProfilesScreen())),
    );
  }
}

class _PreferLocalTile extends ConsumerWidget {
  const _PreferLocalTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _Switch(
      icon: LucideIcons.hardDrive,
      title: l10n.onlinePreferLocal,
      subtitle: l10n.onlinePreferLocalDesc,
      value: ref.watch(onlineSettingsProvider).preferLocal,
      onChanged: (v) => ref
          .read(onlineSettingsProvider.notifier)
          .update((s) => s.copyWith(preferLocal: v)),
    );
  }
}

class _QualityTile extends ConsumerWidget {
  const _QualityTile({required this.mobile});
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(onlineSettingsProvider);
    final value = mobile ? s.qualityMobile : s.qualityWifi;
    String label(OnlineQuality q) => switch (q) {
      OnlineQuality.high => l10n.onlineQualityHigh,
      OnlineQuality.normal => l10n.onlineQualityNormal,
      OnlineQuality.low => l10n.onlineQualityLow,
    };
    return ListTile(
      leading: Icon(
        mobile ? LucideIcons.signal : LucideIcons.wifi,
        color: Colors.white70,
      ),
      title: Text(
        mobile ? l10n.onlineQualityMobile : l10n.onlineQualityWifi,
        style: _title(),
      ),
      trailing: DropdownButton<OnlineQuality>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.settingsStyle(color: Colors.white),
        items: [
          for (final q in OnlineQuality.values)
            DropdownMenuItem(value: q, child: Text(label(q))),
        ],
        onChanged: (q) {
          if (q == null) return;
          ref
              .read(onlineSettingsProvider.notifier)
              .update(
                (s) => mobile
                    ? s.copyWith(qualityMobile: q)
                    : s.copyWith(qualityWifi: q),
              );
        },
      ),
    );
  }
}

class _PreloadTile extends ConsumerWidget {
  const _PreloadTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _Switch(
      icon: LucideIcons.download,
      title: l10n.onlinePreload,
      subtitle: l10n.onlinePreloadDesc,
      value: ref.watch(onlineSettingsProvider).preload,
      onChanged: (v) => ref
          .read(onlineSettingsProvider.notifier)
          .update((s) => s.copyWith(preload: v)),
    );
  }
}

class _PreloadMobileTile extends ConsumerWidget {
  const _PreloadMobileTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(onlineSettingsProvider);
    if (!s.preload) return const SizedBox.shrink();
    return _Switch(
      icon: LucideIcons.signal,
      title: l10n.onlinePreloadMobile,
      subtitle: null,
      value: s.preloadOnMobile,
      onChanged: (v) => ref
          .read(onlineSettingsProvider.notifier)
          .update((s) => s.copyWith(preloadOnMobile: v)),
    );
  }
}

class _CachePlayedTile extends ConsumerWidget {
  const _CachePlayedTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _Switch(
      icon: LucideIcons.hardDriveDownload,
      title: l10n.onlineCachePlayed,
      subtitle: l10n.onlineCachePlayedDesc,
      value: ref.watch(onlineSettingsProvider).cachePlayed,
      onChanged: (v) => ref
          .read(onlineSettingsProvider.notifier)
          .update((s) => s.copyWith(cachePlayed: v)),
    );
  }
}

class _CachePlayedMobileTile extends ConsumerWidget {
  const _CachePlayedMobileTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(onlineSettingsProvider);
    if (!s.cachePlayed) return const SizedBox.shrink();
    return _Switch(
      icon: LucideIcons.signal,
      title: l10n.onlineCachePlayedMobile,
      subtitle: l10n.onlineCachePlayedMobileDesc,
      value: s.cachePlayedOnMobile,
      onChanged: (v) => ref
          .read(onlineSettingsProvider.notifier)
          .update((s) => s.copyWith(cachePlayedOnMobile: v)),
    );
  }
}

class _CacheLimitTile extends ConsumerWidget {
  const _CacheLimitTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mb = ref.watch(onlineSettingsProvider).cacheLimitMB;
    return SettingsSliderTile(
      icon: LucideIcons.database,
      title: l10n.onlineCacheLimit,
      subtitle: l10n.onlineCacheLimitDesc,
      // Stored in MB (no settings migration), shown in whole GB.
      value: (mb / 1024).clamp(1, 20).toDouble(),
      min: 1,
      max: 20,
      divisions: 19,
      suffix: ' GB',
      onChanged: (v) => ref
          .read(onlineSettingsProvider.notifier)
          .update((s) => s.copyWith(cacheLimitMB: v.round() * 1024)),
    );
  }
}

class _CacheTile extends StatefulWidget {
  const _CacheTile();
  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  late Future<int> _size = OnlineCache.instance.sizeBytes();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<int>(
      future: _size,
      builder: (context, snap) {
        final mb = ((snap.data ?? 0) / (1024 * 1024)).toStringAsFixed(1);
        return ListTile(
          leading: const Icon(LucideIcons.trash2),
          title: Text(l10n.onlineClearCache, style: _title()),
          subtitle: Text(
            '${l10n.onlineCacheUsed('$mb MB')} • ${l10n.onlineClearCacheDesc}',
            style: _sub(),
          ),
          onTap: () async {
            final confirmed = await showTaskDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(l10n.onlineClearCache),
                content: Text(l10n.onlineClearCacheDesc),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(l10n.clear),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            await OnlineCache.instance.clear();
            if (mounted) {
              setState(() => _size = OnlineCache.instance.sizeBytes());
            }
          },
        );
      },
    );
  }
}

class _DownloadDirTile extends ConsumerWidget {
  const _DownloadDirTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(onlineSettingsProvider);
    return ListTile(
      leading: const Icon(LucideIcons.folder),
      title: Text(l10n.downloadFolder, style: _title()),
      subtitle: Text(
        s.downloadDir ?? 'Default (Music/Looper)',
        style: _sub(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38),
      onTap: () async {
        final path = await FolderPickerHelper.pickFolderPathOnly(context);
        if (path != null && path.trim().isNotEmpty) {
          final trimmed = path.trim();
          ref
              .read(onlineSettingsProvider.notifier)
              .update((curr) => curr.copyWith(downloadDir: trimmed));
          final libraryNotifier = ref.read(libraryProvider.notifier);
          final settings = ref.read(settingsProvider);
          if (!settings.libraryFolders.contains(trimmed)) {
            ref.read(settingsProvider.notifier).updateLibraryFolders([
              ...settings.libraryFolders,
              trimmed,
            ]);
            await libraryNotifier.scanLibrary(trimmed);
          }
        }
      },
    );
  }
}

class _DownloadQualityTile extends ConsumerWidget {
  const _DownloadQualityTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(onlineSettingsProvider);
    String label(OnlineQuality q) => switch (q) {
      OnlineQuality.high => l10n.onlineQualityHigh,
      OnlineQuality.normal => l10n.onlineQualityNormal,
      OnlineQuality.low => l10n.onlineQualityLow,
    };
    return ListTile(
      leading: const Icon(LucideIcons.arrowDownToLine),
      title: Text(l10n.downloadQuality, style: _title()),
      trailing: DropdownButton<OnlineQuality>(
        value: s.downloadQuality,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.settingsStyle(color: Colors.white),
        items: [
          for (final q in OnlineQuality.values)
            DropdownMenuItem(value: q, child: Text(label(q))),
        ],
        onChanged: (q) {
          if (q == null) return;
          ref
              .read(onlineSettingsProvider.notifier)
              .update((curr) => curr.copyWith(downloadQuality: q));
        },
      ),
    );
  }
}

class _AnimatedArtworkModeTile extends ConsumerWidget {
  const _AnimatedArtworkModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(animatedArtworkSettingsProvider);
    String label(AnimatedArtworkMode m) => switch (m) {
      AnimatedArtworkMode.always => l10n.animatedArtworksAlways,
      AnimatedArtworkMode.wifiOnly => l10n.animatedArtworksWifiOnly,
      AnimatedArtworkMode.never => l10n.animatedArtworksNever,
    };
    return ListTile(
      leading: const Icon(LucideIcons.sparkles),
      title: Text(l10n.animatedArtworks, style: _title()),
      subtitle: Text(l10n.animatedArtworksDesc, style: _sub()),
      trailing: DropdownButton<AnimatedArtworkMode>(
        value: s.mode,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.settingsStyle(color: Colors.white),
        items: [
          for (final m in AnimatedArtworkMode.values)
            DropdownMenuItem(value: m, child: Text(label(m))),
        ],
        onChanged: (m) {
          if (m == null) return;
          ref
              .read(animatedArtworkSettingsProvider.notifier)
              .update((curr) => curr.copyWith(mode: m));
        },
      ),
    );
  }
}

/// Apple motion covers, the song's YouTube Music video, or Apple then
/// YouTube.
class _AnimatedArtworkSourceTile extends ConsumerWidget {
  const _AnimatedArtworkSourceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(animatedArtworkSettingsProvider);
    String label(AnimatedArtworkSource src) => switch (src) {
      AnimatedArtworkSource.apple => 'Apple Music',
      AnimatedArtworkSource.youtube => 'YouTube video',
      AnimatedArtworkSource.appleThenYoutube => 'Apple, then YouTube',
    };
    return ListTile(
      leading: const Icon(LucideIcons.clapperboard),
      title: Text('Artwork Source', style: _title()),
      subtitle: Text(
        s.source.usesYoutube
            ? 'Online songs show their music video (muted, in time with '
                  'the song when it matches). Uses more data.'
            : 'Motion covers from Apple Music',
        style: _sub(),
      ),
      trailing: DropdownButton<AnimatedArtworkSource>(
        value: s.source,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.settingsStyle(color: Colors.white),
        items: [
          for (final src in AnimatedArtworkSource.values)
            DropdownMenuItem(value: src, child: Text(label(src))),
        ],
        onChanged: (src) {
          if (src == null) return;
          ref
              .read(animatedArtworkSettingsProvider.notifier)
              .update((curr) => curr.copyWith(source: src));
        },
      ),
    );
  }
}

class _AnimateAlbumCoverTile extends ConsumerWidget {
  const _AnimateAlbumCoverTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(settingsProvider.select((s) => s.playerStyle));
    final s = ref.watch(animatedArtworkSettingsProvider);
    return _Switch(
      icon: LucideIcons.disc,
      title: 'Now Playing Artwork Motion',
      subtitle: 'Animate album cover on now playing screen when available',
      value: s.isAlbumCoverAnimated(style),
      onChanged: (val) {
        ref
            .read(animatedArtworkSettingsProvider.notifier)
            .update((curr) => curr.withAlbumCoverForStyle(style, val));
      },
    );
  }
}

class _ImmersiveBackgroundTile extends ConsumerWidget {
  const _ImmersiveBackgroundTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(animatedArtworkSettingsProvider);
    return _Switch(
      icon: LucideIcons.scan,
      title: l10n.immersivePlayerBackground,
      subtitle: l10n.immersivePlayerBackgroundDesc,
      value: s.immersiveBackground,
      onChanged: (val) {
        ref
            .read(animatedArtworkSettingsProvider.notifier)
            .update((curr) => curr.copyWith(immersiveBackground: val));
      },
    );
  }
}

class _AmbientGlowTile extends ConsumerWidget {
  const _AmbientGlowTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(animatedArtworkSettingsProvider);
    return _Switch(
      icon: LucideIcons.sparkles,
      title: 'Ambient Glow',
      subtitle: 'Soft moving glow behind the player artwork',
      value: s.ambientGlow,
      onChanged: (val) {
        ref
            .read(animatedArtworkSettingsProvider.notifier)
            .update((curr) => curr.copyWith(ambientGlow: val));
      },
    );
  }
}

class _AnimatedArtworkCacheLimitTile extends ConsumerWidget {
  const _AnimatedArtworkCacheLimitTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(animatedArtworkSettingsProvider);
    const options = [100, 300, 500, 1024, 2048];
    String label(int mb) => mb >= 1024 ? '${(mb / 1024).round()} GB' : '$mb MB';

    return ListTile(
      leading: const Icon(LucideIcons.hardDrive),
      title: Text(l10n.animatedArtworkCacheLimit, style: _title()),
      trailing: DropdownButton<int>(
        value: s.cacheLimitMB,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.settingsStyle(color: Colors.white),
        items: [
          for (final opt in options)
            DropdownMenuItem(value: opt, child: Text(label(opt))),
        ],
        onChanged: (val) {
          if (val == null) return;
          ref
              .read(animatedArtworkSettingsProvider.notifier)
              .update((curr) => curr.copyWith(cacheLimitMB: val));
        },
      ),
    );
  }
}

class _ClearAnimatedArtworkCacheTile extends ConsumerWidget {
  const _ClearAnimatedArtworkCacheTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(LucideIcons.trash2, color: Colors.redAccent),
      title: Text(
        l10n.clearAnimatedArtworkCache,
        style: AppFonts.settingsStyle(color: Colors.redAccent),
      ),
      onTap: () async {
        await AnimatedArtworkService.instance.clearCache();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.animatedArtworkCacheCleared),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }
}
