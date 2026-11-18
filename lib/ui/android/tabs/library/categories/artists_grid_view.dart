import 'package:looper_player/core/motion/list_wave.dart';
import 'package:looper_player/core/providers/collection_navigation.dart';
import 'package:flutter/material.dart';
import 'package:looper_player/ui/widgets/common/filter_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/features/online/data/parsers.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/features/online/presentation/online_widgets.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:looper_player/ui/widgets/common/empty_state_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:isar_community/isar.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'library_categories_views.dart';

enum _ArtistSourceFilter { all, onDevice, youtube }

class ArtistsGridView extends ConsumerStatefulWidget {
  const ArtistsGridView({super.key});

  @override
  ConsumerState<ArtistsGridView> createState() => _ArtistsGridViewState();
}

class _ArtistsGridViewState extends ConsumerState<ArtistsGridView> {
  _ArtistSourceFilter _filter = _ArtistSourceFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sortOptionIndex = ref.watch(
      settingsProvider.select((s) => s.artistSortOptionIndex),
    );
    final sortOption = ArtistSortOption
        .values[sortOptionIndex.clamp(0, ArtistSortOption.values.length - 1)];
    final sortedArtists = ref.watch(artistsSortedProvider(sortOption));
    final onlineArtists =
        ref.watch(onlineAccountArtistsProvider).value ??
        const <OnlineCollection>[];
    final accent = ref.watch(settingsProvider).accent;

    final showOnline = onlineArtists.isNotEmpty;
    final showLocal =
        _filter == _ArtistSourceFilter.all ||
        _filter == _ArtistSourceFilter.onDevice;
    final showCloud =
        showOnline &&
        (_filter == _ArtistSourceFilter.all ||
            _filter == _ArtistSourceFilter.youtube);

    final q = CategorySearch.of(context);
    final displayLocal = showLocal
        ? [
            for (final a in sortedArtists)
              if (CategorySearch.matches(q, [a.name])) a,
          ]
        : const <Artist>[];
    // Deduplicate online artists that have local counterparts by name
    final localNames = {for (final a in sortedArtists) a.name.toLowerCase()};
    final displayOnline = showCloud
        ? [
            for (final a in onlineArtists)
              if ((!showLocal || !localNames.contains(a.title.toLowerCase())) &&
                  CategorySearch.matches(q, [a.title]))
                a,
          ]
        : const <OnlineCollection>[];

    final totalDisplayCount = displayLocal.length + displayOnline.length;

    if (sortedArtists.isEmpty && onlineArtists.isEmpty) {
      return EmptyStateCard(icon: LucideIcons.user, title: l10n.noArtistsFound);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showOnline)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterPill(
                    label:
                        'All (${sortedArtists.length + onlineArtists.length})',
                    isSelected: _filter == _ArtistSourceFilter.all,
                    accent: accent,
                    onTap: () =>
                        setState(() => _filter = _ArtistSourceFilter.all),
                  ),
                  const SizedBox(width: 8),
                  FilterPill(
                    label: 'On Device (${sortedArtists.length})',
                    isSelected: _filter == _ArtistSourceFilter.onDevice,
                    accent: accent,
                    onTap: () =>
                        setState(() => _filter = _ArtistSourceFilter.onDevice),
                  ),
                  const SizedBox(width: 8),
                  FilterPill(
                    label: 'YouTube Music (${onlineArtists.length})',
                    isSelected: _filter == _ArtistSourceFilter.youtube,
                    accent: accent,
                    onTap: () =>
                        setState(() => _filter = _ArtistSourceFilter.youtube),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: totalDisplayCount == 0
              ? EmptyStateCard(
                  icon: LucideIcons.user,
                  title: l10n.noArtistsFound,
                )
              : ListWave(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 20,
                      bottom: 200,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 24,
                          crossAxisSpacing: 24,
                          childAspectRatio: 0.8,
                        ),
                    itemCount: totalDisplayCount,
                    itemBuilder: waveItems((context, index) {
                      if (index < displayLocal.length) {
                        final artist = displayLocal[index];
                        return InkWell(
                          onTap: () async {
                            await ref
                                .read(appNavigationProvider.notifier)
                                .showArtist(artist, subtitle: l10n.artist);
                          },
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipOval(
                                  child: OptimizedImage(
                                    imageUrl:
                                        artist.artistImageUrl != null &&
                                            artist.artistImageUrl!.startsWith(
                                              'http',
                                            )
                                        ? artist.artistImageUrl
                                        : null,
                                    imagePath:
                                        artist.artistImageUrl != null &&
                                            !artist.artistImageUrl!.startsWith(
                                              'http',
                                            )
                                        ? artist.artistImageUrl
                                        : artist.artPath,
                                    fit: BoxFit.cover,
                                    placeholder: Container(
                                      color: Colors.white10,
                                      child: const Center(
                                        child: Icon(
                                          LucideIcons.user,
                                          size: 40,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                artist.name,
                                style: AppFonts.jostStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }
                      final onlineIndex = index - displayLocal.length;
                      return _OnlineArtistItem(
                        artist: displayOnline[onlineIndex],
                      );
                    }),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OnlineArtistItem extends StatelessWidget {
  final OnlineCollection artist;
  const _OnlineArtistItem({required this.artist});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: () => openOnlineCollection(context, artist),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: OptimizedImage(
                      imageUrl: artist.thumbnail,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: Colors.white10,
                        child: const Center(
                          child: Icon(
                            LucideIcons.user,
                            size: 40,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
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
          const SizedBox(height: 12),
          Text(
            artist.title,
            style: AppFonts.jostStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            artist.subtitle ?? 'YouTube Music',
            style: AppFonts.jostStyle(fontSize: 12, color: Colors.white38),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
