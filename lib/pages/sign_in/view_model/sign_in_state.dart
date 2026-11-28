// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/sign_in_flows/server_input.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:material_ui/material_ui.dart';

enum ServerLookupStatus { idle, checking, found, unreachable, notMatrix }

/// What the server step knows about the server typed so far.
class ServerLookup {
  final ServerLookupStatus status;
  final ServerInput? input;
  final SignInMethod? method;

  const ServerLookup(this.status, {this.input, this.method});

  static const idle = ServerLookup(ServerLookupStatus.idle);
}

class SignInState {
  ServerLookup lookup = ServerLookup.idle;

  /// The public server list, fetched when its sheet first opens.
  AsyncSnapshot<List<PublicHomeserverData>> publicHomeservers =
      const AsyncSnapshot.nothing();

  /// The server picked from the public list, which may carry a
  /// registration link; null once the field is edited by hand.
  PublicHomeserverData? pickedPublicHomeserver;
  AsyncSnapshot<bool> loginLoading = const AsyncSnapshot.nothing();
}
