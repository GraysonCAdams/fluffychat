// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/matrix.dart';
import 'settings_homeserver.dart';

class SettingsHomeserverView extends StatelessWidget {
  final SettingsHomeserverController controller;

  const SettingsHomeserverView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;

    final l10n = L10n.of(context);

    Widget link(String title, Uri uri) => SettingsTile(
      title: Text(title),
      subtitle: Linkify(
        text: uri.toString(),
        style: TextStyle(color: theme.colorScheme.onSurface),
        textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        options: const LinkifyOptions(humanize: false),
        linkStyle: TextStyle(
          color: theme.colorScheme.primary,
          decorationColor: theme.colorScheme.primary,
        ),
        onOpen: (link) => launchUrlString(link.url),
      ),
    );

    Widget failure(Object error) => SettingsGroup(
      children: [
        SettingsTile(
          leading: Icon(Icons.error_outlined, color: theme.colorScheme.error),
          title: Text(
            error.toLocalizedString(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );

    const loading = Padding(
      padding: EdgeInsets.all(SettingsMetrics.rowInset),
      child: Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
    );

    return SelectionArea(
      child: SettingsPage(
        title: l10n.aboutHomeserver(client.userID?.domain ?? 'Homeserver'),
        children: [
          SettingsSectionHeader(l10n.serverInformation),
          FutureBuilder(
            future: controller.serverInfoFuture,
            builder: (context, snapshot) {
              final error = snapshot.error;
              if (error != null) return failure(error);
              final data = snapshot.data;
              if (data == null) return loading;
              return SettingsGroup(
                children: [
                  SettingsTile(
                    title: Text(l10n.name),
                    subtitle: Text(data.name),
                  ),
                  SettingsTile(
                    title: Text(l10n.version),
                    subtitle: Text(data.version),
                  ),
                  link(l10n.federationBaseUrl, data.federationBaseUrl),
                ],
              );
            },
          ),
          SettingsSectionHeader(l10n.settingsSupport),
          FutureBuilder(
            future: controller.wellknownSupportFuture,
            builder: (context, snapshot) {
              final error = snapshot.error;
              final data = snapshot.data;
              if (error != null) {
                return SettingsGroup(
                  children: [
                    SettingsTile(
                      leading: const Icon(Icons.error_outlined),
                      title: Text(
                        error.toLocalizedString(
                          context,
                          ExceptionContext.checkServerSupportInfo,
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                );
              }
              if (data == null) return loading;
              final supportPage = data.supportPage;
              final contacts = data.contacts;
              if (supportPage == null && contacts == null) {
                return SettingsGroup(
                  children: [
                    SettingsTile(
                      leading: const Icon(Icons.error_outlined),
                      title: Text(
                        l10n.noContactInformationProvided,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                );
              }
              return SettingsGroup(
                children: [
                  if (supportPage != null)
                    SettingsTile(
                      title: Text(l10n.supportPage),
                      subtitle: Text(supportPage.toString()),
                    ),
                  if (contacts != null)
                    for (final contact in contacts)
                      SettingsTile(
                        title: Text(contact.role.localizedString(l10n)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: .min,
                          children: [
                            if (contact.emailAddress != null)
                              Text(contact.emailAddress!),
                            if (contact.matrixId != null)
                              Text(contact.matrixId!),
                          ],
                        ),
                      ),
                ],
              );
            },
          ),
          FutureBuilder(
            future: controller.wellknownFuture,
            builder: (context, snapshot) {
              final error = snapshot.error;
              if (error != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: failure(error),
                );
              }
              final wellKnown = snapshot.data;
              if (wellKnown == null) return loading;
              final identityServer = wellKnown.mIdentityServer;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSectionHeader(l10n.clientWellKnownInformation),
                  SettingsGroup(
                    children: [
                      link(l10n.baseUrl, wellKnown.mHomeserver.baseUrl),
                      if (identityServer != null)
                        link(l10n.identityServer, identityServer.baseUrl),
                      for (final entry
                          in wellKnown.additionalProperties.entries)
                        SettingsTile(
                          title: Text(entry.key),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Material(
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius / 2,
                              ),
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  const JsonEncoder.withIndent(
                                    '    ',
                                  ).convert(entry.value),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

extension on Role {
  String localizedString(L10n l10n) {
    switch (this) {
      case Role.mRoleAdmin:
        return l10n.contactServerAdmin;
      case Role.mRoleSecurity:
        return l10n.contactServerSecurity;
    }
  }
}
