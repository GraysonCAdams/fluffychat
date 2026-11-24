// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/android_conversation_notifications.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:matrix/matrix.dart';

/// How many recent chats are offered in the Android share sheet. The system
/// allows about 15 dynamic shortcuts per activity, and message notifications
/// publish theirs too, so this leaves room for them.
const maxShareTargets = 8;

/// One chat offered in the Android share sheet.
class ShareTarget {
  /// The shortcut ID, see [conversationId]: a room ID, or `contact_<id>`
  /// for a merged contact, which is offered once for all its rooms.
  final String shortcutId;

  /// The most recently active room of the chat.
  final String roomId;

  const ShareTarget(this.shortcutId, this.roomId);

  @override
  bool operator ==(Object other) =>
      other is ShareTarget &&
      other.shortcutId == shortcutId &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(shortcutId, roomId);

  @override
  String toString() => 'ShareTarget($shortcutId, $roomId)';
}

/// The chats to offer in the share sheet, from [roomIds] ordered most recent
/// first: one entry per room, except that the rooms of a merged contact
/// ([contactIdOf]) make one entry, at the place of the most recent of them.
List<ShareTarget> selectShareTargets(
  Iterable<String> roomIds,
  String? Function(String roomId) contactIdOf, {
  int max = maxShareTargets,
}) {
  final targets = <ShareTarget>[];
  final seen = <String>{};
  for (final roomId in roomIds) {
    if (targets.length >= max) break;
    final shortcutId = conversationId(roomId, contactIdOf(roomId));
    if (seen.add(shortcutId)) targets.add(ShareTarget(shortcutId, roomId));
  }
  return targets;
}

/// The route that opens the chat a Direct Share picked by [shortcutId], or
/// null when that chat is gone. A merged contact opens its merged screen,
/// and so does a room ID whose room has been merged into a contact since its
/// shortcut was published. Any other room opens on its own.
String? shareTargetRoute(
  String shortcutId, {
  required bool Function(String roomId) hasRoom,
  required bool Function(String contactId) hasContact,
  required String? Function(String roomId) contactIdOf,
}) {
  final contactId =
      contactIdOfConversation(shortcutId) ?? contactIdOf(shortcutId);
  if (contactId != null) {
    return hasContact(contactId) ? '/rooms/contact/$contactId' : null;
  }
  return hasRoom(shortcutId) ? '/rooms/$shortcutId' : null;
}

/// Keeps the Android share sheet's FluffyChat suggestions on the client's
/// most recent chats. Conversation shortcuts are otherwise only published
/// when a message notification is shown, so without this the share sheet
/// offers nothing until notifications arrive, and only the chats they came
/// from.
///
/// Republishes a few seconds after a sync, and only when the chats, their
/// names, avatars or order changed.
class AndroidShareTargets {
  final Client client;
  final MatrixLocalizations Function() i18n;

  StreamSubscription? _syncSub;
  Timer? _debounce;
  String? _published;

  AndroidShareTargets._(this.client, this.i18n);

  static final Map<Client, AndroidShareTargets> _instances = {};

  /// Starts keeping the share targets of [client] up to date. Does nothing
  /// off Android or when already started.
  static void start(Client client, MatrixLocalizations Function() i18n) {
    if (!PlatformInfos.isAndroid || _instances.containsKey(client)) return;
    final instance = _instances[client] = AndroidShareTargets._(client, i18n);
    instance._syncSub = client.onSync.stream.listen(
      (_) => instance._schedule(),
    );
    instance._schedule();
  }

  /// Stops [client]'s updates, for example on logout.
  static void stop(Client client) {
    _instances.remove(client)?._dispose();
  }

  void _dispose() {
    _syncSub?.cancel();
    _debounce?.cancel();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () => _publish().ignore());
  }

  Future<void> _publish() async {
    if (client.prevBatch == null) return;
    final store = MergedContactsStore.forClient(client);
    final i18n = this.i18n();
    final rooms =
        client.rooms
            .where(
              (room) => room.membership == Membership.join && !room.isSpace,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
          );
    final targets = selectShareTargets(
      rooms.map((room) => room.id),
      (roomId) => store.contactForRoom(roomId)?.id,
    );

    final shortcuts = <({String id, String name, Room room})>[];
    for (final target in targets) {
      final contact = store.contactById(
        contactIdOfConversation(target.shortcutId) ?? '',
      );
      // A merged contact shows as its default network's room.
      final room =
          client.getRoomById(contact?.sendViaIn(contact.rooms) ?? '') ??
          client.getRoomById(target.roomId);
      if (room == null) continue;
      final name =
          notificationConversationName(client, room.id, i18n) ??
          room.getLocalizedDisplayname(i18n);
      shortcuts.add((id: target.shortcutId, name: name, room: room));
    }

    final signature = shortcuts
        .map((s) => '${s.id}\u0000${s.name}\u0000${s.room.avatar}')
        .join('\u0001');
    if (signature == _published) return;
    _published = signature;

    // Published least recent first: the system puts each pushed shortcut
    // on top of the others.
    for (final shortcut in shortcuts.reversed) {
      try {
        await AndroidConversationNotifications.publishShortcut(
          id: shortcut.id,
          name: shortcut.name,
          roomUrl: AppConfig.inviteLinkPrefix + shortcut.room.id,
          avatar: await client.tryDownloadNotificationAvatar(
            shortcut.room.avatar,
          ),
          isImportant: shortcut.room.isFavourite,
        );
      } catch (e, s) {
        Logs().w('Unable to publish share target ${shortcut.id}', e, s);
        _published = null;
      }
    }
  }
}
