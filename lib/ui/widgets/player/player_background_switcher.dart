import 'package:flutter/widgets.dart';
import 'package:looper_player/core/utils/motion.dart';

const Duration kPlayerBackgroundFade = Duration(milliseconds: 900);
const Curve kPlayerBackgroundCurve = Curves.easeInOut;

/// Crossfades the now playing background when [child]'s key changes. The old
/// layer stays solid under the incoming one, so the screen behind never shows
/// through mid-fade. Children must be opaque.
class PlayerBackgroundSwitcher extends StatelessWidget {
  const PlayerBackgroundSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration duration = Motion.reduced
        ? Duration.zero
        : kPlayerBackgroundFade;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: kPlayerBackgroundCurve,
      switchOutCurve: Curves.linear,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) =>
          _HeldFade(animation: animation, child: child),
      child: child,
    );
  }
}

/// Follows [animation] while it runs forward and holds its opacity once it
/// reverses, so a layer replaced mid-fade doesn't jump or fade out.
class _HeldFade extends StatefulWidget {
  const _HeldFade({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_HeldFade> createState() => _HeldFadeState();
}

class _HeldFadeState extends State<_HeldFade> {
  late double _opacity = widget.animation.value;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_onTick);
  }

  @override
  void didUpdateWidget(_HeldFade old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeListener(_onTick);
      widget.animation.addListener(_onTick);
    }
  }

  void _onTick() {
    final AnimationStatus status = widget.animation.status;
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      return;
    }
    if (widget.animation.value != _opacity) {
      setState(() => _opacity = widget.animation.value);
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: _opacity, child: widget.child);
}
