// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:matrix/matrix.dart';

/// The user's bridges and their contact lists for New Chat, one per client,
/// kept for [lifetime] so reopening New Chat does not ask every bridge
/// again.
class BridgeDirectory {
  final BridgeProvisioning api;

  BridgeDirectory(this.api);

  static const Duration lifetime = Duration(minutes: 10);

  static final Expando<BridgeDirectory> _directories = Expando();

  /// The directory of [client]; null while it is not logged in.
  static BridgeDirectory? forClient(Client client) {
    final homeserver = client.homeserver;
    final accessToken = client.accessToken;
    final userId = client.userID;
    if (homeserver == null || accessToken == null || userId == null) {
      return null;
    }
    final known = _directories[client];
    if (known != null &&
        known.api.accessToken == accessToken &&
        known.api.homeserver == homeserver) {
      return known;
    }
    return _directories[client] = BridgeDirectory(
      BridgeProvisioning(
        httpClient: client.httpClient,
        homeserver: homeserver,
        accessToken: accessToken,
        userId: userId,
      ),
    );
  }

  Future<List<BridgeInfo>>? _bridges;
  Future<List<BridgeContactInput>>? _contacts;
  DateTime? _fetched;

  bool get _stale =>
      _fetched == null || DateTime.now().difference(_fetched!) > lifetime;

  /// The bridges the user is logged in to.
  Future<List<BridgeInfo>> bridges() {
    if (_stale) {
      _fetched = DateTime.now();
      _contacts = null;
      _bridges = api.discover();
    }
    return _bridges!;
  }

  /// Every contact of every bridge that lists them. A bridge that fails or
  /// has no contact list adds none.
  Future<List<BridgeContactInput>> contacts() async {
    final bridges = await this.bridges();
    return _contacts ??= Future.wait(
      bridges.map((bridge) async {
        try {
          final contacts = await api.contacts(bridge) ?? const [];
          return [
            for (final user in contacts) BridgeContactInput(bridge, user),
          ];
        } catch (e) {
          Logs().w('Unable to list the contacts of ${bridge.name}', e);
          return const <BridgeContactInput>[];
        }
      }),
    ).then((lists) => [for (final list in lists) ...list]);
  }
}
