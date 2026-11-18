import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/online/presentation/online_providers.dart';
import 'package:looper_player/ui/widgets/common/app_skeleton.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Top bar with avatar and action buttons skeleton.
class HomeHeaderSkeleton extends StatelessWidget {
  const HomeHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Bone.circle(size: 38),
          Spacer(),
          Bone(width: 48, height: 48, uniRadius: 24),
          SizedBox(width: 5),
          Bone(width: 48, height: 48, uniRadius: 24),
        ],
      ),
    );
  }
}

/// Mood chips skeleton row matching `_MoodChipsRow` (46dp height).
class OnlineMoodChipsSkeleton extends StatelessWidget {
  const OnlineMoodChipsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Bone(width: 76, height: 34, uniRadius: 18),
          ),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Bone(width: 88, height: 34, uniRadius: 18),
          ),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Bone(width: 80, height: 34, uniRadius: 18),
          ),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Bone(width: 92, height: 34, uniRadius: 18),
          ),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Bone(width: 74, height: 34, uniRadius: 18),
          ),
        ],
      ),
    );
  }
}

/// One online song or collection card's skeleton, 100% matching `_Card` (140dp width).
class OnlineCardSkeleton extends StatelessWidget {
  const OnlineCardSkeleton({super.key, this.round = false});

  final bool round;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: round
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            round
                ? const Bone.circle(size: 132)
                : const Bone.square(size: 132, uniRadius: 12),
            const SizedBox(height: 8),
            Bone.text(fontSize: 13, width: round ? 80 : 100),
            const SizedBox(height: 2),
            Bone.text(fontSize: 11, width: round ? 60 : 70),
          ],
        ),
      ),
    );
  }
}

/// A full online horizontal shelf's skeleton, 100% matching `_StandardCardShelf` (196dp height).
class OnlineShelfSkeleton extends StatelessWidget {
  const OnlineShelfSkeleton({super.key, this.round = false});

  final bool round;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 8, 8),
          child: Row(
            children: [
              Bone.text(fontSize: 20, width: 140),
              Spacer(),
              Bone(width: 76, height: 32, uniRadius: 16),
            ],
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < 5; i++) OnlineCardSkeleton(round: round),
            ],
          ),
        ),
      ],
    );
  }
}

/// Skeleton for "Artists for you", 100% matching `_ArtistsForYouRow` (120dp height).
class OnlineArtistsForYouSkeleton extends StatelessWidget {
  const OnlineArtistsForYouSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 8, 8),
          child: Row(
            children: [
              Bone.text(fontSize: 20, width: 130),
              Spacer(),
              Bone(width: 76, height: 32, uniRadius: 16),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Bone.circle(size: 76),
                      SizedBox(height: 6),
                      Bone.text(fontSize: 12, width: 62),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quick Picks section skeleton, 100% matching `_buildQuickPicksSlivers` (3x2 grid).
class QuickPicksSkeleton extends StatelessWidget {
  const QuickPicksSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(fontSize: 24, width: 140),
                  SizedBox(height: 6),
                  Bone.text(fontSize: 14, width: 110),
                ],
              ),
              Bone.circle(size: 40),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(
              6,
              (_) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const Stack(
                  children: [
                    Positioned.fill(child: Bone(uniRadius: 8)),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Bone.text(fontSize: 13, width: 55),
                          SizedBox(height: 4),
                          Bone.text(fontSize: 10, width: 35),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Bone(width: 16, height: 6, uniRadius: 3),
            SizedBox(width: 6),
            Bone(width: 6, height: 6, uniRadius: 3),
            SizedBox(width: 6),
            Bone(width: 6, height: 6, uniRadius: 3),
          ],
        ),
      ],
    );
  }
}

/// Offline card row skeleton, 100% matching `_buildAlbumItem` / `_buildArtistItem` / `PlaylistCard`.
class OfflineCardRowSkeleton extends StatelessWidget {
  const OfflineCardRowSkeleton({super.key, required this.circle});

  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Bone.text(fontSize: 22, width: 120),
              Spacer(),
              Bone(width: 90, height: 40, uniRadius: 20),
            ],
          ),
        ),
        SizedBox(
          height: circle ? 108 : 190,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  width: circle ? 90 : 128,
                  margin: EdgeInsets.symmetric(horizontal: circle ? 4 : 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: circle
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      circle
                          ? const Bone.circle(size: 60)
                          : const Bone.square(size: 128, uniRadius: 5),
                      SizedBox(height: circle ? 10 : 8),
                      Bone.text(fontSize: 14, width: circle ? 64 : 90),
                      if (!circle) ...[
                        const SizedBox(height: 4),
                        const Bone.text(fontSize: 14, width: 56),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full layout skeleton for Online Home mode.
class OnlineHomeSkeleton extends StatelessWidget {
  const OnlineHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: const [
        HomeHeaderSkeleton(),
        OnlineMoodChipsSkeleton(),
        OnlineShelfSkeleton(),
        OnlineShelfSkeleton(),
        QuickPicksSkeleton(),
        SizedBox(height: 16),
        OnlineArtistsForYouSkeleton(),
        SizedBox(height: 16),
        OnlineShelfSkeleton(),
        SizedBox(height: 24),
      ],
    );
  }
}

/// Full layout skeleton for Offline Home mode.
class OfflineHomeSkeleton extends StatelessWidget {
  const OfflineHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: const [
        HomeHeaderSkeleton(),
        QuickPicksSkeleton(),
        SizedBox(height: 16),
        OfflineCardRowSkeleton(circle: false),
        SizedBox(height: 16),
        OfflineCardRowSkeleton(circle: true),
        SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Bone.text(fontSize: 24, width: 90),
              Bone(width: 76, height: 36, uniRadius: 18),
            ],
          ),
        ),
        SongRowSkeleton(index: 0),
        SongRowSkeleton(index: 1),
        SongRowSkeleton(index: 2),
        SizedBox(height: 24),
      ],
    );
  }
}

/// Shown on the Home tab while launching or loading.
/// Mirrors the real tab's layout (header, mood chips / quick picks, card rows)
/// so content smoothly drops into place.
class HomeSkeleton extends ConsumerWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onlineActive = ref.watch(onlineActiveProvider);
    return SafeArea(
      child: AppSkeleton(
        child: onlineActive
            ? const OnlineHomeSkeleton()
            : const OfflineHomeSkeleton(),
      ),
    );
  }
}

/// Shown on the Songs tab while the saved library loads after a cold start.
class SongsSkeleton extends StatelessWidget {
  const SongsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AppSkeleton(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Bone(width: 48, height: 48, uniRadius: 24),
                  Spacer(),
                  Bone.text(fontSize: 24, width: 120),
                  Spacer(),
                  Bone(width: 48, height: 48, uniRadius: 24),
                ],
              ),
            ),
            for (var i = 0; i < 14; i++) SongRowSkeleton(index: i),
          ],
        ),
      ),
    );
  }
}

/// One song row's bones (artwork, title, artist). Wrap in [AppSkeleton].
class SongRowSkeleton extends StatelessWidget {
  const SongRowSkeleton({super.key, this.index = 0});

  final int index;

  static const List<(double, double)> _widths = [
    (190, 120),
    (150, 95),
    (220, 140),
    (170, 80),
    (205, 125),
    (135, 105),
    (180, 90),
    (160, 130),
  ];

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _widths[index % _widths.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Bone.square(size: 52, uniRadius: 4),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone.text(fontSize: 15, width: title),
              const SizedBox(height: 6),
              Bone.text(fontSize: 12, width: subtitle),
            ],
          ),
        ],
      ),
    );
  }
}

/// One Home card row (artists, albums, playlists) whose data is still loading.
class HomeCardRowSkeleton extends StatelessWidget {
  const HomeCardRowSkeleton({super.key, required this.circle});

  final bool circle;

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(child: OfflineCardRowSkeleton(circle: circle));
  }
}

/// Cross-fades a tab between its load states (skeleton, scanning, empty,
/// content).
class LoadStateSwitcher extends StatelessWidget {
  const LoadStateSwitcher({
    super.key,
    required this.state,
    required this.child,
  });

  final String state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(state), child: child),
    );
  }
}
