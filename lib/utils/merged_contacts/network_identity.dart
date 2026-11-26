// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:matrix/matrix.dart';

/// The person in a bridged direct chat as one network knows them: the
/// network's name and their phone number, email address or name there.
class NetworkIdentity {
  final String network;
  final String identifier;

  const NetworkIdentity(this.network, this.identifier);

  /// One entry per network the other person of the direct chat [room] is
  /// reached on: every joined chat of its merged contact, or [room] alone.
  /// The identifier is the phone number a bridge reports, else the phone
  /// number or email address in the person's user ID, else the chat's name.
  static List<NetworkIdentity> ofChat(Room room, MatrixLocalizations locals) {
    final client = room.client;
    final contact = MergedContactsStore.forClient(
      client,
    ).contactForRoom(room.id);
    final rooms = [
      for (final id in contact?.rooms ?? [room.id])
        if (client.getRoomById(id) case final chat?)
          if (chat.membership == Membership.join && chat.isDirectChat) chat,
    ];
    if (rooms.isEmpty) rooms.add(room);
    final features = MatrixFeatures.forClient(client);
    final suggestions = MergeSuggestionService.forClient(client);
    final spaces = spacesByChild(client);
    return [
      for (final chat in rooms)
        NetworkIdentity(
          features.bridgeOf(chat)?.network ??
              networkName(chat, spaces[chat.id], locals),
          switch (suggestions.phoneOf(chat)) {
            final phone? => formatPhoneForDisplay(phone.value),
            null =>
              MatrixFeatures.handleOf(chat.directChatMatrixID ?? '') ??
                  chat.getLocalizedDisplayname(locals),
          },
        ),
    ];
  }
}
