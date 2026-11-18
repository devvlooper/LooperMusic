part of 'android_search_tab.dart';

/// Shown while the field is empty: recent searches as chips, and a line on
/// what the search covers.
class _SearchIdle extends ConsumerWidget {
  const _SearchIdle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final recent = ref.watch(recentSearchesProvider);

    if (recent.isEmpty) {
      return _CenteredMessage(
        icon: LucideIcons.search,
        title: l10n.searchLibraryHint,
        detail: l10n.searchScopeHint,
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 180),
      children: [
        AnalyzeSectionHeader(
          title: l10n.recentSearches,
          trailing: _Pill(
            label: l10n.clear,
            onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
          ),
        ),
        AnalyzeCard(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in recent)
                _RecentChip(
                  term: term,
                  onTap: () {
                    AppHaptics.light();
                    ref.read(searchQueryProvider.notifier).set(term);
                  },
                  onRemove: () =>
                      ref.read(recentSearchesProvider.notifier).remove(term),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            l10n.searchScopeHint,
            style: AppFonts.jostStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentChip({
    required this.term,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.history,
                size: 14,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.jostStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CenteredMessage(
      icon: LucideIcons.searchX,
      title: l10n.noResultsFor(query),
      detail: l10n.searchTryDifferent,
    );
  }
}

/// An icon, a line and a quieter line, centred in the space above the
/// keyboard. Scrollable so a short viewport never overflows.
class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppFonts.jostStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppFonts.jostStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
