// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/add_people/add_people.dart';
import 'package:fluffychat/pages/new_private_chat/new_group_widgets.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:material_ui/material_ui.dart';

class AddPeopleView extends StatelessWidget {
  final AddPeopleController controller;

  const AddPeopleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final room = controller.room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.oopsSomethingWentWrong)),
        body: Center(child: Text(l10n.youAreNoLongerParticipatingInThisChat)),
      );
    }
    final draft = controller.draft;
    final Widget body;
    if (controller.bridgeMissing) {
      final network =
          MatrixFeatures.forClient(room.client).bridgeOf(room)?.network ??
          networkName(
            room,
            spacesByChild(room.client)[room.id],
            MatrixLocals(l10n),
          );
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.addPeopleNetworkUnavailable(network),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (draft == null) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else {
      final people = controller.people;
      final query = controller.controller.text;
      body = Column(
        children: [
          GroupRecipientsBar(draft),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: controller.controller,
              autofocus: true,
              onChanged: controller.search,
              onSubmitted: controller.submit,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: draft.isEmpty
                    ? l10n.addPeopleSearchHint
                    : l10n.anyoneElse,
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
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_outlined),
                        onPressed: controller.clearSearch,
                      ),
              ),
            ),
          ),
          Expanded(
            child: query.trim().isNotEmpty && people.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.noUsersFoundWithQuery(query),
                      style: TextStyle(color: theme.colorScheme.primary),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (context, i) {
                      final person = people[i];
                      return NewChatPersonTile(
                        person: person,
                        onTap: () => controller.toggle(person),
                        picked: draft.contains(person),
                        blockedReason: controller.blockOf(person),
                      );
                    },
                  ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        titleSpacing: 0,
        title: Text(l10n.addPeople),
      ),
      floatingActionButton: draft == null || draft.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: controller.addPicked,
              icon: const Icon(Icons.person_add_outlined),
              label: Text(l10n.addCountPeople(draft.members.length)),
            ),
      body: MaxWidthBody(
        withScrolling: false,
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: body,
      ),
    );
  }
}
