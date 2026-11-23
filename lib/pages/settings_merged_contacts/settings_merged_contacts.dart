// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/manage_merged_contact_sheet.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_suggestion_card.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:material_ui/material_ui.dart';

/// Settings > Chat > Merged contacts: every merged contact, the pending
/// merge suggestions (weak ones included, which the chat list never shows),
/// and whether to suggest at all.
class SettingsMergedContacts extends StatefulWidget {
  const SettingsMergedContacts({super.key});

  @override
  State<SettingsMergedContacts> createState() => _SettingsMergedContactsState();
}

class _SettingsMergedContactsState extends State<SettingsMergedContacts> {
  Future<void> _pickRegion() async {
    final l10n = L10n.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.phoneNumberRegion),
        children: [
          for (final (value, label) in [
            ('', l10n.phoneRegionAutomatic),
            ('US', l10n.phoneRegionNorthAmerica),
            ('other', l10n.phoneRegionOther),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Text(label),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await AppSettings.mergedContactsPhoneRegion.setItem(picked);
    if (!mounted) return;
    setState(() {});
    MergeSuggestionService.forClient(
      Matrix.of(context).client,
    ).schedule(immediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final store = MergedContactsStore.forClient(client);
    final service = MergeSuggestionService.forClient(client);
    final locals = MatrixLocals(l10n);
    final region = AppSettings.mergedContactsPhoneRegion.value;
    Widget header(String text) => ListTile(
      title: Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mergedContacts),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(subtitle: Text(l10n.mergedContactsDescription)),
            SettingsSwitchListTile.adaptive(
              title: l10n.suggestMerges,
              subtitle: l10n.suggestMergesDescription,
              setting: AppSettings.mergedContactSuggestions,
              onChanged: (_) => service.schedule(immediately: true),
            ),
            ListTile(
              title: Text(l10n.phoneNumberRegion),
              subtitle: Text(switch (region) {
                '' => l10n.phoneRegionAutomatic,
                'US' => l10n.phoneRegionNorthAmerica,
                _ => l10n.phoneRegionOther,
              }),
              onTap: _pickRegion,
            ),
            const Divider(),
            header(l10n.mergeSuggestions),
            ValueListenableBuilder(
              valueListenable: service.suggestions,
              builder: (context, suggestions, _) => suggestions.isEmpty
                  ? ListTile(subtitle: Text(l10n.noMergeSuggestions))
                  : Column(
                      children: [
                        for (final suggestion in suggestions)
                          MergeSuggestionCard(
                            key: ValueKey(suggestion.roomIds.join()),
                            client: client,
                            suggestion: suggestion,
                          ),
                      ],
                    ),
            ),
            const Divider(),
            header(l10n.mergedContacts),
            ValueListenableBuilder(
              valueListenable: store.revision,
              builder: (context, _, _) {
                final spaces = spacesByChild(client);
                final contacts = [
                  for (final entry in store.contacts)
                    ?MergedContact.resolve(client, entry),
                ];
                if (contacts.isEmpty) {
                  return ListTile(subtitle: Text(l10n.noMergedContacts));
                }
                return Column(
                  children: [
                    for (final contact in contacts)
                      ListTile(
                        leading: Avatar(
                          mxContent: contact.avatar,
                          name: contact.displayName(locals),
                        ),
                        title: Text(contact.displayName(locals)),
                        subtitle: Text(
                          contact.rooms
                              .map(
                                (room) =>
                                    networkName(room, spaces[room.id], locals),
                              )
                              .join(', '),
                        ),
                        trailing: const Icon(Icons.chevron_right_outlined),
                        onTap: () =>
                            showManageMergedContactSheet(context, contact.id),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
