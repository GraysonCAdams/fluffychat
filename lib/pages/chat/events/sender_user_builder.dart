// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Builds with the sender of [event] as [Event.fetchSenderUser] would
/// resolve it, without starting a new lookup on every rebuild.
///
/// When the member is in memory and [Room.requestUser] would return it
/// unchanged, it is used directly and stays current as the member state
/// changes. Otherwise one lookup is started per room and sender and its
/// result is kept until the member shows up in memory.
///
/// [builder] receives null until a lookup has finished, just like the
/// snapshot data of a [FutureBuilder].
class SenderUserBuilder extends StatefulWidget {
  final Event? event;
  final Widget Function(BuildContext context, User? user) builder;

  const SenderUserBuilder({
    super.key,
    required this.event,
    required this.builder,
  });

  @override
  State<SenderUserBuilder> createState() => _SenderUserBuilderState();
}

class _SenderUserBuilderState extends State<SenderUserBuilder> {
  Future<User?>? _lookup;
  (Room, String)? _lookupFor;

  /// The user [Room.requestUser] would return without any await, or null
  /// when it would go to the database or the server.
  static User? _userFromMemory(Event event) {
    final room = event.room;
    // A partially loaded room reads members from the database first.
    if (room.partial) return null;
    final user = room
        .getState(EventTypes.RoomMember, event.senderId)
        ?.asUser(room);
    if (user == null) return null;
    // A member who left or was banned without a display name gets their
    // profile fetched from the server instead.
    if (const {Membership.ban, Membership.leave}.contains(user.membership) &&
        user.displayName == null) {
      return null;
    }
    return user;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final memoryUser = event == null ? null : _userFromMemory(event);
    if (event != null && memoryUser == null) {
      final lookupFor = (event.room, event.senderId);
      if (_lookup == null || _lookupFor != lookupFor) {
        _lookupFor = lookupFor;
        _lookup = event.fetchSenderUser();
      }
    }
    // Always a FutureBuilder, so switching between the two paths keeps the
    // state of everything built below.
    return FutureBuilder<User?>(
      future: memoryUser == null ? _lookup : null,
      builder: (context, snapshot) =>
          widget.builder(context, memoryUser ?? snapshot.data),
    );
  }
}

/// Builds with the event [event] replies to, as [Event.getReplyEvent] would
/// find it, without starting a new lookup on every rebuild.
///
/// An event loaded in [timeline] is used directly, so edits, redactions and
/// late decryption of the replied-to message show up on the next rebuild.
/// Otherwise one lookup is started per replied-to event id and timeline.
class ReplyEventBuilder extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Widget Function(BuildContext context, Event? replyEvent) builder;

  const ReplyEventBuilder({
    super.key,
    required this.event,
    required this.timeline,
    required this.builder,
  });

  @override
  State<ReplyEventBuilder> createState() => _ReplyEventBuilderState();
}

class _ReplyEventBuilderState extends State<ReplyEventBuilder> {
  Future<Event?>? _lookup;
  (Timeline, String)? _lookupFor;

  @override
  Widget build(BuildContext context) {
    // Same lookup key as Event.getReplyEvent.
    final replyEventId = widget.event.content
        .tryGetMap<String, Object?>('m.relates_to')
        ?.tryGetMap<String, Object?>('m.in_reply_to')
        ?.tryGet<String>('event_id');
    final timeline = widget.timeline;
    final loaded = replyEventId == null
        ? null
        : timeline.events.firstWhereOrNull(
            (event) => event.eventId == replyEventId,
          );
    if (loaded == null) {
      final lookupFor = (timeline, replyEventId ?? '');
      if (_lookup == null || _lookupFor != lookupFor) {
        _lookupFor = lookupFor;
        _lookup = widget.event.getReplyEvent(timeline);
      }
    }
    return FutureBuilder<Event?>(
      future: loaded == null ? _lookup : null,
      builder: (context, snapshot) =>
          widget.builder(context, loaded ?? snapshot.data),
    );
  }
}
