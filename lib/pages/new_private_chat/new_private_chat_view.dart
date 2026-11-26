// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/compose_widgets.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../widgets/qr_code_viewer.dart';

/// The compose screen: the To field on top, the conversation with those
/// people in the middle, the composer at the bottom. While a name is typed
/// into the To field, the suggestions cover the conversation. A new group
/// on a network that takes a name is named from the title.
class NewPrivateChatView extends StatelessWidget {
  final NewPrivateChatController controller;

  const NewPrivateChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final conversation = controller.conversation;
    final typing = controller.controller.text.isNotEmpty;
    final Widget body;
    if (conversation != null) {
      body = ComposeConversation(
        key: ValueKey('compose-${conversation.room.id}'),
        chat: conversation,
        delivery: controller.widget.delivery,
      );
    } else if (controller.recipients.isEmpty) {
      body = _StartList(controller);
    } else {
      body = ComposeEmptyHistory(
        text: controller.group.isGroup
            ? l10n.composeNewGroupHint
            : l10n.composeNewChatHint,
      );
    }
    // The composer names the network the message goes out on: the chat's
    // bridge space, else the group's network.
    final locals = MatrixLocals(l10n);
    final hintText =
        (conversation == null
            ? null
            : spacesByChild(
                client,
              )[conversation.sendRoom.id]?.getLocalizedDisplayname(locals)) ??
        controller.group.bridge?.displayName ??
        l10n.writeAMessage;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: const Center(child: BackButton()),
        // The title button's own padding lines its text up with a plain
        // title's.
        titleSpacing: controller.showGroupName ? 8 : null,
        title: controller.showGroupName
            ? GroupTitleButton(controller)
            : Text(controller.group.isGroup ? l10n.newGroupChat : l10n.newChat),
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: Column(
        children: [
          RecipientField(controller),
          ComposeNetworkLine(controller),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: FluffyThemes.animationDuration,
                    child: body,
                  ),
                ),
                if (typing)
                  Positioned.fill(
                    child: Material(
                      key: const ValueKey('compose-suggestions'),
                      color: theme.colorScheme.surface,
                      child: _Suggestions(controller),
                    ),
                  ),
              ],
            ),
          ),
          ComposeBar(controller, hintText: hintText),
        ],
      ),
    );
  }
}

/// What the conversation area shows before anyone is in the To field: the
/// offer to read the phone's contacts, and the ways to reach someone that
/// the To field cannot (an invite link, a QR code, a Matrix-only group).
class _StartList extends StatelessWidget {
  final NewPrivateChatController controller;

  const _StartList(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final userId = client.userID!;
    final features = MatrixFeatures.forClient(client);
    final showIdentity = features.isRelevant(MatrixFeature.identity);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (showIdentity) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(text: L10n.of(context).yourGlobalUserIdIs),
                  TextSpan(
                    text: userId,
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
        if (controller.offerPhoneContacts) PhoneContactsOfferTile(controller),
        if (showIdentity)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
              child: Icon(Icons.adaptive.share_outlined),
            ),
            title: Text(L10n.of(context).shareInviteLink),
            onTap: controller.inviteAction,
          ),
        // A group with people on the user's networks starts by adding a
        // second person to the To field; a Matrix-only group has its own
        // page for an account with no network.
        if (controller.bridges.isEmpty)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.tertiaryContainer,
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              child: const Icon(Icons.group_add_outlined),
            ),
            title: Text(L10n.of(context).createGroup),
            onTap: () => context.go('/rooms/newgroup'),
          ),
        if (PlatformInfos.isMobile && showIdentity)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: const Icon(Icons.qr_code_scanner_outlined),
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
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  side: BorderSide(width: 3, color: theme.colorScheme.primary),
                ),
                color: Colors.transparent,
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  onTap: () => showQrCodeViewer(context, userId),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
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
    );
  }
}

/// The people the To field's text finds: chats, bridge contacts and phone
/// contacts one row each, then Matrix users from the directory. A tap puts
/// one in the To field; someone already there shows a tick, and someone
/// who cannot join the people picked so far is greyed out with the reason.
class _Suggestions extends StatelessWidget {
  final NewPrivateChatController controller;

  const _Suggestions(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchResponse = controller.searchResponse;
    final client = Matrix.of(context).client;
    final features = MatrixFeatures.forClient(client);
    final groupNetwork = controller.group.network;
    if (searchResponse == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return FutureBuilder(
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
                style: TextStyle(color: theme.colorScheme.error),
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
          return const Center(child: CircularProgressIndicator.adaptive());
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
                  L10n.of(
                    context,
                  ).noUsersFoundWithQuery(controller.controller.text),
                  style: TextStyle(color: theme.colorScheme.primary),
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
                onTap: () => controller.pickPerson(person),
                picked: controller.isRecipient(person),
                blockedReason: controller.groupBlockOf(person),
              );
            }
            final contact = result[i - people.length];
            final displayname =
                contact.displayName ??
                contact.userId.localpart ??
                contact.userId;
            // A Matrix user is on none of the networks a group starts on.
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
                    : L10n.of(
                        context,
                      ).notOnNetwork(groupNetwork.bridge.displayName),
              ),
              onTap: () => controller.pickProfile(contact),
            );
          },
        );
      },
    );
  }
}

/// One person in New Chat's or Add people's results: their chat, or
/// someone the user's networks or phone contacts know, with the networks
/// that reach them as grey icons at the end.
///
/// A person already picked shows a tick, and one who cannot join the
/// people picked so far is greyed out with [blockedReason] as the second
/// line.
class NewChatPersonTile extends StatelessWidget {
  final NewChatPerson person;
  final void Function() onTap;
  final bool picked;
  final String? blockedReason;

  const NewChatPersonTile({
    required this.person,
    required this.onTap,
    this.picked = false,
    this.blockedReason,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = person.phone;
    final typedEmail = person.typed && phone == null;
    final detail = person.typed
        ? typedEmail
              ? L10n.of(context).emailAddress
              : L10n.of(context).phoneNumber
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
              child: Icon(
                typedEmail
                    ? Icons.alternate_email_outlined
                    : Icons.dialpad_outlined,
              ),
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
