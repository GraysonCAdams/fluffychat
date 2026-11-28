// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/browser_sign_in_page.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Connects to the chosen server and goes on to its sign-in: the step
/// before the browser opens (OIDC or SSO, [BrowserSignInPage]), or the
/// password page, with [username] filled in when a Matrix ID was typed.
Future<void> connectToHomeserverFlow(
  PublicHomeserverData homeserverData,
  BuildContext context,
  void Function(AsyncSnapshot<bool>) setState,
  bool signUp, {
  String? username,
}) async {
  setState(AsyncSnapshot.waiting());
  try {
    final homeserverInput = homeserverData.name!;
    var homeserver = Uri.parse(homeserverInput);
    if (homeserver.scheme.isEmpty) {
      homeserver = Uri.https(homeserverInput, '');
    }
    final l10n = L10n.of(context);
    final client = await Matrix.of(context).getLoginClient();
    final (_, _, loginFlows, authMetadata) = await client.checkHomeserver(
      homeserver,
      fetchAuthMetadata: true,
    );

    final regLink = homeserverData.regLink;
    final method = SignInMethod.of(
      loginFlows,
      authMetadata,
      preferOidc: AppSettings.enableMatrixNativeOIDC.value,
    );
    if (!context.mounted) return;

    // The next step lives beside this one: /home/sign_in leads to
    // /home/login, /rooms/settings/addaccount/sign_in to .../login.
    final pathSegments = List.of(
      GoRouter.of(context).routeInformationProvider.value.uri.pathSegments,
    );
    if (pathSegments.last != 'home') pathSegments.removeLast();
    final basePath = '/${pathSegments.join('/')}';

    if (method.usesBrowser) {
      context.push(
        '$basePath/browser',
        extra: BrowserSignInArgs(
          client: client,
          method: method,
          loginFlows: loginFlows,
          signUp: signUp,
          homeserverInput: homeserverInput,
        ),
      );
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
      return;
    }

    if (signUp && regLink != null) {
      // Web and Linux open the registration page in a separate browser
      // window, so they ask first.
      if (kIsWeb || PlatformInfos.isLinux) {
        final consent = await showOkCancelAlertDialog(
          context: context,
          title: l10n.appWantsToUseForLogin(homeserverInput),
          message: l10n.appWantsToUseForLoginDescription,
          okLabel: l10n.continueText,
        );
        if (consent != OkCancelResult.ok) {
          setState(const AsyncSnapshot.nothing());
          return;
        }
      }
      await launchUrlString(regLink);
    }
    if (!context.mounted) return;
    context.push(
      Uri(
        path: '$basePath/login',
        queryParameters: username == null ? null : {'username': username},
      ).toString(),
      extra: client,
    );
    setState(AsyncSnapshot.withData(ConnectionState.done, true));
  } catch (e, s) {
    Logs().w('Unable to login', e, s);
    setState(AsyncSnapshot.withError(ConnectionState.done, e, s));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e.toLocalizedString(context, ExceptionContext.checkHomeserver),
        ),
      ),
    );
  }
}
