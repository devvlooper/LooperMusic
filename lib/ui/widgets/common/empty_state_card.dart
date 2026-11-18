import 'package:flutter/material.dart';
import 'package:looper_player/core/theme/app_fonts.dart';

/// Shared "nothing here yet" layout (icon badge + bold title + dimmed
/// subtitle, optionally followed by an action) - used so every empty grid/
/// list in the app reads at the same tier of polish instead of some falling
/// back to a bare centered [Text]. Mirrors the look [EmptyLibraryView]
/// already established for the Songs/Home empty state.
class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  /// Ignored: empty states are neutral (no accent) in the current design.
  final Color? accentColor;
  final Widget? action;

  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accentColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
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
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppFonts.jostStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: AppFonts.jostStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.4),
                    height: 1.5,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 36), action!],
            ],
          ),
        ),
      ),
    );
  }
}
