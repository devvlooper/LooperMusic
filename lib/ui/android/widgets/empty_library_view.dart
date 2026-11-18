import 'package:flutter/material.dart';
import 'package:looper_player/ui/widgets/common/app_loading_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:looper_player/features/library/presentation/providers/library/library_notifier.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/folder_picker_helper.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';

class EmptyLibraryView extends ConsumerWidget {
  final String title;
  const EmptyLibraryView({super.key, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final isScanning = library.isScanning;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon or scanning animation
              if (isScanning)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: const AppLoadingIndicator(size: 96),
                )
              else
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Icon(
                    LucideIcons.music,
                    size: 48,
                    color: Colors.white70,
                  ),
                ),
              const SizedBox(height: 24),

              // Title
              Text(
                isScanning ? l10n.scanningStorage : title.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppFonts.jostStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                isScanning ? l10n.scanningStorageDesc : l10n.emptyLibraryDesc,
                textAlign: TextAlign.center,
                style: AppFonts.jostStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.4),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // Actions
              if (!isScanning) ...[
                // Primary Action: Scan Storage
                _EmptyActionButton(
                  onPressed: () {
                    AppHaptics.medium();
                    ref.read(libraryProvider.notifier).scanSavedFolders();
                  },
                  label: l10n.scanForMusic,
                  icon: LucideIcons.searchCode,
                  isPrimary: true,
                ),
                const SizedBox(height: 12),
                // Secondary Action: Select Folder
                _EmptyActionButton(
                  onPressed: () async {
                    AppHaptics.light();
                    await FolderPickerHelper.pickFolder(context, ref);
                  },
                  label: l10n.selectCustomFolder,
                  icon: LucideIcons.folderPlus,
                  isPrimary: false,
                ),
              ] else ...[
                // Loading indicator auxiliary status
                Text(
                  l10n.scanningInBackground,
                  style: AppFonts.jostStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final bool isPrimary;

  const _EmptyActionButton({
    required this.onPressed,
    required this.label,
    required this.icon,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.08),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isPrimary ? Colors.black : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppFonts.jostStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isPrimary ? Colors.black : Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
