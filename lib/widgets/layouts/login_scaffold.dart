// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/seam_mark.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// The frame of the sign-in and setup pages that follow the welcome page.
///
/// On a phone it is a plain [Scaffold]. On a wide window the page sits in a
/// card [cardWidth] dp wide, centred on Seam Cobalt (a deep navy in dark
/// mode) with a large, faint Seam mark in the corner, and the Terms of use,
/// Privacy policy, Help and About links underneath.
class LoginScaffold extends StatelessWidget {
  final Widget body;
  final AppBar? appBar;
  final Widget? bottomNavigationBar;

  const LoginScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
  });

  static const double cardWidth = 440;
  static const double cardMaxHeight = 680;

  /// The brand background's two gradient stops, top left to bottom right.
  static (Color, Color) backgroundColors(Brightness brightness) =>
      brightness == Brightness.dark
      ? (const Color(0xFF0B1F4D), const Color(0xFF07142F))
      : (AppConfig.primaryColor, const Color(0xFF1449B3));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileMode = !FluffyThemes.isColumnModeByWidth(
          constraints.maxWidth,
        );
        if (isMobileMode) {
          return Scaffold(
            key: const Key('LoginScaffold'),
            appBar: appBar,
            body: SafeArea(child: body),
            bottomNavigationBar: bottomNavigationBar,
          );
        }
        final (start, end) = backgroundColors(theme.brightness);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [start, end],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              PositionedDirectional(
                end: -120,
                bottom: -140,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: theme.brightness == Brightness.dark ? .07 : .10,
                    child: SeamMark(
                      size: 620,
                      pale: SeamStitchPainter.faded(Colors.white),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Material(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          clipBehavior: Clip.hardEdge,
                          elevation: 8,
                          shadowColor: Colors.black54,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: cardWidth,
                              maxHeight: cardMaxHeight,
                            ),
                            child: Scaffold(
                              key: const Key('LoginScaffold'),
                              appBar: appBar,
                              body: SafeArea(child: body),
                              bottomNavigationBar: bottomNavigationBar,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _FooterLinks(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final style = TextButton.styleFrom(foregroundColor: Colors.white70);
    void open(String url) =>
        launchUrlString(url, mode: LaunchMode.externalApplication);
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              style: style,
              onPressed: () => open(AppSettings.termsOfUseUrl.value),
              child: Text(l10n.termsOfUse),
            ),
            TextButton(
              style: style,
              onPressed: () => open(AppSettings.privacyPolicyPageUrl.value),
              child: Text(l10n.privacyPolicy),
            ),
            TextButton(
              style: style,
              onPressed: () => open(AppConfig.sourceCodeUrl),
              child: Text(l10n.website),
            ),
            TextButton(
              style: style,
              onPressed: () => open(AppConfig.supportUrl),
              child: Text(l10n.help),
            ),
            TextButton(
              style: style,
              onPressed: () => PlatformInfos.showDialog(context),
              child: Text(l10n.about),
            ),
          ],
        ),
      ),
    );
  }
}
