// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// What is being shared into Seam, from the Android share sheet or from
/// inside the app (forwarding messages, the image viewer), on its way to
/// the composer where it waits for the user to press send.
library;

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:matrix/matrix.dart';

abstract class ShareItem {}

/// Shared text or a link; it goes into the composer's text field.
class TextShareItem extends ShareItem {
  final String value;
  TextShareItem(this.value);
}

/// A forwarded message's content, sent as it is.
class ContentShareItem extends ShareItem {
  final Map<String, Object?> value;
  ContentShareItem(this.value);
}

/// A shared file; it is staged as a composer attachment.
class FileShareItem extends ShareItem {
  final XFile value;
  FileShareItem(this.value);
}

/// A share handed to the compose screen or a chat page through the route's
/// `extra`.
class SharedDraft {
  final List<ShareItem> items;

  /// Whether the share came in through an Android share intent. Then
  /// sending, or leaving without sending, returns to the app that shared.
  final bool fromShareIntent;

  const SharedDraft(this.items, {this.fromShareIntent = false});

  List<XFile> get files => [
    for (final item in items)
      if (item is FileShareItem) item.value,
  ];

  List<Map<String, Object?>> get contents => [
    for (final item in items)
      if (item is ContentShareItem) item.value,
  ];

  /// The shared text, one item per line.
  String get text =>
      items.whereType<TextShareItem>().map((item) => item.value).join('\n');
}

/// What the compose screen sends to a chat, in this order: [files] (one
/// event each), then the forwarded [contents], then [text] as its own
/// message.
class SharePayload {
  final List<XFile> files;
  final List<Map<String, Object?>> contents;
  final String text;

  const SharePayload({
    this.files = const [],
    this.contents = const [],
    this.text = '',
  });

  bool get isEmpty => files.isEmpty && contents.isEmpty && text.trim().isEmpty;
}

/// The toast shown as Seam goes back to the app that shared: the chat's
/// [name] and the network [room] is on, when it is a bridged one.
String shareSentToast(L10n l10n, Room room, String name) {
  final space = spacesByChild(room.client)[room.id];
  return space == null
      ? l10n.sentToName(name)
      : l10n.sentToOnNetwork(name, space.chatDisplayname(MatrixLocals(l10n)));
}
