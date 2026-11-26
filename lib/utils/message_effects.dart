// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// iMessage expressive effects as they travel on Matrix events.
///
/// Everything that knows how the bridge carries an effect lives in this
/// file: the content key, the id strings and the test for a room that can
/// carry one. The rest of the app works with [MessageEffect] only.
library;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart';

/// The key of a message's content that holds the effect id, the one
/// Beeper's iMessage bridge uses. The value is Apple's id, verbatim. The
/// bridge reads it on messages sent from here and writes it on messages
/// that arrive; an id it does not know it drops, in both directions.
const messageEffectKey = 'com.beeper.imessage.effect';

/// Whether an effect changes how one bubble arrives or plays over the whole
/// conversation.
enum MessageEffectKind { bubble, screen }

/// Every effect iMessage can send, with the id Apple puts on the wire.
enum MessageEffect {
  slam(MessageEffectKind.bubble, 'com.apple.MobileSMS.expressivesend.impact'),
  loud(MessageEffectKind.bubble, 'com.apple.MobileSMS.expressivesend.loud'),
  gentle(MessageEffectKind.bubble, 'com.apple.MobileSMS.expressivesend.gentle'),
  invisibleInk(
    MessageEffectKind.bubble,
    'com.apple.MobileSMS.expressivesend.invisibleink',
  ),
  echo(MessageEffectKind.screen, 'com.apple.messages.effect.CKEchoEffect'),
  spotlight(
    MessageEffectKind.screen,
    'com.apple.messages.effect.CKSpotlightEffect',
  ),
  balloons(
    MessageEffectKind.screen,
    'com.apple.messages.effect.CKHappyBirthdayEffect',
  ),
  confetti(
    MessageEffectKind.screen,
    'com.apple.messages.effect.CKConfettiEffect',
  ),
  love(MessageEffectKind.screen, 'com.apple.messages.effect.CKHeartEffect'),
  lasers(MessageEffectKind.screen, 'com.apple.messages.effect.CKLasersEffect'),
  fireworks(
    MessageEffectKind.screen,
    'com.apple.messages.effect.CKFireworksEffect',
  ),
  celebration(
    MessageEffectKind.screen,
    'com.apple.messages.effect.CKSparklesEffect',
  ),
  shootingStar(
    MessageEffectKind.screen,
    'com.apple.messages.effect.CKShootingStarEffect',
  );

  final MessageEffectKind kind;

  /// The id in the event content, Apple's own.
  final String id;

  const MessageEffect(this.kind, this.id);

  bool get isBubble => kind == MessageEffectKind.bubble;
  bool get isScreen => kind == MessageEffectKind.screen;

  /// The effect with [id], or null for an id this app does not know.
  static MessageEffect? fromId(Object? id) {
    if (id is! String) return null;
    for (final effect in values) {
      if (effect.id == id) return effect;
    }
    return null;
  }

  static List<MessageEffect> ofKind(MessageEffectKind kind) => [
    for (final effect in values)
      if (effect.kind == kind) effect,
  ];

  String localizedName(L10n l10n) => switch (this) {
    slam => l10n.effectSlam,
    loud => l10n.effectLoud,
    gentle => l10n.effectGentle,
    invisibleInk => l10n.effectInvisibleInk,
    echo => l10n.effectEcho,
    spotlight => l10n.effectSpotlight,
    balloons => l10n.effectBalloons,
    confetti => l10n.effectConfetti,
    love => l10n.effectLove,
    lasers => l10n.effectLasers,
    fireworks => l10n.effectFireworks,
    celebration => l10n.effectCelebration,
    shootingStar => l10n.effectShootingStar,
  };
}

/// The effect [event] was sent with, or null.
MessageEffect? effectOf(Event event) {
  if (event.type != EventTypes.Message || event.redacted) return null;
  return MessageEffect.fromId(event.content[messageEffectKey]);
}

/// [content] with [effect] on it, for sending.
Map<String, Object?> withEffect(
  Map<String, Object?> content,
  MessageEffect effect,
) => {...content, messageEffectKey: effect.id};

/// Whether [room] is a chat on the iMessage bridge, the only place effects
/// can be sent. The bridge carries an effect on a text message only, and
/// drops it from one that goes out as SMS. A direct chat tells by its ghost's user id; a group by the
/// network its bridge state names.
bool canSendMessageEffects(Room room) {
  if (NetworkColors.bridgeIdOf(room) == 'imessage') return true;
  final network = MatrixFeatures.forClient(room.client).bridgeOf(room)?.network;
  return network?.toLowerCase() == 'imessage';
}

extension SendWithEffect on Room {
  /// The content of a text message saying [text] with [effect], formatted
  /// from Markdown as [Room.sendTextEvent] formats it.
  Map<String, Object?> textContentWithEffect(
    String text,
    MessageEffect effect,
  ) {
    final content = <String, Object?>{
      'msgtype': MessageTypes.Text,
      'body': text,
    };
    final html = markdown(
      text,
      getEmotePacks: () => getImagePacksFlat(ImagePackUsage.emoticon),
      getMention: getMention,
      convertLinebreaks: client.convertLinebreaksInFormatting,
      enableLatex: client.enableLatexMarkdown,
    );
    // Markdown that only escaped the text added nothing worth sending.
    final plain = html
        .replaceAll(RegExp(r'<br />\n?'), '\n')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    if (plain != text) {
      content['format'] = 'org.matrix.custom.html';
      content['formatted_body'] = html;
    }
    return withEffect(content, effect);
  }

  /// Sends [text] as a message with [effect]. Commands are not run: a
  /// message sent with an effect is always a message.
  Future<String?> sendTextEventWithEffect(
    String text,
    MessageEffect effect, {
    Event? inReplyTo,
    String? threadRootEventId,
    String? threadLastEventId,
  }) => sendEvent(
    Map<String, dynamic>.of(textContentWithEffect(text, effect)),
    inReplyTo: inReplyTo,
    threadRootEventId: threadRootEventId,
    threadLastEventId: threadLastEventId,
  );
}

/// The text that stands in for [event]'s body wherever a message is shown
/// outside its bubble (chat list, notification, reply quote), or null when
/// the body can be shown. Invisible ink keeps its text out of all of those.
String? effectPreviewOf(Event event, L10n l10n) =>
    effectOf(event) == MessageEffect.invisibleInk
    ? l10n.sentWithEffect(l10n.effectInvisibleInk)
    : null;

/// [html], the formatted body of [event], as its bubble shows it. The
/// bridge wraps the text of an invisible ink message in a Matrix spoiler
/// for clients that do not know the effect; here the ink already covers
/// the bubble, so the spoiler is taken off.
String effectBodyHtml(Event event, String html) =>
    effectOf(event) == MessageEffect.invisibleInk
    ? html.replaceAll(_spoilerAttribute, '')
    : html;

final _spoilerAttribute = RegExp(r'''\sdata-mx-spoiler(=("[^"]*"|'[^']*'))?''');

/// Tells message bubbles to play their effect again, as the message menu
/// and the Replay link under an effect message ask. The value is the event id and a counter, so asking twice for the
/// same message notifies twice.
final messageEffectReplays = ValueNotifier<(String eventId, int count)?>(null);

void replayMessageEffect(Event event) {
  messageEffectReplays.value = (
    event.eventId,
    (messageEffectReplays.value?.$2 ?? 0) + 1,
  );
}
