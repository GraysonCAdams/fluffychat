import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// The macOS menu bar: the app menu with Settings, a File menu for starting
/// chats, the standard Edit commands, and the system's View and Window items.
///
/// [PlatformMenuBar] replaces every menu in `MainMenu.xib`, so the Edit
/// commands are declared here and sent to the focused text field as the same
/// intents its keyboard shortcuts raise.
class MacMenuBar extends StatelessWidget {
  final GoRouter router;
  final Widget child;

  const MacMenuBar({required this.router, required this.child, super.key});

  static void _invoke(Intent intent) {
    final context = primaryFocus?.context;
    if (context == null) return;
    Actions.maybeInvoke(context, intent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final material = MaterialLocalizations.of(context);
    const cause = SelectionChangedCause.keyboard;
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          // AppKit shows the app's name for the first menu whatever its label.
          label: 'Seam',
          menus: [
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '${l10n.settings}…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: () => router.go('/rooms/settings'),
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: l10n.newChat,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: () => router.go('/rooms/newprivatechat'),
            ),
            PlatformMenuItem(
              label: l10n.newGroup,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
              ),
              onSelected: () => router.go('/rooms/newgroup'),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Undo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                  ),
                  onSelected: () => _invoke(const UndoTextIntent(cause)),
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () => _invoke(const RedoTextIntent(cause)),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: material.cutButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelected: () =>
                      _invoke(const CopySelectionTextIntent.cut(cause)),
                ),
                PlatformMenuItem(
                  label: material.copyButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                  onSelected: () => _invoke(CopySelectionTextIntent.copy),
                ),
                PlatformMenuItem(
                  label: material.pasteButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelected: () => _invoke(const PasteTextIntent(cause)),
                ),
                PlatformMenuItem(
                  label: material.selectAllButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelected: () => _invoke(const SelectAllTextIntent(cause)),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: l10n.chats,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit1,
                meta: true,
              ),
              onSelected: () => router.go('/rooms'),
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.minimizeWindow,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.zoomWindow,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
