import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/motion/app_routes.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/online/data/not_interested_store.dart';
import 'package:looper_player/features/online/data/taste_profile_engine.dart';
import 'package:looper_player/features/online/data/taste_profile_store.dart';
import 'package:looper_player/features/online/data/taste_store.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/taste_setup_screen.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TasteProfilesScreen extends ConsumerStatefulWidget {
  const TasteProfilesScreen({super.key});

  @override
  ConsumerState<TasteProfilesScreen> createState() =>
      _TasteProfilesScreenState();
}

class _TasteProfilesScreenState extends ConsumerState<TasteProfilesScreen> {
  TasteProfileSnapshot? _snapshot;
  Set<String> _hiddenProfiles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await NotInterestedStore.load();
    final hidden = await TasteProfileStore.getHiddenProfiles();
    final snapshot = await TasteProfileStore.getOrBuild();
    if (mounted) {
      setState(() {
        _hiddenProfiles = hidden;
        _snapshot = snapshot;
        _loading = false;
      });
    }
  }

  TextStyle _title() =>
      AppFonts.jostStyle(color: Colors.white, fontWeight: FontWeight.w500);
  TextStyle _sub() => AppFonts.jostStyle(color: Colors.white54, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = ref.watch(settingsProvider).accent;
    final taste = ref.watch(tasteProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.onlineYourTaste, style: _title()),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Taste setup section
                Card(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: Icon(LucideIcons.sparkles, color: accent),
                    title: Text(l10n.tasteGenresTitle, style: _title()),
                    subtitle: Text(
                      taste.genres.isNotEmpty
                          ? taste.genres.join(', ')
                          : l10n.onlinePersonalizeBody,
                      style: _sub(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(
                      LucideIcons.chevronRight,
                      color: Colors.white38,
                    ),
                    onTap: () async {
                      await Navigator.of(
                        context,
                      ).push(riseRoute(const TasteSetupScreen()));
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Detected mix shelves
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.detectedProfiles,
                        style: AppFonts.jostStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(l10n.detectedProfilesDesc, style: _sub()),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_snapshot == null || _snapshot!.profiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Listen to more songs to automatically detect your taste mixes.',
                      style: _sub(),
                    ),
                  )
                else
                  for (final profile in _snapshot!.profiles)
                    SwitchListTile(
                      secondary: const Icon(
                        LucideIcons.disc,
                        color: Colors.white70,
                      ),
                      title: Text(profile.displayTitle, style: _title()),
                      subtitle: Text(
                        profile.topArtists.join(', '),
                        style: _sub(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      activeThumbColor: accent,
                      value: !_hiddenProfiles.contains(profile.key),
                      onChanged: (visible) async {
                        if (visible) {
                          await TasteProfileStore.unhideProfile(profile.key);
                          setState(() => _hiddenProfiles.remove(profile.key));
                        } else {
                          await TasteProfileStore.hideProfile(profile.key);
                          setState(() => _hiddenProfiles.add(profile.key));
                        }
                        ref.invalidate(onlineHomeProvider);
                      },
                    ),

                const SizedBox(height: 24),

                // Hidden & Blocked items (NotInterestedStore)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${l10n.hiddenSongs} & ${l10n.blockedArtists}',
                    style: AppFonts.jostStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                if (NotInterestedStore.blockedArtists.isEmpty &&
                    NotInterestedStore.hiddenSongIds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.noHiddenItems, style: _sub()),
                  )
                else ...[
                  for (final artist in NotInterestedStore.blockedArtists)
                    ListTile(
                      leading: const Icon(
                        LucideIcons.userX,
                        color: Colors.redAccent,
                      ),
                      title: Text(artist, style: _title()),
                      trailing: TextButton(
                        onPressed: () async {
                          await NotInterestedStore.unblockArtist(artist);
                          ref.invalidate(onlineHomeProvider);
                          setState(() {});
                        },
                        child: const Text('Unblock'),
                      ),
                    ),
                  for (final id in NotInterestedStore.hiddenSongIds)
                    ListTile(
                      leading: const Icon(
                        LucideIcons.eyeOff,
                        color: Colors.white60,
                      ),
                      title: Text('Video: $id', style: _title()),
                      trailing: TextButton(
                        onPressed: () async {
                          await NotInterestedStore.unhideSong(id);
                          ref.invalidate(onlineHomeProvider);
                          setState(() {});
                        },
                        child: const Text('Unhide'),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
