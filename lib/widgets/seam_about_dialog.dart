// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// The About dialog, laid out as a Material 3 dialog: the app icon with
/// the name and version beside it, the legal notice, then the links as a
/// list whose icons line up, all 24dp from the sides, and "View licenses"
/// and "Close" at the bottom right. At most 560 wide.
class SeamAboutDialog extends StatelessWidget {
  final String version;

  const SeamAboutDialog({required this.version, super.key});

  static const double _inset = 24;
  static const double _iconSize = 56;

  Widget _icon() => ClipOval(
    key: const ValueKey('about-icon'),
    child: Image.asset(
      './assets/seam/seam_app_icon.png',
      width: _iconSize,
      height: _iconSize,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final name = AppSettings.applicationName.value;
    // The page the dialog was opened over, which the Logs and Configs
    // links go from once the dialog is closed.
    final router = GoRouter.maybeOf(context);

    void openRoute(String route) {
      Navigator.of(context).pop();
      router?.go(route);
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: _inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _inset),
                      child: Row(
                        spacing: 16,
                        children: [
                          _icon(),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  key: const ValueKey('about-name'),
                                  style: theme.textTheme.headlineSmall,
                                ),
                                Text(
                                  l10n.versionWithNumber(version),
                                  key: const ValueKey('about-version'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _inset),
                      // The AGPL's "Appropriate Legal Notices": credit,
                      // licence and no warranty. "View licenses" lists the
                      // licences.
                      child: Text(
                        l10n.aboutLegalNotice,
                        key: const ValueKey('about-legalese'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AboutLink(
                      key: const ValueKey('about-link-source'),
                      icon: Icons.source_outlined,
                      label: l10n.sourceCode,
                      onTap: () => launchUrlString(AppConfig.sourceCodeUrl),
                    ),
                    _AboutLink(
                      key: const ValueKey('about-link-upstream'),
                      icon: Icons.call_split_outlined,
                      label: l10n.originalProject,
                      onTap: () =>
                          launchUrlString(AppConfig.upstreamSourceCodeUrl),
                    ),
                    _AboutLink(
                      key: const ValueKey('about-link-logs'),
                      icon: Icons.list_outlined,
                      label: l10n.logs,
                      onTap: () => openRoute('/logs'),
                    ),
                    _AboutLink(
                      key: const ValueKey('about-link-configs'),
                      icon: Icons.settings_applications_outlined,
                      label: l10n.advancedConfigs,
                      onTap: () => openRoute('/configs'),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_inset, 16, _inset, _inset),
              // Wraps the buttons onto lines of their own when they do not
              // fit side by side, as AlertDialog's actions do.
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: name,
                      applicationVersion: version,
                      applicationIcon: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _icon(),
                      ),
                      applicationLegalese: l10n.aboutLegalNotice,
                    ),
                    child: Text(
                      MaterialLocalizations.of(context).viewLicensesButtonLabel,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A link in the About dialog: a full-width 48dp row with a 24dp icon
/// 24dp from the side and its label 16dp after it.
class _AboutLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AboutLink({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SeamAboutDialog._inset,
          ),
          child: Row(
            spacing: 16,
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
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
