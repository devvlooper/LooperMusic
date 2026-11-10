part of 'settings_view.dart';

extension _SettingsCategoryGroup on _SettingsViewState {
  Widget _buildCategoryGroup({
    required BuildContext context,
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required ColorScheme colorScheme,
    required bool useBlur,
    required AppSettings settings,
  }) {
    return MochyCardRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () {
        AppHaptics.light();
        if (id == 'support_us') {
          _showSupportUsDialog(context, colorScheme, useBlur);
          return;
        }
        // Routed through appNavigationProvider (not a raw Navigator push) so
        // the sub-page is tracked in nav history -- otherwise the system back
        // button's PopScope handler (which always resolves through
        // appNavigationProvider.goBack()) has no record of this level and
        // collapses straight past both this screen and Settings back to the
        // main tab in one shot.
        ref
            .read(appNavigationProvider.notifier)
            .showSettingsCategory(id: id, title: title);
      },
    );
  }
}
