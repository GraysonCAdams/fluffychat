// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/platform_infos.dart';
import 'login_error.dart';
import 'login_view.dart';

class Login extends StatefulWidget {
  final Client client;

  /// The localpart of a Matrix ID typed on the server step.
  final String? initialUsername;

  const Login({required this.client, this.initialUsername, super.key});

  @override
  LoginController createState() => LoginController();
}

class LoginController extends State<Login> {
  late final TextEditingController usernameController = TextEditingController(
    text: widget.initialUsername,
  );
  final TextEditingController passwordController = TextEditingController();
  String? usernameError;
  String? passwordError;
  bool loading = false;
  bool showPassword = false;

  /// A problem that is not about what was typed: too many tries, or no
  /// answer from the server. Shown as a notice above the fields.
  LoginError? notice;

  /// Until when the server asked for no more tries; the sign-in button
  /// counts down to it.
  DateTime? rateLimitedUntil;
  Timer? _rateLimitTicker;

  Duration? get rateLimitRemaining {
    final until = rateLimitedUntil;
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  void _waitOut(Duration wait) {
    rateLimitedUntil = DateTime.now().add(wait);
    _rateLimitTicker?.cancel();
    _rateLimitTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (rateLimitRemaining == null) {
        timer.cancel();
        rateLimitedUntil = null;
        notice = null;
      }
      setState(() {});
    });
  }

  void toggleShowPassword() =>
      setState(() => showPassword = !loading && !showPassword);

  Future<void> login() async {
    if (rateLimitRemaining != null) return;
    final matrix = Matrix.of(context);
    if (usernameController.text.isEmpty) {
      setState(() => usernameError = L10n.of(context).pleaseEnterYourUsername);
    } else {
      setState(() => usernameError = null);
    }
    if (passwordController.text.isEmpty) {
      setState(() => passwordError = L10n.of(context).pleaseEnterYourPassword);
    } else {
      setState(() => passwordError = null);
    }

    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      return;
    }

    setState(() {
      loading = true;
      notice = null;
    });

    _coolDown?.cancel();

    try {
      final username = usernameController.text;
      AuthenticationIdentifier identifier;
      if (username.isEmail) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'email',
          address: username,
        );
      } else if (username.isPhoneNumber) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'msisdn',
          address: username,
        );
      } else {
        identifier = AuthenticationUserIdentifier(user: username);
      }
      final client = await matrix.getLoginClient();
      await client.login(
        LoginType.mLoginPassword,
        identifier: identifier,
        // To stay compatible with older server versions
        // ignore: deprecated_member_use
        user: identifier.type == AuthenticationIdentifierTypes.userId
            ? username
            : null,
        password: passwordController.text,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
      if (mounted) {
        context.go(Matrix.of(context).afterSignInLocation);
      }
    } catch (exception, s) {
      Logs().d('Password sign-in failed', exception, s);
      if (!mounted) return;
      final error = LoginError.of(exception);
      final l10n = L10n.of(context);
      setState(() {
        loading = false;
        switch (error.kind) {
          case LoginErrorKind.wrongCredentials:
            passwordError = l10n.wrongUsernameOrPassword;
          case LoginErrorKind.rateLimited:
            notice = error;
            final wait = error.retryAfter;
            if (wait != null) _waitOut(wait);
          case LoginErrorKind.unreachable:
            notice = error;
          case LoginErrorKind.other:
            passwordError = error.message;
        }
      });
      return;
    }

    if (mounted) setState(() => loading = false);
  }

  Timer? _coolDown;

  void checkWellKnownWithCoolDown(String userId) {
    _coolDown?.cancel();
    _coolDown = Timer(
      const Duration(seconds: 1),
      () => _checkWellKnown(userId),
    );
  }

  Future<void> _checkWellKnown(String userId) async {
    if (mounted) setState(() => usernameError = null);
    if (!userId.isValidMatrixIdStrict()) return;
    final oldHomeserver = widget.client.homeserver;
    try {
      var newDomain = Uri.https(userId.domain!, '');
      widget.client.homeserver = newDomain;
      DiscoveryInformation? wellKnownInformation;
      try {
        wellKnownInformation = await widget.client.getWellknown();
        if (wellKnownInformation.mHomeserver.baseUrl.toString().isNotEmpty) {
          newDomain = wellKnownInformation.mHomeserver.baseUrl;
        }
      } catch (_) {
        // do nothing, newDomain is already set to a reasonable fallback
      }
      if (newDomain != oldHomeserver) {
        await widget.client.checkHomeserver(newDomain);

        if (widget.client.homeserver == null) {
          widget.client.homeserver = oldHomeserver;
          // okay, the server we checked does not appear to be a matrix server
          Logs().v(
            '$newDomain is not running a homeserver, asking to use $oldHomeserver',
          );
          if (!mounted) return;
          final l10n = L10n.of(context);
          final dialogResult = await showOkCancelAlertDialog(
            context: context,
            useRootNavigator: false,
            title: l10n.noMatrixServer(
              newDomain.toString(),
              oldHomeserver.toString(),
            ),
            okLabel: l10n.ok,
            cancelLabel: l10n.cancel,
          );
          if (!mounted) return;
          if (dialogResult == OkCancelResult.ok) {
            if (mounted) setState(() => usernameError = null);
          } else {
            Navigator.of(context, rootNavigator: false).pop();
            return;
          }
        }
        usernameError = null;
        if (mounted) setState(() {});
      } else {
        widget.client.homeserver = oldHomeserver;
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      widget.client.homeserver = oldHomeserver;
      if (!mounted) return;
      usernameError = e.toLocalizedString(context);
      if (mounted) setState(() {});
    }
  }

  Future<void> passwordForgotten() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.enterAnEmailAddress,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: usernameController.text.isEmail
          ? usernameController.text
          : '',
      hintText: l10n.enterAnEmailAddress,
      keyboardType: TextInputType.emailAddress,
    );
    if (input == null) return;
    if (!mounted) return;
    final clientSecret = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.requestTokenToResetPasswordEmail(
        clientSecret,
        input,
        sendAttempt++,
      ),
    );
    if (response.error != null) return;
    if (!mounted) return;
    final password = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.chooseAStrongPassword,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: '******',
      obscureText: true,
      minLines: 1,
      maxLines: 1,
    );
    if (password == null) return;
    if (!mounted) return;
    final ok = await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.weSentYouAnEmail,
      message: l10n.pleaseClickOnLink,
      okLabel: l10n.iHaveClickedOnLink,
    );
    if (ok != OkCancelResult.ok) return;
    if (!mounted) return;
    final data = <String, dynamic>{
      'new_password': password,
      'logout_devices': false,
      'auth': AuthenticationThreePidCreds(
        type: AuthenticationTypes.emailIdentity,
        threepidCreds: ThreepidCreds(
          sid: response.result!.sid,
          clientSecret: clientSecret,
        ),
      ).toJson(),
    };
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.request(
        RequestType.POST,
        '/client/v3/account/password',
        data: data,
      ),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.passwordHasBeenChanged)),
      );
      usernameController.text = input;
      passwordController.text = password;
      login();
    }
  }

  static int sendAttempt = 0;

  @override
  void dispose() {
    _rateLimitTicker?.cancel();
    _coolDown?.cancel();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoginView(this);
}

extension on String {
  static final RegExp _phoneRegex = RegExp(
    r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$',
  );
  static final RegExp _emailRegex = RegExp(r'(.+)@(.+)\.(.+)');

  bool get isEmail => _emailRegex.hasMatch(this);

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
