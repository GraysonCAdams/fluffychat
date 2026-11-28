// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/optical_line.dart';
import 'package:fluffychat/pages/chat/events/state_event_group.dart';
import 'package:fluffychat/pages/chat/utd_dialog.dart';
import 'package:fluffychat/utils/state_event_summary.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A system event on its own in the timeline (one not folded into a
/// [StateEventGroup]): one centred line of small grey text. A message that
/// could not be decrypted shows its sender and a button that explains why.
class StateMessage extends StatelessWidget {
  final Event event;
  const StateMessage(this.event, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final style = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      decoration: event.redacted ? TextDecoration.lineThrough : null,
    );
    final Widget line;
    if (event.type != EventTypes.Encrypted || event.redacted) {
      line = LayoutBuilder(
        builder: (context, box) => OpticalLine(
          StateEventSummary.line(event, l10n),
          style: style,
          maxWidth: box.maxWidth >= 600
              ? StateEventGroup.wideMaxWidth
              : box.maxWidth,
        ),
      );
    } else {
      final sender = event.senderFromMemoryOrFallback;
      line = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Avatar(
              name: sender.calcDisplayname(),
              size: 14,
              mxContent: sender.avatarUrl,
            ),
          ),
          Flexible(
            child: Text(
              l10n.messageNotDecryptable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => UtdDialog.show(context, event),
              child: Icon(Icons.info_outlined, size: 14, color: style.color),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: StateEventGroup.rhythm,
      ),
      child: Center(child: line),
    );
  }
}
