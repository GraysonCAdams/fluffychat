// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum _MessageAction {
  reply,
  thread,
  edit,
  copy,
  forward,
  pin,
  download,
  delete,
  info,
  report,
}

/// A quick reaction picked from the row at the top of the menu.
class _React {
  final String emoji;
  const _React(this.emoji);
}

/// Shows the actions for [event] at [position], as opened by a right click.
///
/// The message is selected while the menu is open, so each action is the
/// same one the selection app bar runs on it. Dismissing the menu without
/// picking anything clears the selection again.
Future<void> showMessageContextMenu(
  ChatController controller,
  Event event,
  Offset position,
) async {
  if (event.redacted) return;
  final context = controller.context;
  final l10n = L10n.of(context);
  final room = controller.room;
  controller.selectOnly(event);

  final timeline = controller.timeline;
  final sentReactions = timeline == null
      ? <String>{}
      : event
            .aggregatedEvents(timeline, RelationshipTypes.reaction)
            .where((e) => e.senderId == room.client.userID)
            .map(
              (e) => e.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>()
            .toSet();

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(position);
  final canSend = room.canSendDefaultMessages;

  PopupMenuItem<Object> item(
    _MessageAction value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<Object>(
      value: value,
      child: Row(
        mainAxisSize: .min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

  controller.setMessageMenuOpen(true);
  final picked = await showMenu<Object>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(
      local & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      if (canSend)
        PopupMenuItem<Object>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Builder(
            builder: (context) => Row(
              mainAxisSize: .min,
              children: AppConfig.defaultReactions
                  .map(
                    (emoji) => IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: sentReactions.contains(emoji)
                          ? null
                          : () => Navigator.of(context).pop(_React(emoji)),
                      icon: Opacity(
                        opacity: sentReactions.contains(emoji) ? 0.33 : 1,
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      if (canSend) const PopupMenuDivider(),
      if (canSend) item(_MessageAction.reply, Icons.reply_outlined, l10n.reply),
      if (canSend && controller.activeThreadId == null)
        item(_MessageAction.thread, Icons.message_outlined, l10n.replyInThread),
      if (controller.canEditSelectedEvents)
        item(_MessageAction.edit, Icons.edit_outlined, l10n.edit),
      item(_MessageAction.copy, Icons.copy_outlined, l10n.copyToClipboard),
      item(_MessageAction.forward, Icons.forward_outlined, l10n.forward),
      if (controller.canPinSelectedEvents)
        item(_MessageAction.pin, Icons.push_pin_outlined, l10n.pinMessage),
      if (controller.canSaveSelectedEvent)
        item(
          _MessageAction.download,
          Icons.download_outlined,
          l10n.downloadFile,
        ),
      if (controller.canRedactSelectedEvents)
        item(_MessageAction.delete, Icons.delete_outlined, l10n.redactMessage),
      item(_MessageAction.info, Icons.info_outlined, l10n.messageInfo),
      if (event.status.isSent)
        item(
          _MessageAction.report,
          Icons.shield_outlined,
          l10n.reportMessage,
          color: Colors.red,
        ),
    ],
  );

  if (!controller.mounted) return;
  controller.setMessageMenuOpen(false);
  switch (picked) {
    case _React(:final emoji):
      controller.clearSelectedEvents();
      await room.sendReaction(event.eventId, emoji);
    case _MessageAction.reply:
      controller.replyAction(replyTo: event);
    case _MessageAction.thread:
      controller.clearSelectedEvents();
      controller.enterThread(event.eventId);
    case _MessageAction.edit:
      controller.editSelectedEventAction();
    case _MessageAction.copy:
      controller.copyEventsAction();
    case _MessageAction.forward:
      await controller.forwardEventsAction();
    case _MessageAction.pin:
      controller.pinEvent();
    case _MessageAction.download:
      controller.clearSelectedEvents();
      event.saveFile(controller.context);
    case _MessageAction.delete:
      await controller.redactEventsAction();
    case _MessageAction.info:
      controller.clearSelectedEvents();
      controller.showEventInfo(event);
    case _MessageAction.report:
      await controller.reportEventAction();
    default:
      controller.clearSelectedEvents();
  }
}
