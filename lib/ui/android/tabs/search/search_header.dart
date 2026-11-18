part of 'android_search_tab.dart';

/// The tab title over a pill search field, in Looper Analyze's header type.
class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              l10n.search,
              style: AppFonts.jostStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: AppFonts.jostStyle(color: Colors.white, fontSize: 15),
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: InputDecoration(
                hintText: l10n.searchLibraryHint,
                hintStyle: AppFonts.jostStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(LucideIcons.x, size: 18),
                          color: Colors.white70,
                          tooltip: l10n.clear,
                          onPressed: onClear,
                        ),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded pill button: [accent] filled with black text (Analyze's
/// selected pill), otherwise the quiet white-6% pill.
class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final IconData? icon;

  const _Pill({
    required this.label,
    this.onTap,
    this.accent = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final foreground = accent
        ? Colors.black
        : Colors.white.withValues(alpha: 0.85);
    return Material(
      color: accent ? accentColor : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.selection();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppFonts.jostStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 14, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Replaces the search field while songs are selected.
class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onAddToPlaylist;

  const _SelectionBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onSelectAll,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Tooltip(
              message: l10n.cancel,
              child: Material(
                color: Colors.white.withValues(alpha: 0.055),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onCancel,
                  child: const SizedBox.square(
                    dimension: 48,
                    child: Icon(LucideIcons.x, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                l10n.selectedCount(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.jostStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            _Pill(label: l10n.selectAll, onTap: onSelectAll),
            const SizedBox(width: 6),
            // Short label so the selection count keeps its room; the
            // tooltip carries the full name.
            Tooltip(
              message: l10n.addToPlaylists,
              child: _Pill(
                label: l10n.add,
                icon: LucideIcons.listPlus,
                accent: true,
                onTap: onAddToPlaylist,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The row of result-kind filters under the search field.
class _KindChips extends StatelessWidget {
  final Map<_SearchKind, int> counts;
  final _SearchKind selected;
  final ValueChanged<_SearchKind> onSelected;

  const _KindChips({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  String _label(AppLocalizations l10n, _SearchKind kind) => switch (kind) {
    _SearchKind.all => l10n.searchFilterAll,
    _SearchKind.songs => l10n.songs,
    _SearchKind.artists => l10n.artists,
    _SearchKind.albums => l10n.albums,
    _SearchKind.playlists => l10n.playlists,
    _SearchKind.genres => l10n.genres,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final kinds = counts.keys.toList();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        itemCount: kinds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final kind = kinds[index];
          final isSelected = kind == selected;
          final foreground = isSelected
              ? Colors.black
              : Colors.white.withValues(alpha: 0.6);
          return GestureDetector(
            onTap: isSelected ? null : () => onSelected(kind),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _label(l10n, kind),
                    style: AppFonts.jostStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (kind != _SearchKind.all) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${counts[kind]}',
                      style: AppFonts.jostStyle(
                        color: foreground.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
