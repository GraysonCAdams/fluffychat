// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_bubble.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_host.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:material_ui/material_ui.dart';

IconData _iconOf(MessageEffect effect) => switch (effect) {
  MessageEffect.slam => Icons.vertical_align_bottom_outlined,
  MessageEffect.loud => Icons.campaign_outlined,
  MessageEffect.gentle => Icons.spa_outlined,
  MessageEffect.invisibleInk => Icons.blur_on_outlined,
  MessageEffect.echo => Icons.copy_all_outlined,
  MessageEffect.spotlight => Icons.highlight_outlined,
  MessageEffect.balloons => Icons.cake_outlined,
  MessageEffect.confetti => Icons.celebration_outlined,
  MessageEffect.love => Icons.favorite_outline,
  MessageEffect.lasers => Icons.flashlight_on_outlined,
  MessageEffect.fireworks => Icons.flare_outlined,
  MessageEffect.celebration => Icons.auto_awesome_outlined,
  MessageEffect.shootingStar => Icons.star_outline,
};

/// Opens the sheet that sends [text] with an effect and returns the effect
/// picked, or null when the sheet was dismissed.
///
/// [onSchedule], when given, puts a schedule button in the sheet's header,
/// which closes the sheet before it is called.
Future<MessageEffect?> showMessageEffectPicker(
  BuildContext context, {
  required String text,
  required Color bubbleColor,
  required Color onBubbleColor,
  VoidCallback? onSchedule,
}) => showModalBottomSheet<MessageEffect>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 1,
    child: MessageEffectPicker(
      text: text,
      bubbleColor: bubbleColor,
      onBubbleColor: onBubbleColor,
      onSchedule: onSchedule,
    ),
  ),
);

/// What a long press on the send button does: in a chat that can carry
/// effects, with a message typed, it opens the effect picker and hands the
/// pick to [send]; anywhere else it calls [fallback].
Future<void> onSendLongPress(
  BuildContext context, {
  required bool effectsAvailable,
  required String text,
  required Color bubbleColor,
  required Color onBubbleColor,
  required void Function(MessageEffect effect) send,
  required VoidCallback fallback,
}) async {
  if (!effectsAvailable || text.trim().isEmpty) {
    fallback();
    return;
  }
  final effect = await showMessageEffectPicker(
    context,
    text: text,
    bubbleColor: bubbleColor,
    onBubbleColor: onBubbleColor,
    onSchedule: fallback,
  );
  if (effect != null) send(effect);
}

/// The content of the effect sheet: a switch between bubble and screen
/// effects, a stage that plays the chosen effect on the typed message, and
/// the effects of that kind, each with its own send button.
class MessageEffectPicker extends StatefulWidget {
  final String text;
  final Color bubbleColor;
  final Color onBubbleColor;
  final VoidCallback? onSchedule;

  const MessageEffectPicker({
    required this.text,
    required this.bubbleColor,
    required this.onBubbleColor,
    this.onSchedule,
    super.key,
  });

  @override
  State<MessageEffectPicker> createState() => _MessageEffectPickerState();
}

class _MessageEffectPickerState extends State<MessageEffectPicker> {
  MessageEffectKind _kind = MessageEffectKind.bubble;
  MessageEffect _effect = MessageEffect.slam;

  /// Counts previews, so picking the same effect again plays it again.
  int _preview = 0;

  void _select(MessageEffect effect) => setState(() {
    _effect = effect;
    _preview++;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final radius = BorderRadius.circular(20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.sendWithEffect,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (widget.onSchedule case final onSchedule?)
                IconButton(
                  tooltip: l10n.scheduleMessage,
                  icon: const Icon(Icons.schedule_send_outlined),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onSchedule();
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SegmentedButton<MessageEffectKind>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: MessageEffectKind.bubble,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(l10n.effectKindBubble),
              ),
              ButtonSegment(
                value: MessageEffectKind.screen,
                icon: const Icon(Icons.fullscreen_outlined),
                label: Text(l10n.effectKindScreen),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (selected) => setState(() {
              _kind = selected.single;
              _effect = MessageEffect.ofKind(_kind).first;
              _preview++;
            }),
          ),
        ),
        // The stage: the message as it will arrive. Tapping plays it again.
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Material(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _preview++),
                child: ScreenEffectHost(
                  child: Container(
                    alignment: Alignment.bottomRight,
                    padding: const EdgeInsets.all(20),
                    child: EffectBubble(
                      key: ValueKey((_effect, _preview)),
                      effect: _effect,
                      ownMessage: true,
                      autoPlay: true,
                      bubbleColor: widget.bubbleColor,
                      onBubbleColor: widget.onBubbleColor,
                      borderRadius: radius,
                      text: widget.text,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 260),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: widget.bubbleColor,
                          borderRadius: radius,
                        ),
                        child: Text(
                          widget.text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: widget.onBubbleColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final effect in MessageEffect.ofKind(_kind))
                _EffectTile(
                  effect: effect,
                  selected: effect == _effect,
                  onTap: () => _select(effect),
                  onSend: () => Navigator.of(context).pop(effect),
                  sendColor: widget.bubbleColor,
                  onSendColor: widget.onBubbleColor,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EffectTile extends StatelessWidget {
  final MessageEffect effect;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSend;

  /// The colours of the chat's own send button.
  final Color sendColor;
  final Color onSendColor;

  const _EffectTile({
    required this.effect,
    required this.selected,
    required this.onTap,
    required this.onSend,
    required this.sendColor,
    required this.onSendColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final name = effect.localizedName(l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        key: ValueKey('effect_${effect.name}'),
        shape: const StadiumBorder(),
        selected: selected,
        selectedTileColor: theme.colorScheme.secondaryContainer,
        selectedColor: theme.colorScheme.onSecondaryContainer,
        leading: Icon(_iconOf(effect)),
        title: Text(name),
        onTap: onTap,
        trailing: IconButton.filled(
          key: ValueKey('send_effect_${effect.name}'),
          tooltip: l10n.sendWithNamedEffect(name),
          style: IconButton.styleFrom(
            backgroundColor: sendColor,
            foregroundColor: onSendColor,
          ),
          icon: const Icon(Icons.send_outlined),
          onPressed: onSend,
        ),
      ),
    );
  }
}
