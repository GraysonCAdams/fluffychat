// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_state.dart';
import 'package:fluffychat/utils/sign_in_flows/server_input.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';

/// The server step: looks up the server in [serverController] once typing
/// pauses, and keeps the public server list for its sheet.
class SignInViewModel extends ValueNotifier<SignInState> {
  final MatrixState? matrixService;
  final bool signUp;
  final TextEditingController serverController = TextEditingController();

  /// Checks a server and says how it signs in; throws if there is no
  /// Matrix server there. Defaults to [checkWithLoginClient].
  late final Future<SignInMethod> Function(Uri homeserver) checkServer;

  static const Duration lookupDelay = Duration(milliseconds: 600);

  Timer? _lookupTimer;
  String _lookedUp = '';
  bool _disposed = false;

  SignInViewModel(
    this.matrixService, {
    required this.signUp,
    Future<SignInMethod> Function(Uri homeserver)? checkServer,
  }) : super(SignInState()) {
    this.checkServer = checkServer ?? checkWithLoginClient;
    serverController.addListener(_onServerTextChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _lookupTimer?.cancel();
    serverController.removeListener(_onServerTextChanged);
    serverController.dispose();
    super.dispose();
  }

  Future<SignInMethod> checkWithLoginClient(Uri homeserver) async {
    final client = await matrixService!.getLoginClient();
    final (_, _, loginFlows, authMetadata) = await client.checkHomeserver(
      homeserver,
      fetchAuthMetadata: true,
    );
    return SignInMethod.of(
      loginFlows,
      authMetadata,
      preferOidc: AppSettings.enableMatrixNativeOIDC.value,
    );
  }

  void _onServerTextChanged() {
    final text = serverController.text.trim();
    if (text == _lookedUp) return;
    _lookedUp = text;
    _lookupTimer?.cancel();
    final picked = value.pickedPublicHomeserver;
    if (picked != null && picked.name != text) {
      value.pickedPublicHomeserver = null;
    }
    final input = ServerInput.parse(text);
    if (input == null) {
      _setLookup(ServerLookup.idle);
      return;
    }
    _setLookup(ServerLookup(ServerLookupStatus.checking, input: input));
    _lookupTimer = Timer(lookupDelay, () => _lookUp(input));
  }

  Future<void> _lookUp(ServerInput input) async {
    final text = _lookedUp;
    ServerLookup result;
    try {
      final method = await checkServer(input.homeserver);
      result = ServerLookup(
        ServerLookupStatus.found,
        input: input,
        method: method,
      );
    } catch (e, s) {
      Logs().d('No Matrix server at ${input.homeserver}', e, s);
      result = ServerLookup(
        e is http.ClientException || e is TimeoutException
            ? ServerLookupStatus.unreachable
            : ServerLookupStatus.notMatrix,
        input: input,
      );
    }
    // The text changed while the server answered: a newer lookup is due.
    if (text != _lookedUp) return;
    _setLookup(result);
  }

  /// Looks the current text up again at once, after an error.
  void retryLookup() {
    final input = value.lookup.input;
    if (input == null) return;
    _lookupTimer?.cancel();
    _setLookup(ServerLookup(ServerLookupStatus.checking, input: input));
    _lookUp(input);
  }

  void _setLookup(ServerLookup lookup) {
    if (_disposed) return;
    value.lookup = lookup;
    notifyListeners();
  }

  /// Fills in a server from the public list or the recent chips.
  void useServer(String name, {PublicHomeserverData? publicData}) {
    serverController.text = name;
    serverController.selection = TextSelection.collapsed(offset: name.length);
    value.pickedPublicHomeserver = publicData;
    notifyListeners();
  }

  Future<void> loadPublicHomeservers() async {
    if (value.publicHomeservers.connectionState != ConnectionState.none) {
      return;
    }
    value.publicHomeservers = const AsyncSnapshot.waiting();
    notifyListeners();
    try {
      final client = await matrixService!.getLoginClient();
      final response = await client.httpClient.get(AppConfig.homeserverList);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final servers = (json['public_servers'] as List)
          .map((json) => PublicHomeserverData.fromJson(json))
          .toList();
      if (signUp) servers.removeWhere((server) => server.regMethod == null);
      value.publicHomeservers = AsyncSnapshot.withData(
        ConnectionState.done,
        servers,
      );
    } catch (e, s) {
      Logs().w('Unable to fetch public homeservers...', e, s);
      value.publicHomeservers = AsyncSnapshot.withError(
        ConnectionState.done,
        e,
        s,
      );
    }
    if (!_disposed) notifyListeners();
  }

  void setLoginLoading(AsyncSnapshot<bool> loginLoading) {
    value.loginLoading = loginLoading;
    notifyListeners();
  }
}
