import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:looper_player/features/microg/domain/auth_state.dart';
import 'package:looper_player/features/microg/presentation/providers/auth_provider.dart';
import 'package:looper_player/features/microg/presentation/screens/account_management_screen.dart';
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
    AppFonts.jostStyle(color: Colors.white, fontWeight: FontWeight.w500);
TextStyle _sub() => AppFonts.jostStyle(color: Colors.white54, fontSize: 12);

/// Settings > Online music.
List<({String title, List<Widget> tiles})> onlineSettingsSections(
  AppLocalizations l10n,
) => [
  (
    title: l10n.onlineMusic,
    tiles: const [
      _EnabledTile(),
      _AccountTile(),
      _RefreshTile(),
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
  (
    title: l10n.onlineCache,
    tiles: const [
      _CachePlayedTile(),
      _CachePlayedMobileTile(),
      _CacheLimitTile(),
      _CacheTile(),
    ],
  ),
  (
    title: l10n.onlineDownloads,
    tiles: const [_DownloadDirTile(), _DownloadQualityTile()],
  ),
  (
    title: l10n.animatedArtworks,
    tiles: const [
      _AnimatedArtworkModeTile(),
      _ImmersiveBackgroundTile(),
      _CustomArtworkServerTile(),
      _AnimatedArtworkCacheLimitTile(),
      _ClearAnimatedArtworkCacheTile(),
    ],
  ),
];

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
    activeThumbColor: ref.watch(settingsProvider).accent,
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
    return _Switch(
      icon: LucideIcons.cloud,
      title: l10n.onlineMusic,
      subtitle: internet ? l10n.onlineEnabledDesc : l10n.onlineNeedsInternet,
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
                  style: AppFonts.jostStyle(
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
              style: AppFonts.jostStyle(
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
                    style: AppFonts.jostStyle(color: Colors.white60),
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
                    style: AppFonts.jostStyle(fontWeight: FontWeight.w600),
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
      leading: const Icon(LucideIcons.refreshCw, color: Colors.white70),
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

class _AccountTile extends ConsumerWidget {
  const _AccountTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final name = auth.session?.displayName ?? auth.session?.microgAccount;
    return ListTile(
      leading: const Icon(LucideIcons.circleUser, color: Colors.white70),
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
      leading: const Icon(LucideIcons.sparkles, color: Colors.white70),
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
        style: AppFonts.jostStyle(color: Colors.white),
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
          leading: const Icon(LucideIcons.trash2, color: Colors.white70),
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
      leading: const Icon(LucideIcons.folder, color: Colors.white70),
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
      leading: const Icon(LucideIcons.arrowDownToLine, color: Colors.white70),
      title: Text(l10n.downloadQuality, style: _title()),
      trailing: DropdownButton<OnlineQuality>(
        value: s.downloadQuality,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.jostStyle(color: Colors.white),
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
      leading: const Icon(LucideIcons.sparkles, color: Colors.white70),
      title: Text(l10n.animatedArtworks, style: _title()),
      subtitle: Text(l10n.animatedArtworksDesc, style: _sub()),
      trailing: DropdownButton<AnimatedArtworkMode>(
        value: s.mode,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.jostStyle(color: Colors.white),
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

class _CustomArtworkServerTile extends ConsumerWidget {
  const _CustomArtworkServerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(animatedArtworkSettingsProvider);
    return ListTile(
      leading: const Icon(LucideIcons.server, color: Colors.white70),
      title: Text(l10n.customArtworkServer, style: _title()),
      subtitle: Text(
        s.customServerUrl != null && s.customServerUrl!.isNotEmpty
            ? s.customServerUrl!
            : l10n.customArtworkServerDesc,
        style: _sub(),
      ),
      onTap: () async {
        final controller = TextEditingController(text: s.customServerUrl ?? '');
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).colorScheme.surfaceContainer,
            title: Text(l10n.customArtworkServer),
            content: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.100:5000',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () {
                  final text = controller.text.trim();
                  ref
                      .read(animatedArtworkSettingsProvider.notifier)
                      .update((curr) => curr.copyWith(customServerUrl: text.isEmpty ? null : text));
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
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
      leading: const Icon(LucideIcons.hardDrive, color: Colors.white70),
      title: Text(l10n.animatedArtworkCacheLimit, style: _title()),
      trailing: DropdownButton<int>(
        value: s.cacheLimitMB,
        underline: const SizedBox.shrink(),
        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        style: AppFonts.jostStyle(color: Colors.white),
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
        style: AppFonts.jostStyle(color: Colors.redAccent),
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
