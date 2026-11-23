// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'send_router.dart';

extension RoutedEvent on Event {
  /// The room to send [action] on this message to. An action on a message
  /// (reaction, redaction, edit, reply) always goes to the room the message
  /// is in, from the account that sees it there, whichever network a merged
  /// contact sends new messages on (see [SendRouter]). Message widgets have
  /// no router at hand and call this instead of picking a room themselves.
  Room roomFor(SendAction action) {
    assert(action.actsOnEvent, '$action does not act on a message');
    return room;
  }
}
