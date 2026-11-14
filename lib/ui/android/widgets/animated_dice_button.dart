import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:looper_player/core/utils/motion.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AnimatedDiceButton extends StatefulWidget {
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final String? tooltip;
  final EdgeInsetsGeometry padding;

  const AnimatedDiceButton({
    super.key,
    required this.onTap,
    this.size = 20.0,
    this.color,
    this.tooltip,
    this.padding = const EdgeInsets.all(8.0),
  });

  @override
  State<AnimatedDiceButton> createState() => _AnimatedDiceButtonState();
}

class _AnimatedDiceButtonState extends State<AnimatedDiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    if (!mounted) return;
    final reduced = Motion.reducedOf(context);
    if (!reduced) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? Colors.white;
    final reduced = Motion.reducedOf(context);

    Widget iconWidget = Icon(
      LucideIcons.dices,
      size: widget.size,
      color: effectiveColor,
    );

    if (!reduced) {
      iconWidget = AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * 2 * math.pi;
          final scale = 1.0 + (math.sin(_animation.value * math.pi) * 0.2);
          return Transform.scale(
            scale: scale,
            child: Transform.rotate(
              angle: angle,
              child: child,
            ),
          );
        },
        child: iconWidget,
      );
    }

    Widget button = InkWell(
      customBorder: const CircleBorder(),
      onTap: _handleTap,
      child: Padding(
        padding: widget.padding,
        child: iconWidget,
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return Material(
      color: Colors.transparent,
      child: button,
    );
  }
}
