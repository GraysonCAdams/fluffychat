// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/add_people/add_people_view.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Adds people to a bridged group on the group's own network, found the
/// way New Chat finds them: the user's chats, the bridges' contact lists,
/// the phone's contacts, or a typed phone number or email. Each person is
/// resolved through the group's bridge and their ghost is invited.
class AddPeople extends StatefulWidget {
  final String roomId;
  final NewChatDelivery delivery;

  const AddPeople({
    super.key,
    required this.roomId,
    this.delivery = const NewChatDelivery(),
  });

  @override
  AddPeopleController createState() => AddPeopleController();
}

class AddPeopleController extends State<AddPeople> {
  final TextEditingController controller = TextEditingController();

  /// The bridges' contact lists and the phone's address book.
  late final NewChatSources sources = NewChatSources(onChanged: _rebuild);

  /// The group's bridge, once the user's bridges answered.
  BridgeInfo? bridge;

  /// Whether the user's bridges answered without the group's.
  bool bridgeMissing = false;

  /// The people picked, on [bridge]; null until [bridge] is known.
  GroupDraft? draft;

  /// The results for the search in [controller].
  List<NewChatPerson<ExistingChat>> people = const [];

  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = Matrix.of(context).client;
    final room = this.room;
    if (room == null) return;
    widget.delivery.loadSources(client, sources);
    final BridgeInfo? bridge;
    try {
      bridge = await widget.delivery.bridgeOfRoom(client, room);
    } catch (e, s) {
      Logs().w('Unable to find the bridge of ${room.id}', e, s);
      if (mounted) setState(() => bridgeMissing = true);
      return;
    }
    if (!mounted) return;
    if (bridge == null) {
      setState(() => bridgeMissing = true);
      return;
    }
    final draft = GroupDraft.forRoom(bridge, memberIds: await _memberIds(room))
      ..addListener(_rebuild);
    if (!mounted) return draft.dispose();
    setState(() {
      this.bridge = bridge;
      this.draft = draft;
    });
  }

  /// The joined and invited members of [room], from the server when it
  /// answers.
  Future<Set<String>> _memberIds(Room room) async {
    const memberships = [Membership.join, Membership.invite];
    List<User> users;
    try {
      users = await room.requestParticipants(memberships);
    } catch (e, s) {
      Logs().w('Unable to load the members of ${room.id}', e, s);
      users = room.getParticipants(memberships);
    }
    return {for (final user in users) user.id};
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() => people = _search(controller.text));
  }

  List<NewChatPerson<ExistingChat>> _search(String query) {
    if (query.trim().isEmpty) return const [];
    final client = Matrix.of(context).client;
    final locals = MatrixLocals(L10n.of(context));
    final chats = AppSettings.suggestContactsFromChats.value
        ? searchExistingChats(
            client,
            query,
            locals,
            keep: (room) => room.id != widget.roomId,
          )
        : const <ExistingChat>[];
    return sources.people(query, [
      for (final chat in chats) chatPersonInput(chat, locals),
    ], typedEmail: true);
  }

  void search(String text) => setState(() => people = _search(text));

  void clearSearch() {
    controller.clear();
    search('');
  }

  /// Adds [person] to the picked people, or removes them, and clears the
  /// search after an add so the next person can be typed.
  Future<void> toggle(NewChatPerson<ExistingChat> person) async {
    final draft = this.draft;
    if (draft == null) return;
    final added = await toggleGroupMember(
      context,
      Matrix.of(context).client,
      widget.delivery,
      draft,
      person,
    );
    if (!added || !mounted) return;
    clearSearch();
  }

  /// Enter in the search field adds a typed phone number or email.
  void submit(String text) {
    final typed = _search(text).where((person) => person.typed).firstOrNull;
    if (typed != null) toggle(typed);
  }

  /// Why [person] cannot be picked, or null.
  String? blockOf(NewChatPerson person) {
    final block = draft?.blockOf(person);
    return block == null
        ? null
        : groupBlockReason(L10n.of(context), block, bridge);
  }

  /// The add button: invites each picked person's ghost, resolving the
  /// ones whose ghost is not known yet. Everyone added leaves the picked
  /// people; when anyone could not be added, a dialog names them with the
  /// reason and the page stays, else the chat opens. A refusal the bridge
  /// makes after the invite went through, as the iMessage bridge does in a
  /// carrier (SMS) group, arrives as a notice in the chat and is not seen
  /// here.
  Future<void> addPicked() async {
    final draft = this.draft;
    final bridge = this.bridge;
    final room = this.room;
    if (draft == null || bridge == null || room == null || draft.isEmpty) {
      return;
    }
    final client = Matrix.of(context).client;
    final members = draft.members;
    final added = <GroupMember, String>{};
    final failed = <GroupMember, Object?>{};
    await showFutureLoadingDialog<void>(
      context: context,
      future: () async {
        for (final member in members) {
          try {
            final ghost =
                member.user.mxid ??
                (await widget.delivery.resolveOnNetwork(
                  client,
                  bridge,
                  member.user.id,
                ))?.mxid;
            if (ghost == null) {
              failed[member] = null;
              continue;
            }
            await widget.delivery.invite(room, ghost);
            added[member] = ghost;
          } catch (e, s) {
            Logs().w('Unable to add ${member.user.id} to ${room.id}', e, s);
            failed[member] = e;
          }
        }
      },
    );
    if (!mounted) return;
    for (final MapEntry(key: member, value: ghost) in added.entries) {
      draft.remove(member.key);
      draft.markMember(ghost);
    }
    final l10n = L10n.of(context);
    if (failed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.countPeopleAdded(added.length))),
      );
      context.go('/rooms/${room.id}');
      return;
    }
    // Someone the network does not reach leaves the picked people; someone
    // whose invite failed stays picked, to try again.
    for (final MapEntry(key: member, value: error) in failed.entries) {
      if (error != null) continue;
      draft.remove(member.key);
      draft.markUnreachable(member.person);
    }
    await showOkAlertDialog(
      context: context,
      title: l10n.peopleNotAdded,
      message: [
        for (final MapEntry(key: member, value: error) in failed.entries)
          '${member.person.name}: ${error == null ? l10n.notOnNetwork(bridge.displayName) : error.toLocalizedString(context)}',
      ].join('\n'),
    );
  }

  @override
  void dispose() {
    draft?.dispose();
    sources.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AddPeopleView(this);
}
