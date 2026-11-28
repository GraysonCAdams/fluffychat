// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:matrix/matrix.dart';

/// How system events (membership and room state) read in the timeline:
/// the text of one line, which events are housekeeping, and which runs of
/// consecutive system events fold into one group.
abstract final class StateEventSummary {
  /// Symbols the translations put in front of some system lines ("👍 ",
  /// "📩 "). Timeline system lines are plain text.
  static final _leadingSymbols = RegExp(r'^[^\p{L}\p{N}]+\s+', unicode: true);

  /// Room state a bridge bot writes while it sets up or keeps a portal.
  static const _bridgeHousekeepingTypes = {
    EventTypes.RoomName,
    EventTypes.RoomAvatar,
    EventTypes.RoomTopic,
    EventTypes.RoomPowerLevels,
    EventTypes.RoomJoinRules,
    EventTypes.HistoryVisibility,
    EventTypes.GuestAccess,
    EventTypes.Encryption,
    EventTypes.RoomCanonicalAlias,
  };

  /// The line [event] shows in the timeline: its localized text without
  /// leading symbols, with the room's bridge bot named by its network
  /// ("Google Messages invited Gloria") when the room's `m.bridge` state
  /// names both.
  static String line(Event event, L10n l10n) {
    var text = event
        .calcLocalizedBody(MatrixLocals(l10n))
        .replaceFirst(_leadingSymbols, '');
    final bridge = RoomBridge.fromState(event.room);
    final bot = bridge?.bot;
    final network = bridge?.network;
    if (bot != null && network != null) {
      // The SDK has already put the bot's display name into the text, so
      // the name is swapped as a whole string.
      final botName = event.room
          .unsafeGetUserFromMemoryOrFallback(bot)
          .calcDisplayname();
      if (botName.isNotEmpty && botName != network) {
        text = text.replaceAll(botName, network);
      }
    }
    return text;
  }

  /// Whether [event] is housekeeping no one needs to see first: the user's
  /// own join or accepted invitation, the bridge bot joining, and anything
  /// the bridge bot does to the room except removing someone (it invites
  /// the remote person, names the portal, sets its photo and topic).
  static bool isHousekeeping(Event event) {
    final own = event.room.client.userID;
    final bot = RoomBridge.fromState(event.room)?.bot;
    if (event.type == EventTypes.RoomMember) {
      final membership = event.content.tryGet<String>('membership');
      if (membership == 'join' &&
          (event.stateKey == own || event.stateKey == bot)) {
        return true;
      }
      return bot != null && event.senderId == bot && membership == 'invite';
    }
    return bot != null &&
        event.senderId == bot &&
        _bridgeHousekeepingTypes.contains(event.type);
  }

  /// Index in [run] (oldest first) of the event a folded group leads
  /// with: the newest one that is not housekeeping, or the newest of all
  /// when every event is.
  static int headlineIndex(List<Event> run) {
    for (var i = run.length - 1; i >= 0; i--) {
      if (!isHousekeeping(run[i])) return i;
    }
    return run.length - 1;
  }

  /// The run of consecutive foldable system events that [events] (newest
  /// first, as the timeline lists them) holds at [index], oldest first, or
  /// null when the event there is not part of a run of two or more.
  static List<Event>? runAt(List<Event> events, int index) {
    if (!events[index].isCollapsedState) return null;
    var newest = index;
    while (newest > 0 && events[newest - 1].isCollapsedState) {
      newest--;
    }
    var oldest = index;
    while (oldest + 1 < events.length && events[oldest + 1].isCollapsedState) {
      oldest++;
    }
    if (oldest == newest) return null;
    return events.sublist(newest, oldest + 1).reversed.toList();
  }
}
