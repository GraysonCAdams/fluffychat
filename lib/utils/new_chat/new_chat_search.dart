// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The search behind New Chat and Add people: the user's chats that match
/// a query (a merged contact once), the people their bridges and phone
/// know, and starting a chat with someone on a network the user picked.
library;

import 'package:fluffychat/pages/chat_list/merged_contact_list.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/phone_contacts.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:matrix/matrix.dart';

/// A chat the user already has, as a search result.
class ExistingChat {
  /// The chat, or for a merged contact the room that represents it.
  final Room room;

  /// The merged contact [room] belongs to, or null.
  final MergedContact? contact;

  /// The networks (bridge spaces) the chat is on, without repeats.
  final List<Room> networks;

  const ExistingChat({
    required this.room,
    required this.contact,
    required this.networks,
  });

  /// The room a new message goes to: the merged contact's `send_via` room,
  /// else [room].
  Room get sendRoom => contact?.sendViaRoom ?? room;
}

/// [rooms] as the chat list shows them, every merged contact once, for the
/// rooms that pass [keep].
List<ExistingChat> existingChatsOf(
  Client client,
  List<Room> rooms,
  bool Function(Room room) keep,
) {
  final listed = MergedChatList.build(client, rooms, keep);
  final spaces = spacesByChild(client);
  return [
    for (final room in listed.rooms)
      ExistingChat(
        room: room,
        contact: listed.contacts[room.id],
        networks: NetworkBadges.distinctOf(
          listed.contacts[room.id]?.networks(spaces) ?? [spaces[room.id]],
        ),
      ),
  ];
}

/// The joined chats whose name, or whose other person's ID, contains
/// [searchTerm]: what a chat list search for it finds, newest first. A
/// merged contact is found by its own name too, and is one entry. [keep]
/// narrows the rooms further, such as to those the user can write in.
///
/// The server's user directory never returns bridged contacts, since
/// Synapse keeps every user in an appservice namespace out of it, so they
/// are only found here.
List<ExistingChat> searchExistingChats(
  Client client,
  String searchTerm,
  MatrixLocals locals, {
  bool Function(Room room)? keep,
}) {
  final needle = searchTerm.toLowerCase();
  final rooms = client.rooms
      .where((room) => room.membership == Membership.join && !room.isSpace)
      .where(keep ?? (_) => true)
      .toList();
  bool matches(Room room) =>
      room.chatDisplayname(locals).toLowerCase().contains(needle) ||
      (room.directChatMatrixID?.toLowerCase().contains(needle) ?? false);
  final store = MergedContactsStore.forClient(client);
  final named = <String>{
    for (final entry in store.contacts)
      if (MergedContact.resolve(client, entry)?.matchesSearch(needle, locals) ??
          false)
        ...entry.rooms,
  };
  return existingChatsOf(
    client,
    rooms,
    (room) => matches(room) || named.contains(room.id),
  );
}

/// The phone number known for [chat]'s other person: the merged contact's
/// stored number, else one a bridge reports for any of its rooms.
String? phoneOfChat(ExistingChat chat) {
  final rooms = chat.contact?.rooms ?? [chat.room];
  final stored = chat.contact?.entry.identifier;
  if (stored?['type'] == IdentifierType.phone.name) {
    final value = stored!['value'] as String?;
    if (value != null) return value;
  }
  final suggestions = MergeSuggestionService.forClient(chat.room.client);
  for (final room in rooms) {
    final phone = suggestions.phoneOf(room)?.value;
    if (phone != null) return phone;
  }
  return null;
}

/// What the people merge ([mergeNewChatPeople]) knows about the other
/// person of [chat].
ChatPersonInput<ExistingChat> chatPersonInput(
  ExistingChat chat,
  MatrixLocals locals,
) {
  final rooms = chat.contact?.rooms ?? [chat.room];
  return ChatPersonInput(
    chat: chat,
    name:
        chat.contact?.displayName(locals) ?? chat.room.chatDisplayname(locals),
    avatar: chat.contact?.avatar ?? chat.room.chatAvatar,
    phone: phoneOfChat(chat),
    userIds: [for (final room in rooms) ?room.directChatMatrixID],
    group: chat.contact == null && chat.room.directChatMatrixID == null,
    networks: [
      for (final network in chat.networks)
        NetworkRef(
          key: network.id,
          name: network.chatDisplayname(locals),
          icon: network.avatar,
        ),
    ],
  );
}

/// The people sources a search merges besides the chats: the bridges'
/// contact lists and the phone's address book. Each arrives on its own and
/// calls [onChanged].
class NewChatSources {
  final void Function() onChanged;

  NewChatSources({required this.onChanged});

  /// The user's bridges, once their `whoami` answered. Setting them marks
  /// them [bridgesLoaded].
  List<BridgeInfo> get bridges => _bridges;
  set bridges(List<BridgeInfo> value) {
    _bridges = value;
    bridgesLoaded = true;
  }

  List<BridgeInfo> _bridges = const [];

  /// Whether the bridges answered, or there are none to ask, so an empty
  /// [bridges] means the user has no network rather than that the answer
  /// is still coming. A failed answer leaves it false.
  bool bridgesLoaded = false;

  List<BridgeContactInput> bridgeContacts = const [];

  List<PhoneBookEntry> phoneBook = const [];

  /// Whether to offer reading the phone's contacts.
  bool offerPhoneContacts = false;

  bool _disposed = false;

  void _changed() {
    if (!_disposed) onChanged();
  }

  /// Starts reading the bridges and, when allowed, the phone's contacts.
  Future<void> load(Client client) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) {
      bridges = const [];
      _changed();
    } else {
      directory.bridges().then((value) {
        bridges = value;
        _changed();
      });
      directory.contacts().then((value) {
        bridgeContacts = value;
        _changed();
      });
    }
    if (await PhoneContacts.shouldOffer()) {
      offerPhoneContacts = true;
      _changed();
    } else {
      await _loadPhoneBook();
    }
  }

  Future<void> _loadPhoneBook() async {
    final entries = await PhoneContacts.load();
    if (entries.isEmpty) return;
    phoneBook = entries;
    _changed();
  }

  /// Asks for the contacts permission.
  Future<void> allowPhoneContacts() async {
    final granted = await PhoneContacts.request();
    offerPhoneContacts = false;
    _changed();
    if (granted) await _loadPhoneBook();
  }

  /// Stops offering the phone's contacts for good.
  Future<void> declinePhoneContacts() async {
    offerPhoneContacts = false;
    _changed();
    await PhoneContacts.decline();
  }

  /// One row per person for [query] across [chats] and these sources,
  /// with a row for a typed email too when [typedEmail] is set.
  List<NewChatPerson<ExistingChat>> people(
    String query,
    List<ChatPersonInput<ExistingChat>> chats, {
    bool typedEmail = false,
  }) => mergeNewChatPeople(
    query: query,
    chats: chats,
    bridgeContacts: bridgeContacts,
    phoneBook: phoneBook,
    defaultRegion: MergeSuggestionService.defaultPhoneRegion(),
    typedEmail: typedEmail,
  );

  void dispose() => _disposed = true;
}

/// How long [awaitBridgedRoom] waits for a new room to come down the sync.
const Duration newChatRoomTimeout = Duration(seconds: 30);

/// The network a direct chat starts on, with what that bridge resolved the
/// person to and the [identifier] it was asked about.
class StartChatChoice {
  final BridgeInfo bridge;
  final String identifier;
  final BridgeUser resolved;

  const StartChatChoice(this.bridge, this.identifier, this.resolved);
}

/// The room of [choice]: the existing direct chat the bridge reported, or
/// one `create_dm` starts. Waits until the room is on this client and joins
/// it if the bridge only invited the user.
Future<String> startBridgeChat(
  Client client,
  BridgeProvisioning api,
  StartChatChoice choice,
) async {
  final known = choice.resolved.dmRoomId;
  final roomId = known != null && client.getRoomById(known) != null
      ? known
      : await api.createDm(choice.bridge, choice.identifier);
  await awaitBridgedRoom(client, roomId);
  return roomId;
}

/// Waits until [roomId], which a bridge just made, is on this client, and
/// joins it if the bridge only invited the user.
Future<void> awaitBridgedRoom(Client client, String roomId) async {
  if (client.getRoomById(roomId) == null) {
    await client
        .waitForRoomInSync(roomId, join: true, invite: true)
        .timeout(newChatRoomTimeout);
  }
  final room = client.getRoomById(roomId);
  if (room != null && room.membership == Membership.invite) {
    await room.join();
  }
}

/// Adds [roomId] to the merged contact with [person]'s phone number, if
/// there is one, and returns that contact's ID.
Future<String?> addNewChatToMergedContact(
  Client client,
  NewChatPerson person,
  String roomId,
) async {
  final phone = person.phone;
  if (phone == null) return null;
  final store = MergedContactsStore.forClient(client);
  final suggestions = MergeSuggestionService.forClient(client);
  bool hasPhone(MergedContactEntry entry) {
    final stored = entry.identifier;
    if (stored?['type'] == IdentifierType.phone.name &&
        stored?['value'] == phone) {
      return true;
    }
    final contact = MergedContact.resolve(client, entry);
    return contact?.rooms.any(
          (room) => suggestions.phoneOf(room)?.value == phone,
        ) ??
        false;
  }

  final entry = store.contacts.where(hasPhone).firstOrNull;
  if (entry == null) return null;
  if (!entry.rooms.contains(roomId)) {
    try {
      await store.merge([roomId], intoContactId: entry.id);
    } catch (e, s) {
      Logs().w('Unable to add the new chat to its contact', e, s);
      return null;
    }
  }
  return entry.id;
}
