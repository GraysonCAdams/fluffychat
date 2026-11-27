// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/add_people/add_people.dart';
import 'package:fluffychat/pages/archive/archive.dart';
import 'package:fluffychat/pages/bootstrap/bootstrap_page.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat_access_settings/chat_access_settings_controller.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_encryption_settings/chat_encryption_settings.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_members/chat_members.dart';
import 'package:fluffychat/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:fluffychat/pages/chat_search/chat_search_page.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/pages/intro/intro_page_presenter.dart';
import 'package:fluffychat/pages/invitation_selection/invitation_selection.dart';
import 'package:fluffychat/pages/login/login.dart';
import 'package:fluffychat/pages/new_group/new_group.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:fluffychat/pages/settings_chat/settings_swipe_actions.dart';
import 'package:fluffychat/pages/settings_emotes/settings_emotes.dart';
import 'package:fluffychat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:fluffychat/pages/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/pages/settings_matrix_features/settings_matrix_features.dart';
import 'package:fluffychat/pages/settings_merged_contacts/settings_merged_contacts.dart';
import 'package:fluffychat/pages/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/pages/settings_password/settings_password.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/pages/settings_style/settings_style.dart';
import 'package:fluffychat/pages/sign_in/sign_in_page.dart';
import 'package:fluffychat/utils/handoff_page.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/widgets/chat_windows_host.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:fluffychat/widgets/log_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

abstract class AppRoutes {
  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? '/rooms'
      : null;

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? null
      : '/home';

  AppRoutes();

  /// The app's route table, built anew on each read: a [ShellRoute] holds
  /// its navigator's key, and the main window's router and each chat
  /// window's ([ChatWindowScope]) need their own.
  static List<RouteBase> get routes => [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          Matrix.of(context).widget.clients.any((client) => client.isLogged())
          ? '/rooms'
          : '/home',
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const IntroPagePresenter()),
      redirect: loggedInRedirect,
      routes: [
        GoRoute(
          path: 'sign_in',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInPage(signUp: false)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'sign_up',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInPage(signUp: true)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'login',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            Login(client: state.extra as Client),
          ),
          redirect: loggedInRedirect,
        ),
      ],
    ),
    GoRoute(
      path: '/logs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const LogViewer()),
    ),
    GoRoute(
      path: '/configs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const ConfigViewer()),
    ),
    GoRoute(
      path: '/backup',
      redirect: loggedOutRedirect,
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        BootstrapPage(reset: state.uri.queryParameters['reset'] == 'true'),
      ),
    ),
    ShellRoute(
      // Never use a transition on the shell route. Changing the PageBuilder
      // here based on a MediaQuery causes the child to briefly be rendered
      // twice with the same GlobalKey, blowing up the rendering.
      // A chat window shows its chat without the list beside it.
      pageBuilder: (context, state, child) => noTransitionPageBuilder(
        context,
        state,
        FluffyThemes.isColumnMode(context) &&
                !ChatWindowScope.isChatWindow(context) &&
                state.fullPath?.startsWith('/rooms/settings') == false
            ? TwoColumnLayout(
                mainView: ChatList(
                  activeChat: _activeChat(state),
                  activeSpace: state.uri.queryParameters['spaceId'],
                  displayNavigationRail:
                      state.path?.startsWith('/rooms/settings') != true,
                ),
                sideView: child,
              )
            : child,
      ),
      routes: [
        GoRoute(
          path: '/rooms',
          redirect: loggedOutRedirect,
          // In a chat window this page only sits under the chat, never shown.
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            FluffyThemes.isColumnMode(context) ||
                    ChatWindowScope.isChatWindow(context)
                ? const EmptyPage()
                : ChatList(
                    activeChat: _activeChat(state),
                    activeSpace: state.uri.queryParameters['spaceId'],
                  ),
          ),
          routes: [
            GoRoute(
              path: 'archive',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const Archive()),
              routes: [
                GoRoute(
                  path: ':roomid',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatPage(
                      key: ValueKey(state.uri),
                      roomId: state.pathParameters['roomid']!,
                      eventId: state.uri.queryParameters['event'],
                      timeline: state.extra as Timeline?,
                      action: state.uri.queryParameters['action'],
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
              ],
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newprivatechat',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewPrivateChat(
                  key: ValueKey(
                    'new_chat_${state.uri.fragment}_${state.uri.query}',
                  ),
                  deeplink: state.uri.fragment,
                  startGroup: state.uri.queryParameters['group'] == '1',
                  // What is shared from another app or forwarded, staged
                  // in the composer.
                  share: state.extra is SharedDraft
                      ? state.extra as SharedDraft
                      : null,
                ),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newgroup',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewGroup(spaceId: state.uri.queryParameters['space_id']),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newspace',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewGroup(
                  createGroupType: CreateGroupType.space,
                  spaceId: state.uri.queryParameters['space_id'],
                ),
              ),
              redirect: loggedOutRedirect,
            ),
            ShellRoute(
              pageBuilder: (context, state, child) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? TwoColumnLayout(
                        mainView: Settings(key: state.pageKey),
                        sideView: child,
                        hasNavigationRail: false,
                      )
                    : child,
              ),
              routes: [
                GoRoute(
                  path: 'settings',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    FluffyThemes.isColumnMode(context)
                        ? const EmptyPage()
                        : const Settings(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'notifications',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsNotifications(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'style',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsStyle(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'devices',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const DevicesSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'chat',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsChat(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'merged_contacts',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const SettingsMergedContacts(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'swipe_actions',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const SettingsSwipeActions(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'matrix_features',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const SettingsMatrixFeatures(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'emotes',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            EmotesSettings(
                              roomId: state.pathParameters['roomid'],
                            ),
                          ),
                        ),
                      ],
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'addaccount',
                      redirect: loggedOutRedirect,
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const IntroPagePresenter(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'sign_in',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            SignInPage(signUp: false),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'sign_up',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            SignInPage(signUp: true),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'login',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            Login(client: state.extra as Client),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                    ),
                    GoRoute(
                      path: 'homeserver',
                      pageBuilder: (context, state) {
                        return defaultPageBuilder(
                          context,
                          state,
                          const SettingsHomeserver(),
                        );
                      },
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'security',
                      redirect: loggedOutRedirect,
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsSecurity(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'password',
                          pageBuilder: (context, state) {
                            return defaultPageBuilder(
                              context,
                              state,
                              const SettingsPassword(),
                            );
                          },
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'ignorelist',
                          pageBuilder: (context, state) {
                            return defaultPageBuilder(
                              context,
                              state,
                              SettingsIgnoreList(
                                initialUserId: state.extra?.toString(),
                              ),
                            );
                          },
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: '3pid',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const Settings3Pid(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
            GoRoute(
              path: 'contact/:contactid',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                ChatPage(
                  key: ValueKey(state.uri),
                  roomId: '',
                  contactId: state.pathParameters['contactid'],
                  // A share picked for this contact in the Android share
                  // sheet, staged in the composer.
                  share: state.extra is SharedDraft
                      ? state.extra as SharedDraft
                      : null,
                  eventId: state.uri.queryParameters['event'],
                  eventRoomId: state.uri.queryParameters['room'],
                  action: state.uri.queryParameters['action'],
                ),
                handoff: true,
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: ':roomid',
              pageBuilder: (context, state) {
                final body = state.uri.queryParameters['body'];
                var share = state.extra is SharedDraft
                    ? state.extra as SharedDraft
                    : null;
                if (body != null && body.isNotEmpty) {
                  share = SharedDraft([
                    ...?share?.items,
                    TextShareItem(body),
                  ], fromShareIntent: share?.fromShareIntent ?? false);
                }
                return defaultPageBuilder(
                  context,
                  state,
                  ChatPage(
                    key: ValueKey(state.uri),
                    roomId: state.pathParameters['roomid']!,
                    share: share,
                    eventId: state.uri.queryParameters['event'],
                    action: state.uri.queryParameters['action'],
                  ),
                  handoff: true,
                );
              },
              redirect: (context, state) =>
                  Matrix.of(
                    context,
                  ).widget.clients.any((client) => client.isLogged())
                  ? _mergedContactRedirect(context, state)
                  : '/home',
              routes: [
                GoRoute(
                  path: 'search',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatSearchPage(roomId: state.pathParameters['roomid']!),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'encryption',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const ChatEncryptionSettings(),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'invite',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    InvitationSelection(
                      roomId: state.pathParameters['roomid']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'add-people',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    AddPeople(roomId: state.pathParameters['roomid']!),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'details',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatDetails(roomId: state.pathParameters['roomid']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'access',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatAccessSettings(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'members',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatMembersPage(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'permissions',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const ChatPermissionsSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'invite',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        InvitationSelection(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'emotes',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        EmotesSettings(roomId: state.pathParameters['roomid']),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];

  /// The chat the chat list highlights: the room shown, or a merged
  /// contact's screen.
  static String? _activeChat(GoRouterState state) {
    final contactId = state.pathParameters['contactid'];
    if (contactId != null) return mergedContactActiveChat(contactId);
    return state.pathParameters['roomid'];
  }

  /// A room in a merged contact opens the contact's merged screen, so
  /// notifications, links and the chat list land there. Only the room's own
  /// page is redirected, not its details or settings; `single=1` keeps the
  /// room on its own, and shared items stay with the room they were shared
  /// to.
  static String? _mergedContactRedirect(
    BuildContext context,
    GoRouterState state,
  ) {
    if (state.fullPath != '/rooms/:roomid') return null;
    final query = state.uri.queryParameters;
    if (query['single'] == '1' ||
        state.extra != null ||
        query['body'] != null) {
      return null;
    }
    final roomId = state.pathParameters['roomid'];
    if (roomId == null) return null;
    final client = Matrix.of(context).client;
    final contact = MergedContactsStore.forClient(
      client,
    ).contactForRoom(roomId);
    if (contact == null) return null;
    final event = query['event'];
    final action = query['action'];
    final clientName = query['client'];
    return Uri(
      path: '/rooms/contact/${contact.id}',
      queryParameters: {
        if (event != null) ...{'event': event, 'room': roomId},
        'action': ?action,
        'client': ?clientName,
      },
    ).toString();
  }

  static Page noTransitionPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => NoTransitionPage(
    key: state.pageKey,
    restorationId: state.pageKey.value,
    child: child,
  );

  /// The page for [child]: without a transition beside the chat list, else
  /// a Material page. A chat's page ([handoff]) enters at once when a peek
  /// card grew into it, see [PageHandoff].
  static Page defaultPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child, {
    bool handoff = false,
  }) {
    final clientName = state.uri.queryParameters['client'];
    if (clientName != null) {
      final matrix = Matrix.of(context);
      final client = matrix.getClientByName(clientName);
      if (client != null) matrix.setActiveClient(client);
    }
    if (FluffyThemes.isColumnMode(context)) {
      return noTransitionPageBuilder(context, state, child);
    }
    if (handoff) {
      return HandoffPage(
        key: state.pageKey,
        restorationId: state.pageKey.value,
        enterInstantly: PageHandoff.take(),
        child: child,
      );
    }
    return MaterialPage(
      key: state.pageKey,
      restorationId: state.pageKey.value,
      child: child,
    );
  }
}
