// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_state.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

class SignInViewModel extends ValueNotifier<SignInState> {
  final MatrixState matrixService;
  final bool signUp;
  final TextEditingController filterTextController = TextEditingController();

  SignInViewModel(this.matrixService, {required this.signUp})
    : super(SignInState()) {
    refreshPublicHomeservers();
    filterTextController.addListener(_filterHomeservers);
  }

  @override
  void dispose() {
    filterTextController.removeListener(_filterHomeservers);
    filterTextController.dispose();
    super.dispose();
  }

  void _filterHomeservers() {
    final filterText = filterTextController.text.trim().toLowerCase();
    final filteredPublicHomeservers =
        value.publicHomeservers.data
            ?.where(
              (homeserver) =>
                  homeserver.name?.toLowerCase().contains(filterText) ?? false,
            )
            .toList() ??
        [];
    if (filterText.length >= 3 &&
        (filterText.contains('.') || filterText.endsWith('localhost')) &&
        Uri.tryParse(filterText) != null &&
        !filteredPublicHomeservers.any(
          (homeserver) => homeserver.name == filterText,
        )) {
      filteredPublicHomeservers.add(PublicHomeserverData(name: filterText));
    }
    value.filteredPublicHomeservers = filteredPublicHomeservers;
    notifyListeners();
  }

  Future<void> refreshPublicHomeservers() async {
    notifyListeners();
    value.publicHomeservers = AsyncSnapshot.waiting();
    // The Play build recommends no server: it neither fetches the public
    // list nor preselects matrix.org. The user types their own homeserver,
    // which _filterHomeservers offers as a choice, and a server they signed
    // in to before is offered again.
    if (AppConfig.isPlayRelease) {
      final remembered = AppSettings.store.getString(
        AppSettings.defaultHomeserver.key,
      );
      final servers = [
        if (remembered != null && remembered.isNotEmpty)
          PublicHomeserverData(name: remembered),
      ];
      value.selectedHomeserver ??= servers.firstOrNull;
      value.publicHomeservers = AsyncSnapshot.withData(
        ConnectionState.done,
        servers,
      );
      notifyListeners();
      _filterHomeservers();
      return;
    }
    final defaultHomeserverData = PublicHomeserverData(
      name: AppSettings.defaultHomeserver.value,
    );
    try {
      final client = await matrixService.getLoginClient();
      final response = await client.httpClient.get(AppConfig.homeserverList);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final homeserverJsonList = json['public_servers'] as List;

      final publicHomeservers = homeserverJsonList
          .map((json) => PublicHomeserverData.fromJson(json))
          .toList();

      if (signUp) {
        publicHomeservers.removeWhere((server) {
          return server.regMethod == null;
        });
      }

      final defaultServer = publicHomeservers.singleWhereOrNull(
        (server) => server.name == AppSettings.defaultHomeserver.value,
      );

      if (defaultServer == null) {
        publicHomeservers.insert(0, defaultHomeserverData);
      }

      value.selectedHomeserver =
          value.selectedHomeserver ?? publicHomeservers.first;
      value.publicHomeservers = AsyncSnapshot.withData(
        ConnectionState.done,
        publicHomeservers,
      );
      notifyListeners();
    } catch (e, s) {
      Logs().w('Unable to fetch public homeservers...', e, s);
      value.selectedHomeserver = defaultHomeserverData;
      value.publicHomeservers = AsyncSnapshot.withData(ConnectionState.done, [
        defaultHomeserverData,
      ]);
      notifyListeners();
    }
    _filterHomeservers();
  }

  void selectHomeserver(PublicHomeserverData? publicHomeserverData) {
    value.selectedHomeserver = publicHomeserverData;
    notifyListeners();
  }

  void setLoginLoading(AsyncSnapshot<bool> loginLoading) {
    value.loginLoading = loginLoading;
    notifyListeners();
  }
}
