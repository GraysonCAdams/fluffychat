// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// The desktop window (`desktop`): the app's Windows window as it builds
/// it, with the title bar over the two columns, the chat list of the
/// `chat-list` fixture on the left and the conversation of the
/// `chat-dm-linked` fixture open on the right.
library;

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/windows_shell.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../harness.dart';
import 'chat.dart';
import 'chat_list.dart';

/// The window's size in logical pixels and its density: a 1280 x 800
/// window on a display at 200 %.
const desktopWidth = 1280;
const desktopHeight = 800;
const desktopPixelRatio = 2.0;

Future<void> pumpDesktopScreen(WidgetTester tester) async {
  final list = ParityFixture.load('chat-list');
  final chat = ParityFixture.load('chat-dm-linked');
  final view = list.onScreen(
    'desktop',
    widthPx: (desktopWidth * desktopPixelRatio).round(),
    heightPx: (desktopHeight * desktopPixelRatio).round(),
    devicePixelRatio: desktopPixelRatio,
  );
  late String location;
  await pumpChatList(
    tester,
    list,
    view: view,
    host: (
      addRooms: (client) async {
        // At a fixed time, since the list prints it on the contact's row.
        location = (await addChat(
          client,
          chat,
          end: fixtureTime('21:40', 0),
        )).location;
      },
      pump: (client, prefs) {
        // setUpParityView picked Android; this window is the Windows app.
        PlatformInfos.debugOperatingSystem = 'windows';
        return pumpParityApp(
          tester,
          client: client,
          prefs: prefs,
          initialLocation: location,
          // As the app's router builds the two columns, with the list's
          // active chat taken from the open contact.
          routes: [
            ShellRoute(
              builder: (context, state, child) {
                final contactId = state.pathParameters['contactid'];
                return TwoColumnLayout(
                  mainView: ChatList(
                    activeChat: contactId == null
                        ? null
                        : mergedContactActiveChat(contactId),
                    displayNavigationRail: true,
                  ),
                  sideView: child,
                );
              },
              routes: [
                GoRoute(
                  path: '/rooms',
                  builder: (context, state) => const SizedBox.shrink(),
                  routes: [
                    GoRoute(
                      path: 'contact/:contactid',
                      builder: (context, state) => ChatPage(
                        roomId: '',
                        contactId: state.pathParameters['contactid'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
          chrome: (router, child) => WindowsChrome(
            showChatList: () => router.go('/rooms'),
            child: child,
          ),
        );
      },
    ),
  );
  await expectParityGolden(tester, view);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}
