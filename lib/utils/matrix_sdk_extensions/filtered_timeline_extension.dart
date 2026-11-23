// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

// These sets are checked for every timeline event on every rebuild of the
// chat, so they are compile time constants instead of fresh literals.
const _hiddenRelationshipTypes = {
  RelationshipTypes.edit,
  RelationshipTypes.reaction,
};
const _hiddenEventTypes = {EventTypes.Reaction, EventTypes.Redaction};
const _messageEventTypes = {EventTypes.Message, EventTypes.Sticker};
const _uncollapsedEventTypes = {
  EventTypes.Message,
  EventTypes.Sticker,
  EventTypes.RoomCreate,
  EventTypes.RoomTombstone,
};

extension VisibleInGuiExtension on List<Event> {
  List<Event> filterByVisibleInGui({
    String? exceptionEventId,
    String? threadId,
  }) {
    // Each settings read goes through SharedPreferences and allocates, so
    // read them once for the whole list rather than once per event.
    final hideRedacted = AppSettings.hideRedactedEvents.value;
    final hideUnknown = AppSettings.hideUnknownEvents.value;
    return where((event) {
      final relationshipType = event.relationshipType;
      if (threadId != null && relationshipType != RelationshipTypes.reaction) {
        if ((relationshipType != RelationshipTypes.thread ||
                event.relationshipEventId != threadId) &&
            event.eventId != threadId) {
          return false;
        }
      } else if (relationshipType == RelationshipTypes.thread) {
        return false;
      }
      return event._isVisibleInGui(
            hideRedacted: hideRedacted,
            hideUnknown: hideUnknown,
          ) ||
          event.eventId == exceptionEventId;
    }).toList();
  }
}

extension IsStateExtension on Event {
  bool get isVisibleInGui => _isVisibleInGui(
    hideRedacted: AppSettings.hideRedactedEvents.value,
    hideUnknown: AppSettings.hideUnknownEvents.value,
  );

  bool _isVisibleInGui({
    required bool hideRedacted,
    required bool hideUnknown,
  }) =>
      // always filter out edit and reaction relationships
      !_hiddenRelationshipTypes.contains(relationshipType) &&
      // always filter out m.key.* and other known but unimportant events
      !isKnownHiddenStates &&
      // event types to hide: redaction and reaction events
      // if a reaction has been redacted we also want it to be hidden in the timeline
      !_hiddenEventTypes.contains(type) &&
      // if we enabled to hide all redacted events, don't show those
      (!hideRedacted || !redacted) &&
      // if we enabled to hide all unknown events, don't show those
      (!hideUnknown || isEventTypeKnown);

  bool get isState => !_messageEventTypes.contains(type);

  bool get isCollapsedState => !_uncollapsedEventTypes.contains(type);

  bool get isKnownHiddenStates =>
      type == PollEventContent.responseType ||
      type.startsWith('m.key.verification.');
}
