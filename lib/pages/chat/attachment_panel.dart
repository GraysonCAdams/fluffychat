// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:material_ui/material_ui.dart';

/// The panel the composer's add button opens in place of the keyboard: a
/// grid of round tonal buttons for gallery, camera, files, location and poll.
///
/// Every action here opens a full-screen route, a sheet or a system picker
/// that covers the panel, so the panel stays open underneath. That keeps the
/// composer layout steady while attaching files, which then show up as chips
/// above the input.
class AttachmentPanel extends StatelessWidget {
  final ChatController controller;

  const AttachmentPanel(this.controller, {super.key});

  static const double _panelHeight = 288;
  static const int _columns = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isOpen = controller.showAttachmentPanel;

    final items = <_AttachmentItem>[
      _AttachmentItem(
        icon: Icons.photo_outlined,
        label: l10n.gallery,
        onTap: controller.openGalleryPicker,
      ),
      if (PlatformInfos.isMobile)
        _AttachmentItem(
          icon: Icons.photo_camera_outlined,
          label: l10n.camera,
          onTap: controller.openCameraAction,
        ),
      if (PlatformInfos.isMobile)
        _AttachmentItem(
          icon: Icons.videocam_outlined,
          label: l10n.videoCamera,
          onTap: controller.openVideoCameraAction,
        ),
      _AttachmentItem(
        icon: Icons.attach_file,
        label: l10n.files,
        onTap: controller.pickFilesToComposer,
      ),
      if (PlatformInfos.isMobile)
        _AttachmentItem(
          icon: Icons.location_on_outlined,
          label: l10n.location,
          onTap: controller.sendLocationAction,
        ),
      _AttachmentItem(
        icon: Icons.poll_outlined,
        label: l10n.poll,
        onTap: () =>
            controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.poll),
      ),
    ];

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      // Keeps the panel clear of the composer above it.
      margin: EdgeInsets.only(top: isOpen ? 8 : 0),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      height: isOpen ? _panelHeight : 0,
      width: double.infinity,
      // A Material is needed so the buttons' ink ripples paint above the
      // panel's fill instead of underneath it.
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        child: isOpen
            ? SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cellWidth = constraints.maxWidth / _columns;
                      return Wrap(
                        runSpacing: 24,
                        children: [
                          for (final item in items)
                            SizedBox(
                              width: cellWidth,
                              child: _AttachmentButton(item: item),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _AttachmentItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachmentItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _AttachmentButton extends StatelessWidget {
  final _AttachmentItem item;

  const _AttachmentButton({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      onTap: item.onTap,
      child: Tooltip(
        message: item.label,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Ink(
                  width: 72,
                  height: 56,
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: const StadiumBorder(),
                  ),
                  child: Icon(
                    item.icon,
                    size: 26,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
