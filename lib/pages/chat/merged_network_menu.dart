// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// One network of a merged contact as menus and chips show it.
class MergedNetwork {
  final Room room;
  final Room? space;
  final String name;

  const MergedNetwork(this.room, this.space, this.name);

  /// The networks of [contact] in its room order.
  static List<MergedNetwork> of(MergedContact contact, MatrixLocals locals) {
    final spaces = spacesByChild(contact.rooms.first.client);
    return [
      for (final room in contact.rooms)
        MergedNetwork(
          room,
          spaces[room.id],
          networkName(room, spaces[room.id], locals),
        ),
    ];
  }

  /// The bubble colour for this network: the user's pick, else the main
  /// colour of the network's logo, else null for a network with neither.
  /// The bridge is found as for any chat, so a merged group's rooms, which
  /// have no ghost to read it from, have their network's colour too.
  Color? get bubbleColor =>
      NetworkColors.colorFor(NetworkColors.bridgeIdOfRoom(room));

  Widget icon({double size = 20}) => Avatar(
    mxContent: space?.avatar,
    name: name,
    size: size,
    borderRadius: BorderRadius.circular(size / 4),
  );
}

/// Opens a menu of [networks] below [anchorContext]'s widget, with
/// [selectedRoomId] checked and [defaultRoomId] marked as the default.
/// Returns the picked network's room ID.
Future<String?> showMergedNetworkMenu(
  BuildContext anchorContext, {
  required List<MergedNetwork> networks,
  required String selectedRoomId,
  String? defaultRoomId,
}) {
  final l10n = L10n.of(anchorContext);
  final box = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  // Opens below the anchor when the menu fits there, above it otherwise: in
  // the composer the space below is the keyboard, which showMenu does not
  // keep clear of by itself.
  const itemHeight = 48.0;
  final menuHeight = networks.length * itemHeight + 16;
  // Read from the view: a Scaffold that resizes for the keyboard reports no
  // bottom inset to its body.
  final keyboard = MediaQueryData.fromView(
    View.of(anchorContext),
  ).viewInsets.bottom;
  final spaceBelow =
      overlay.size.height - keyboard - (topLeft.dy + box.size.height);
  final top = spaceBelow >= menuHeight
      ? topLeft.dy + box.size.height
      : topLeft.dy - menuHeight;
  return showMenu<String>(
    context: anchorContext,
    // Leaves focus where it is, so opening the menu from the composer does
    // not close the keyboard.
    requestFocus: false,
    position: RelativeRect.fromLTRB(
      topLeft.dx,
      top,
      overlay.size.width - topLeft.dx - box.size.width,
      0,
    ),
    constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
    items: [
      for (final network in networks)
        PopupMenuItem(
          value: network.room.id,
          height: itemHeight,
          child: Row(
            children: [
              network.icon(size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      network.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (network.room.id == defaultRoomId)
                      Text(
                        l10n.defaultNetwork,
                        style: Theme.of(anchorContext).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 24,
                child: network.room.id == selectedRoomId
                    ? const Icon(Icons.check, size: 20)
                    : null,
              ),
            ],
          ),
        ),
    ],
  );
}
