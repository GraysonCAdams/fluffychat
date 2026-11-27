// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/sender_user_builder.dart';
import 'package:fluffychat/pages/chat_list/message_preview.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';

class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final bool ownMessage;

  /// When set, the quoted sender, text and bar use this colour. For a bubble
  /// whose background is not the theme's, such as a network's colour.
  final Color? foregroundColor;
  final Timeline? timeline;

  const ReplyContent(
    this.replyEvent, {
    this.ownMessage = false,
    this.foregroundColor,
    super.key,
    this.timeline,
  });

  static const BorderRadius borderRadius = BorderRadius.only(
    topRight: Radius.circular(AppConfig.borderRadius / 2),
    bottomRight: Radius.circular(AppConfig.borderRadius / 2),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final timeline = this.timeline;
    final displayEvent = timeline != null
        ? replyEvent.getDisplayEvent(timeline)
        : replyEvent;
    const fontSize = AppConfig.messageFontSize;
    final color =
        foregroundColor ??
        (theme.brightness == Brightness.dark
            ? theme.colorScheme.onTertiaryContainer
            : ownMessage
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.tertiary);

    final l10n = L10n.of(context);
    final hidden = effectPreviewOf(displayEvent, l10n);
    // Media reads as in the chat list ("Photo", "Video 0:12", a caption),
    // and a photo, video or sticker shows a small thumbnail of itself,
    // unless Invisible Ink hides it.
    final media = hidden != null || !_hasMedia(displayEvent)
        ? null
        : mediaPreviewOf(displayEvent, l10n, '');
    final showsThumbnail = media != null && _hasThumbnail(displayEvent);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          Container(
            width: 5,
            height: fontSize * 2 + 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          if (showsThumbnail) ...[
            _ReplyThumbnail(displayEvent),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisAlignment: .center,
              children: <Widget>[
                SenderUserBuilder(
                  event: displayEvent,
                  builder: (context, user) {
                    return Text(
                      '${user?.calcDisplayname() ?? displayEvent.senderFromMemoryOrFallback.calcDisplayname()}:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: fontSize,
                      ),
                    );
                  },
                ),
                Text(
                  hidden ??
                      media?.text ??
                      displayEvent
                          .calcLocalizedBody(
                            MatrixLocals(L10n.of(context)),
                            hideReply: true,
                            plaintextBody: true,
                          )
                          .trim()
                          .replaceAll('\n', ' '),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color:
                        foregroundColor ??
                        (theme.brightness == Brightness.dark
                            ? theme.colorScheme.onSurface
                            : ownMessage
                            ? theme.colorScheme.onTertiary
                            : theme.colorScheme.onSurface),
                    fontSize: fontSize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// Whether [event] is media the quote reads as the chat list does.
bool _hasMedia(Event event) =>
    !event.redacted &&
    (event.type == EventTypes.Sticker ||
        (event.type == EventTypes.Message &&
            {
              MessageTypes.Image,
              MessageTypes.Video,
              MessageTypes.Audio,
              MessageTypes.File,
              MessageTypes.Location,
            }.contains(event.messageType)));

/// Whether [event] is a photo, video or sticker, which a quote shows a
/// thumbnail of.
bool _hasThumbnail(Event event) =>
    event.type == EventTypes.Sticker ||
    {MessageTypes.Image, MessageTypes.Video}.contains(event.messageType);

/// A 40dp square of the quoted photo, sticker or video poster frame, the
/// video with a play badge. A video without a poster frame shows a plain
/// tile: the video itself is never fetched for it.
class _ReplyThumbnail extends StatelessWidget {
  final Event event;

  const _ReplyThumbnail(this.event);

  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = event.messageType == MessageTypes.Video;
    final placeholder = Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video && !event.hasThumbnail)
              placeholder
            else
              MxcImage(
                // The bubble of the quoted message caches its image under
                // the same key, so a quote of a message already on screen
                // fetches nothing.
                cacheKey: event.transactionId ?? event.eventId,
                cacheName: event.room.id,
                event: event,
                isThumbnail: true,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_) => placeholder,
              ),
            if (video)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(110),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
