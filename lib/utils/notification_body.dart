// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/notification_media.dart';
import 'package:fluffychat/utils/pending_media.dart';
import 'package:matrix/matrix.dart';

/// The text a notification shows for [event], on Android (the push helper)
/// and in the local notifications of the desktop and web apps.
///
/// An effect that hides the message keeps it out of the notification. A
/// bridge's placeholder for an attachment ([PendingMedia]) reads as the
/// photo or video it stands for, and a picture that comes as an edit of a
/// placeholder reads as the picture, not as the edit's own fallback text.
String notificationBodyOf(Event event, L10n l10n) =>
    effectPreviewOf(event, l10n) ??
    PendingMedia.of(effectiveEvent(event))?.previewText(l10n) ??
    (hasNotificationMedia(event) ? effectiveEvent(event) : event)
        .calcLocalizedBody(
          MatrixLocals(l10n),
          plaintextBody: true,
          hideReply: true,
          hideEdit: true,
          removeMarkdown: true,
        );

/// Whether a notification shows [event]'s sender as a bot: a notice (an
/// `m.notice`), the message type bots send. A bridge's placeholder for an
/// attachment ([PendingMedia]) is a notice too, but its sender is a person
/// whose photo or video is on its way.
bool notificationSenderIsBot(Event event) =>
    event.messageType == MessageTypes.Notice &&
    PendingMedia.of(effectiveEvent(event)) == null;
