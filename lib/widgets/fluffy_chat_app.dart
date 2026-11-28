// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat_windows/chat_windows.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/windows_shell.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/chat_windows_host.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class FluffyChatApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final ({String? pincode, bool useBiometrics}) appLockSettings;
  final SharedPreferences store;
  final Locale? locale;

  /// The system's dynamic primary color, see loadDynamicPrimaryColor().
  final Color? dynamicPrimaryColor;

  const FluffyChatApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    required this.appLockSettings,
    this.locale,
    this.dynamicPrimaryColor,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      // Workaround for content sharings passed to go router:
      if ({
        'content',
        'sharemedia-im.fluffychat.app',
        'sharemedia-${AppConfig.seamApplicationId}',
      }.contains(state.uri.scheme)) {
        Logs().d('Ignore content sharing handling in go router', state.uri);
        return '/';
      }

      if (state.uri.scheme == 'matrix') {
        // A matrix: URI names its target as <type>/<id>; anything shorter
        // has nothing to open.
        final segments = state.uri.pathSegments;
        if (segments.length < 2) return '/';
        final type = segments[0];
        final id = segments[1];
        switch (type) {
          case 'roomid':
            final roomId = '!$id';
            return '/rooms/$roomId';
          case 'r':
            final alias = '#$id';
            return '/rooms/newprivatechat#$alias';
          case 'u':
            final userId = '@$id';
            return '/rooms/newprivatechat#$userId';
        }
      }

      // Pass deep links to app:
      if (state.uri.toString().startsWith(AppConfig.deepLinkPrefix)) {
        return '/rooms/newprivatechat#${state.uri}';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      store: store,
      dynamicPrimaryColor: dynamicPrimaryColor,
      builder: (context, themeMode, primaryColor) => MaterialApp.router(
        title: AppSettings.applicationName.value,
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: FluffyThemes.buildTheme(context, Brightness.light, primaryColor),
        darkTheme: FluffyThemes.buildTheme(
          context,
          Brightness.dark,
          primaryColor,
        ),
        scrollBehavior: CustomScrollBehavior(),
        localizationsDelegates: [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
          ...GlobalCupertinoLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
        builder: (context, child) {
          var content = testWidget ?? child ?? const SizedBox.shrink();
          if (ChatWindows.instance.isSupported) {
            content = ChatWindowsHost(
              windowBuilder: (context, target) => _ChatWindowApp(
                key: ValueKey(target),
                target: target,
                themeMode: themeMode,
                primaryColor: primaryColor,
                locale: locale,
              ),
              child: content,
            );
          }
          if (PlatformInfos.isWindows) {
            // Inside Matrix, as the title bar shows the account.
            content = WindowsChrome(
              showChatList: () => router.go('/rooms'),
              child: content,
            );
          }
          final app = AppLockWidget(
            pincode: appLockSettings.pincode,
            useBiometrics: appLockSettings.useBiometrics,
            isLoggedIn: clients.any((client) => client.isLogged()),
            // Need a navigator above the Matrix widget for
            // displaying dialogs
            child: Matrix(clients: clients, store: store, child: content),
          );
          if (!PlatformInfos.isWindows) return app;
          return WindowsTitleBarSync(child: app);
        },
      ),
    );
  }
}

/// The app as a chat window shows it: [target] on its own, in the main
/// window's theme and language. The window has its own router over the
/// app's routes, so the chat's details, search and other pages open inside
/// it; any other page opens in the main window, which comes to the front.
class _ChatWindowApp extends StatefulWidget {
  final ChatWindowTarget target;
  final ThemeMode themeMode;
  final Color? primaryColor;
  final Locale? locale;

  const _ChatWindowApp({
    required this.target,
    required this.themeMode,
    required this.primaryColor,
    required this.locale,
    super.key,
  });

  @override
  State<_ChatWindowApp> createState() => _ChatWindowAppState();
}

class _ChatWindowAppState extends State<_ChatWindowApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.target.location,
    routes: AppRoutes.routes,
    redirect: _redirect,
  );

  /// The last location this window accepted, where it stays when asked to
  /// go elsewhere.
  String? _location;

  String? _redirect(BuildContext context, GoRouterState state) {
    final target = widget.target;
    final store = MergedContactsStore.forClient(Matrix.of(context).client);
    final contactId = target.contactId;
    final contact = contactId != null
        ? store.contactById(contactId)
        : store.contactForRoom(target.roomId!);
    if (target.owns(state.uri, contactRooms: contact?.rooms ?? const [])) {
      _location = state.uri.toString();
      return null;
    }
    final location = state.uri.toString();
    final extra = state.extra;
    // Not during the redirect: the main router may be mid-build.
    scheduleMicrotask(() {
      // A chat goes to the chat list once it is left or forgotten, which
      // here closes the window.
      if (location == '/rooms') {
        ChatWindows.instance.close(target);
        return;
      }
      FluffyChatApp.router.go(location, extra: extra);
      WindowsDesktop.showWindow();
    });
    return _location ?? target.location;
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: AppSettings.applicationName.value,
    themeMode: widget.themeMode,
    debugShowCheckedModeBanner: false,
    locale: widget.locale,
    theme: FluffyThemes.buildTheme(
      context,
      Brightness.light,
      widget.primaryColor,
    ),
    darkTheme: FluffyThemes.buildTheme(
      context,
      Brightness.dark,
      widget.primaryColor,
    ),
    scrollBehavior: CustomScrollBehavior(),
    localizationsDelegates: [
      ...L10n.localizationsDelegates,
      ...GlobalMaterialLocalizations.delegates,
      ...GlobalCupertinoLocalizations.delegates,
    ],
    supportedLocales: L10n.supportedLocales,
    routerConfig: _router,
    builder: (context, child) =>
        ChatWindowTitleBarSync(child: child ?? const SizedBox.shrink()),
  );
}
