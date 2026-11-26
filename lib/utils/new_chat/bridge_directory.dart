// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:matrix/matrix.dart';

/// The user's bridges, their contact lists, the groups they create and
/// what they look people up by, for New Chat, one per client. Bridges and
/// contacts are kept for [lifetime] so reopening New Chat does not ask
/// every bridge again.
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

  final Map<String, Future<Map<String, Object?>?>> _capabilities = {};

  /// [bridge]'s capabilities, asked once per directory; null when they
  /// cannot be read, which is asked again next time.
  Future<Map<String, Object?>?> _capabilitiesOf(BridgeInfo bridge) =>
      _capabilities[bridge.name] ??= api
          .capabilities(bridge)
          .then<Map<String, Object?>?>((json) => json)
          .catchError((Object e) {
            Logs().w('Unable to read the capabilities of ${bridge.name}', e);
            _capabilities.remove(bridge.name);
            return null;
          });

  /// The kinds of group [bridge] can create. A bridge whose capabilities
  /// cannot be read creates none.
  Future<List<BridgeGroupType>> groupTypes(BridgeInfo bridge) async {
    final capabilities = await _capabilitiesOf(bridge);
    return capabilities == null ? const [] : groupTypesOf(capabilities);
  }

  /// What [bridge] can look a person up by: what its capabilities
  /// declare, else what its network is known to take.
  Future<BridgeLookups> lookups(BridgeInfo bridge) async {
    final capabilities = await _capabilitiesOf(bridge);
    return (capabilities == null
            ? null
            : BridgeLookups.fromCapabilities(capabilities)) ??
        BridgeLookups.knownFor(bridge);
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
