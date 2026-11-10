part of 'welcome_screen.dart';

/// Online setup after the storage scan, in Mochy's order: ask, pick taste
/// (the existing TasteSetupScreen), "Last one" toggles with live demos,
/// then "You're good to go". Styled like the rest of the welcome screen.
class _OnlineSetupFlow extends ConsumerStatefulWidget {
  const _OnlineSetupFlow({
    super.key,
    required this.noSongs,
    required this.onSkip,
    required this.onDone,
  });

  /// Opened from "no music found": different title, Skip goes back.
  final bool noSongs;
  final VoidCallback onSkip;
  final VoidCallback onDone;

  @override
  ConsumerState<_OnlineSetupFlow> createState() => _OnlineSetupFlowState();
}

class _OnlineSetupFlowState extends ConsumerState<_OnlineSetupFlow> {
  int _page = 0; // 0 ask, 1 last one, 2 good to go

  Future<void> _turnOn() async {
    AppHaptics.light();
    if (!ref.read(settingsProvider).enableInternet) {
      await ref.read(settingsProvider.notifier).updateEnableInternet(true);
    }
    await ref
        .read(onlineSettingsProvider.notifier)
        .update((s) => s.copyWith(enabled: true, disclaimerAccepted: true));
    if (!mounted) return;
    await Navigator.of(context).push(riseRoute(const TasteSetupScreen()));
    if (mounted) setState(() => _page = 1);
  }

  void _finishSoon() {
    AppHaptics.light();
    setState(() => _page = 2);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.15, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: switch (_page) {
        0 => _ask(l10n, accent),
        1 => _lastOne(l10n, accent),
        _ => _goodToGo(l10n, accent),
      },
    );
  }

  Widget _header(IconData icon, String title, String subtitle, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52.s,
          height: 52.s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.15),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: accent, size: 24.s),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          maxLines: 2,
          style: TextStyle(
            fontSize: 28.ts,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13.ts,
            color: Colors.white.withValues(alpha: 0.5),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _ask(AppLocalizations l10n, Color accent) {
    return Column(
      key: const ValueKey('online_ask'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          LucideIcons.cloud,
          widget.noSongs ? l10n.onlineSetupNoSongsTitle : l10n.onlineSetupTitle,
          l10n.onlineDisclaimerBody,
          accent,
        ),
        const SizedBox(height: 24),
        // Auto picks the SIM/network country; tap to change it.
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: const ContentRegionTile(),
        ),
        const SizedBox(height: 32),
        _PremiumButton(
          onPressed: _turnOn,
          label: l10n.onlineSetupYes,
          icon: LucideIcons.cloud,
          gradientColors: [accent, accent.withValues(alpha: 0.75)],
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: widget.onSkip,
            child: Text(
              l10n.onlineSetupSkip,
              style: TextStyle(
                fontSize: 12.ts,
                color: Colors.white60,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A cover from the user's own library for the demos; null = gradient.
  ImageProvider? _demoArt() {
    for (final song in ref.read(libraryProvider).songs.take(200)) {
      final p = song.artPath;
      if (p != null && p.isNotEmpty && File(p).existsSync()) {
        return ResizeImage(FileImage(File(p)), width: 400);
      }
    }
    return null;
  }

  Widget _lastOne(AppLocalizations l10n, Color accent) {
    final art = ref.watch(animatedArtworkSettingsProvider);
    final cover = _demoArt();
    void setArt(AnimatedArtworkSettings Function(AnimatedArtworkSettings) f) {
      AppHaptics.light();
      ref.read(animatedArtworkSettingsProvider.notifier).update(f);
    }

    // Only the two settings that change the player the most; the rest stay
    // at their defaults and live in Settings.
    return Column(
      key: const ValueKey('online_last_one'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          LucideIcons.slidersHorizontal,
          l10n.onlineSetupLastOneTitle,
          l10n.onlineSetupLastOneDesc,
          accent,
        ),
        const SizedBox(height: 24),
        _DemoToggleCard(
          demo: _Demo.animatedArtwork,
          title: l10n.animatedArtworks,
          subtitle: l10n.animatedArtworksDesc,
          value: art.mode != AnimatedArtworkMode.never,
          accent: accent,
          cover: cover,
          onChanged: (v) => setArt(
            (s) => s.copyWith(
              mode: v ? AnimatedArtworkMode.always : AnimatedArtworkMode.never,
            ),
          ),
        ),
        _DemoToggleCard(
          demo: _Demo.immersive,
          title: l10n.immersivePlayerBackground,
          subtitle: l10n.immersivePlayerBackgroundDesc,
          value: art.immersiveBackground,
          accent: accent,
          cover: cover,
          onChanged: (v) => setArt((s) => s.copyWith(immersiveBackground: v)),
        ),
        const SizedBox(height: 24),
        _PremiumButton(
          onPressed: _finishSoon,
          label: l10n.onlineSetupNext,
          icon: LucideIcons.arrowRight,
          gradientColors: [accent, accent.withValues(alpha: 0.75)],
        ),
      ],
    );
  }

  Widget _goodToGo(AppLocalizations l10n, Color accent) {
    return Column(
      key: const ValueKey('online_done'),
      children: [
        const SizedBox(height: 40),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox(
            width: 160.s,
            height: 160.s,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A faint wave rings out as the tick lands.
                Container(
                  width: (80 + 80 * t).s,
                  height: (80 + 80 * t).s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.5 * (1 - t)),
                      width: 2,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: Curves.elasticOut.transform(t.clamp(0, 1)),
                  child: Container(
                    width: 80.s,
                    height: 80.s,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Icon(LucideIcons.check, size: 40.s, color: accent),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.onlineSetupDoneTitle,
          style: TextStyle(
            fontSize: 26.ts,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

enum _Demo { animatedArtwork, immersive }

/// A setting card that compares OFF and ON side by side as two tiny now
/// playing screens. The chosen side is lit; tapping a side picks it.
class _DemoToggleCard extends StatefulWidget {
  const _DemoToggleCard({
    required this.demo,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.cover,
    required this.onChanged,
  });

  final _Demo demo;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ImageProvider? cover;
  final ValueChanged<bool> onChanged;

  @override
  State<_DemoToggleCard> createState() => _DemoToggleCardState();
}

class _DemoToggleCardState extends State<_DemoToggleCard>
    with SingleTickerProviderStateMixin {
  // The ON phone always loops so the difference is visible before choosing.
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _side(bool on) {
    final selected = widget.value == on;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onChanged(on),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: selected ? 1 : 0.45,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                    color: selected ? widget.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => _PhoneMock(
                      demo: widget.demo,
                      on: on,
                      t: on ? _c.value : 0,
                      accent: widget.accent,
                      cover: widget.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                on ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 11.ts,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: selected ? widget.accent : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [_side(false), const SizedBox(width: 20), _side(true)],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 15.ts,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 11.ts,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: widget.value,
                activeThumbColor: widget.accent,
                onChanged: widget.onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small now playing screen: cover, title lines, seek bar, controls.
/// [t] runs 0..1 in a loop for the ON side and stays 0 for OFF.
class _PhoneMock extends StatelessWidget {
  const _PhoneMock({
    required this.demo,
    required this.on,
    required this.t,
    required this.accent,
    required this.cover,
  });

  final _Demo demo;
  final bool on;
  final double t;
  final Color accent;
  final ImageProvider? cover;

  Widget _art({BoxFit fit = BoxFit.cover}) {
    if (cover != null) return Image(image: cover!, fit: fit);
    final hsl = HSLColor.fromColor(accent);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, hsl.withHue((hsl.hue + 50) % 360).toColor()],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        LucideIcons.music,
        color: Colors.white.withValues(alpha: 0.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wave = math.sin(t * 2 * math.pi); // -1..1
    final immersive = demo == _Demo.immersive && on;
    final moving = demo == _Demo.animatedArtwork && on;

    // Animated artwork: the cover itself plays - a slow push-in and drift,
    // with a soft light passing over it, like a motion cover video.
    Widget cover = _art();
    if (moving) {
      cover = Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(
            offset: Offset(4 * wave, 2 * math.cos(t * 2 * math.pi)),
            child: Transform.scale(scale: 1.18 + 0.08 * wave, child: cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-2.5 + 5 * t, -1),
                  end: Alignment(-1.5 + 5 * t, 1),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: Looper's blurred artwork, or the immersive
          // full-bleed artwork that slowly drifts.
          if (immersive)
            Transform.scale(
              scale: 1.25 + 0.06 * wave,
              alignment: Alignment(0.3 * wave, -0.4),
              child: _art(),
            )
          else
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Opacity(opacity: 0.55, child: _art()),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1],
                colors: [
                  Colors.black.withValues(alpha: immersive ? 0 : 0.35),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Immersive hides the cover: the art is the whole screen.
                if (!immersive)
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: cover,
                    ),
                  ),
                const Spacer(),
                for (final (w, a) in [(0.75, 0.9), (0.5, 0.45)]) ...[
                  FractionallySizedBox(
                    widthFactor: w,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: a),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.35 + (on ? 0.4 * t : 0),
                    child: Container(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Icon(LucideIcons.skipBack, size: 12, color: Colors.white70),
                    Icon(LucideIcons.pause, size: 16, color: Colors.white),
                    Icon(
                      LucideIcons.skipForward,
                      size: 12,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
