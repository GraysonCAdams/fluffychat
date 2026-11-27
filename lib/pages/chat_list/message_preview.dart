// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:html/parser.dart' as html;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What the chat list shows for a message: an optional icon for the kind of
/// message, then [text]. A photo is the photo icon and "Photo", a link on
/// its own the link icon and the address, a text message just its text.
@immutable
class MessagePreview {
  final IconData? icon;
  final String text;

  const MessagePreview(this.text, {this.icon});

  @override
  bool operator ==(Object other) =>
      other is MessagePreview && other.icon == icon && other.text == text;

  @override
  int get hashCode => Object.hash(icon, text);

  @override
  String toString() => icon == null ? text : '[${icon!.codePoint}] $text';
}

/// The size of the icon in front of a preview, and the space after it.
const double messagePreviewIconSize = 18;
const double messagePreviewIconGap = 4;

/// A duration as a clock, `0:48` or `1:02:05`.
String previewClock(Duration duration) {
  final minutes = duration.inMinutes % 60;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

final _lonelyUrl = RegExp(r'^https?://\S+$', caseSensitive: false);

/// The preview of [event] when it is media, or a message that is only a
/// link in [body], its text as the chat list would show it otherwise.
/// Null for any other message, which shows as [body].
MessagePreview? mediaPreviewOf(Event event, L10n l10n, String body) {
  if (event.redacted) return null;
  if (event.type == EventTypes.Sticker) {
    return MessagePreview(
      l10n.previewSticker,
      icon: Icons.sticky_note_2_outlined,
    );
  }
  if (event.type != EventTypes.Message) return null;
  final info = event.content.tryGetMap<String, Object?>('info');
  final durationMs = info?.tryGet<int>('duration', TryGet.silent);
  final duration = durationMs == null
      ? null
      : Duration(milliseconds: durationMs);
  String withDuration(String type) => duration == null
      ? type
      : l10n.previewWithDuration(type, previewClock(duration));
  final caption = event.fileDescription?.trim().replaceAll('\n', ' ');
  final fileName =
      event.content.tryGet<String>('filename', TryGet.silent) ??
      event.content.tryGet<String>('body', TryGet.silent) ??
      '';

  switch (event.messageType) {
    case MessageTypes.Image:
      final gif =
          info?.tryGet<String>('mimetype', TryGet.silent) == 'image/gif';
      return MessagePreview(
        caption ?? (gif ? l10n.previewGif : l10n.photo),
        icon: gif ? Icons.gif_box_outlined : Icons.photo_outlined,
      );
    case MessageTypes.Video:
      return MessagePreview(
        caption ?? withDuration(l10n.video),
        icon: Icons.videocam_outlined,
      );
    case MessageTypes.Audio:
      if (event.content.tryGetMap('org.matrix.msc3245.voice') != null) {
        return MessagePreview(
          withDuration(l10n.voiceMessage),
          icon: Icons.mic_none_outlined,
        );
      }
      return MessagePreview(
        caption ?? fileName,
        icon: Icons.headphones_outlined,
      );
    case MessageTypes.File:
      return MessagePreview(caption ?? fileName, icon: Icons.attach_file);
    case MessageTypes.Location:
      return MessagePreview(l10n.location, icon: Icons.location_on_outlined);
    case MessageTypes.Text:
      final trimmed = body.trim();
      if (_lonelyUrl.hasMatch(trimmed)) {
        return MessagePreview(
          trimmed
              .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
              .replaceFirst(RegExp(r'/$'), ''),
          icon: Icons.link,
        );
      }
  }
  return null;
}

/// [body], which the Matrix SDK made from [event]'s HTML, without the 🔗 it
/// puts straight in front of the text of every link. A 🔗 the sender typed
/// stays.
String withoutLinkMarkers(Event event, String body) {
  if (!body.contains('🔗')) return body;
  final sources = [
    event.formattedText,
    event.content
            .tryGetMap<String, Object?>('m.new_content')
            ?.tryGet<String>('formatted_body', TryGet.silent) ??
        '',
  ];
  for (final source in sources) {
    if (source.isEmpty) continue;
    for (final anchor in html.parseFragment(source).querySelectorAll('a')) {
      final text = anchor.text;
      body = body.replaceFirst('🔗$text', text);
    }
  }
  return body;
}

/// [preview] after "[sender]: ", as one line of rich text, with its icon in
/// [color] (the text's color when null) where it has one.
InlineSpan messagePreviewSpan(
  L10n l10n,
  MessagePreview preview, {
  String? sender,
  Color? color,
}) {
  final text = preview.text.trim().replaceAll('\n', ' ');
  final icon = preview.icon;
  // Split the localized "Sender: message" around the message, so the icon
  // sits right before it whatever the language puts first.
  const marker = '\u0000';
  final parts = sender == null
      ? const ['', '']
      : l10n.senderMessage(sender, marker).split(marker);
  return TextSpan(
    children: [
      if (parts.first.isNotEmpty) TextSpan(text: parts.first),
      if (icon != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              end: messagePreviewIconGap,
            ),
            child: Builder(
              builder: (context) => Icon(
                icon,
                size: messagePreviewIconSize,
                color: color ?? DefaultTextStyle.of(context).style.color,
              ),
            ),
          ),
        ),
      TextSpan(text: text),
      if (parts.length > 1 && parts.last.isNotEmpty) TextSpan(text: parts.last),
    ],
  );
}
