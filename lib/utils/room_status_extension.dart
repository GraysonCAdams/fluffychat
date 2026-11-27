// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../config/app_config.dart';

extension RoomStatusExtension on Room {
  String getLocalizedTypingText(BuildContext context) {
    var typingText = '';
    final typingUsers = this.typingUsers;
    typingUsers.removeWhere((User u) => u.id == client.userID);

    if (AppConfig.hideTypingUsernames) {
      typingText = L10n.of(context).isTyping;
      if (typingUsers.first.id != directChatMatrixID) {
        typingText = L10n.of(context).numUsersTyping(typingUsers.length);
      }
    } else if (typingUsers.length == 1) {
      typingText = L10n.of(context).isTyping;
      if (typingUsers.first.id != directChatMatrixID) {
        typingText = L10n.of(
          context,
        ).userIsTyping(typingUsers.first.calcDisplayname());
      }
    } else if (typingUsers.length == 2) {
      typingText = L10n.of(context).userAndUserAreTyping(
        typingUsers.first.calcDisplayname(),
        typingUsers[1].calcDisplayname(),
      );
    } else if (typingUsers.length > 2) {
      typingText = L10n.of(context).userAndOthersAreTyping(
        typingUsers.first.calcDisplayname(),
        (typingUsers.length - 1),
      );
    }
    return typingText;
  }

  /// The read receipts of the members who have read [event]: those whose
  /// receipt is on [event] or on a later event of this room in [timeline],
  /// one per member, without the user's own, the sender's or the bridge
  /// bot's.
  ///
  /// Only this room's events count, so in a merged contact's timeline a
  /// receipt on another network's room never marks [event] as read.
  List<Receipt> readReceiptsOf(Event event, Timeline timeline) {
    final receipts = <String, Receipt>{};
    for (final later in timeline.events) {
      if (later.room.id == id) {
        for (final receipt in later.receipts) {
          receipts.putIfAbsent(receipt.user.id, () => receipt);
        }
      }
      if (later.eventId == event.eventId) break;
    }
    receipts.remove(client.userID);
    receipts.remove(event.senderId);
    receipts.remove(RoomBridge.fromState(this)?.bot);
    return receipts.values.toList();
  }
}
