// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_group_widgets.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../widgets/qr_code_viewer.dart';

class NewPrivateChatView extends StatelessWidget {
  final NewPrivateChatController controller;

  const NewPrivateChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final searchResponse = controller.searchResponse;
    final userId = Matrix.of(context).client.userID!;
    final group = controller.group;
    final groupNetwork = group.network;
    final features = MatrixFeatures.forClient(Matrix.of(context).client);
    final showIdentity = features.isRelevant(MatrixFeature.identity);
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: const Center(child: BackButton()),
        title: Text(
          group.isGroup
              ? L10n.of(context).newGroupChat
              : L10n.of(context).newChat,
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      floatingActionButton: group.isGroup
          ? FloatingActionButton.extended(
              onPressed: controller.createGroup,
              icon: const Icon(Icons.arrow_forward_outlined),
              label: Text(L10n.of(context).next),
            )
          : null,
      body: MaxWidthBody(
        withScrolling: false,
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            GroupRecipientsBar(group),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: TextField(
                controller: controller.controller,
                onChanged: controller.searchUsers,
                onSubmitted: controller.submitSearch,
                decoration: InputDecoration(
                  hintText: !group.isEmpty
                      ? L10n.of(context).anyoneElse
                      : showIdentity
                      ? L10n.of(context).searchForUsers
                      : L10n.of(context).newChatSearchHint,
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.normal,
                  ),
                  prefixIcon: searchResponse == null
                      ? const Icon(Icons.search_outlined)
                      : FutureBuilder(
                          future: searchResponse,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.all(10.0),
                                child: SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 1,
                                  ),
                                ),
                              );
                            }
                            return const Icon(Icons.search_outlined);
                          },
                        ),
                  suffixIcon: controller.controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_outlined),
                          onPressed: () {
                            controller.controller.clear();
                            controller.searchUsers();
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: FluffyThemes.animationDuration,
                child: searchResponse == null && !group.isEmpty
                    ? const SizedBox.shrink()
                    : searchResponse == null
                    ? ListView(
                        children: [
                          if (showIdentity) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18.0,
                              ),
                              child: SelectableText.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: L10n.of(context).yourGlobalUserIdIs,
                                    ),
                                    TextSpan(
                                      text: Matrix.of(context).client.userID,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (controller.offerPhoneContacts)
                            PhoneContactsOfferTile(controller),
                          if (showIdentity)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                child: Icon(Icons.adaptive.share_outlined),
                              ),
                              title: Text(L10n.of(context).shareInviteLink),
                              onTap: controller.inviteAction,
                            ),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.tertiaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onTertiaryContainer,
                              child: const Icon(Icons.group_add_outlined),
                            ),
                            title: Text(L10n.of(context).createGroup),
                            onTap: () => context.go('/rooms/newgroup'),
                          ),
                          if (PlatformInfos.isMobile && showIdentity)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                child: const Icon(
                                  Icons.qr_code_scanner_outlined,
                                ),
                              ),
                              title: Text(L10n.of(context).scanQrCode),
                              onTap: controller.openScannerAction,
                            ),
                          if (showIdentity)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 64.0,
                                  vertical: 24.0,
                                ),
                                child: Material(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius,
                                    ),
                                    side: BorderSide(
                                      width: 3,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  color: Colors.transparent,
                                  clipBehavior: Clip.hardEdge,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius,
                                    ),
                                    onTap: () =>
                                        showQrCodeViewer(context, userId),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 200,
                                        ),
                                        child: PrettyQrView.data(
                                          data: 'https://matrix.to/#/$userId',
                                          decoration: PrettyQrDecoration(
                                            shape: PrettyQrSmoothSymbol(
                                              roundFactor: 1,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : FutureBuilder(
                        future: searchResponse,
                        builder: (context, snapshot) {
                          final result = snapshot.data;
                          final error = snapshot.error;
                          if (error != null) {
                            return Column(
                              mainAxisAlignment: .center,
                              children: [
                                Text(
                                  error.toLocalizedString(context),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: controller.searchUsers,
                                  icon: const Icon(Icons.refresh_outlined),
                                  label: Text(L10n.of(context).tryAgain),
                                ),
                              ],
                            );
                          }
                          if (result == null) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                          }
                          final people = controller.people;
                          final offer = controller.offerPhoneContacts ? 1 : 0;
                          if (result.isEmpty && people.isEmpty && offer == 0) {
                            return Column(
                              mainAxisAlignment: .center,
                              children: [
                                const Icon(Icons.search_outlined, size: 86),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    L10n.of(context).noUsersFoundWithQuery(
                                      controller.controller.text,
                                    ),
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            );
                          }
                          return ListView.builder(
                            itemCount: offer + people.length + result.length,
                            itemBuilder: (context, i) {
                              if (i < offer) {
                                return PhoneContactsOfferTile(controller);
                              }
                              i -= offer;
                              if (i < people.length) {
                                final person = people[i];
                                return NewChatPersonTile(
                                  person: person,
                                  onTap: () => controller.openPerson(person),
                                  onLongPress: () =>
                                      controller.pickForGroup(person),
                                  picked: group.contains(person),
                                  blockedReason: controller.groupBlockOf(
                                    person,
                                  ),
                                );
                              }
                              final contact = result[i - people.length];
                              final displayname =
                                  contact.displayName ??
                                  contact.userId.localpart ??
                                  contact.userId;
                              // A Matrix user is on none of the networks a
                              // group starts on.
                              return ListTile(
                                enabled: groupNetwork == null,
                                leading: Avatar(
                                  name: displayname,
                                  mxContent: contact.avatarUrl,
                                  presenceUserId: contact.userId,
                                ),
                                title: Text(displayname),
                                subtitle: Text(
                                  groupNetwork == null
                                      ? features.userLabel(contact.userId)
                                      : L10n.of(context).notOnNetwork(
                                          groupNetwork.bridge.displayName,
                                        ),
                                ),
                                onTap: () => controller.openUserModal(contact),
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One person in New Chat's results: their chat, or someone the user's
/// networks or phone contacts know, with the networks that reach them as
/// grey icons at the end.
///
/// While a group is being picked, a person in it shows a tick, and one who
/// cannot join it is greyed out with [blockedReason] as the second line.
class NewChatPersonTile extends StatelessWidget {
  final NewChatPerson person;
  final void Function() onTap;
  final void Function()? onLongPress;
  final bool picked;
  final String? blockedReason;

  const NewChatPersonTile({
    required this.person,
    required this.onTap,
    this.onLongPress,
    this.picked = false,
    this.blockedReason,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = person.phone;
    final detail = person.typed
        ? L10n.of(context).phoneNumber
        : person.chat != null
        ? null
        : phone != null
        ? formatPhoneForDisplay(phone)
        : person.email;
    final reason = blockedReason;
    return ListTile(
      enabled: reason == null,
      selected: picked,
      leading: person.typed
          ? CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
              child: const Icon(Icons.dialpad_outlined),
            )
          : Avatar(name: person.name, mxContent: person.avatar),
      title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: reason != null
          ? Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis)
          : detail == null || detail == person.name
          ? null
          : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: picked
          ? const Icon(Icons.check_circle)
          : person.networks.isEmpty
          ? null
          : MonochromeNetworkIcons.icons(
              icons: [
                for (final network in person.networks)
                  (icon: network.icon, name: network.name),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// The row that offers to list the phone's contacts, on Android until the
/// user answers.
class PhoneContactsOfferTile extends StatelessWidget {
  final NewPrivateChatController controller;

  const PhoneContactsOfferTile(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: const Icon(Icons.contacts_outlined),
      ),
      title: Text(l10n.showPhoneContacts),
      subtitle: Text(l10n.showPhoneContactsHint),
      trailing: IconButton(
        icon: const Icon(Icons.close_outlined),
        tooltip: l10n.notNow,
        onPressed: controller.declinePhoneContacts,
      ),
      onTap: controller.allowPhoneContacts,
    );
  }
}
