import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/providers/providers.dart';
import 'package:looper_player/core/services/update/apk_installer.dart';
import 'package:looper_player/core/services/update/apk_update_notifier.dart';
import 'package:looper_player/core/services/update/update_service.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/ui/widgets/sheets/apk_update_sheet.dart';

import '../android/shell/android_main_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger library scan for saved folders on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait for settings to load from DB
      await ref.read(settingsProvider.notifier).initialization;
      final settings = ref.read(settingsProvider);

      // Check for application updates on GitHub
      _checkForUpdates();

      // Handle file passed via CLI arguments
      final initialFile = ref.read(startupFileProvider);
      if (initialFile != null) {
        ref.read(playbackProvider.notifier).playFromFile(initialFile);
        return;
      }
    });
  }

  /// The github APK downloads and installs the release itself, so it gets
  /// the update sheet; every other build is pointed at its store or the
  /// release page.
  Future<void> _checkForUpdates() async {
    if (!ApkInstaller.supported) return UpdateService.checkForUpdates();
    final prompt = await ref.read(apkUpdateProvider.notifier).checkOnLaunch();
    if (prompt && mounted) showApkUpdateSheet(context);
  }

  @override
  Widget build(BuildContext context) => const AndroidMainScreen();
}
