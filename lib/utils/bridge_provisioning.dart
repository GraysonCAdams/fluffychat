// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// A client for the provisioning API of the user's own mautrix bridges
/// (bridgev2, `/_matrix/provision/v3`), which the homeserver's front end
/// proxies at `{homeserver}/_matrix/client/unstable/net.graysons.bridge/
/// {name}/v3/...`.
///
/// Requests carry the user's Matrix access token and `user_id`; the bridge
/// checks the token against the homeserver itself. Plain Dart over
/// `package:http`, so it is tested with a fake HTTP client.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The bridges asked for, by the name the proxy routes on. A bridge that is
/// not installed answers `whoami` with an error and is skipped.
const List<String> provisionedBridgeNames = [
  'imessage',
  'gmessages',
  'telegram',
  'linkedin',
  'xbox',
];

/// An error answer from a bridge, or a request that never got one.
class BridgeProvisioningException implements Exception {
  final String bridge;

  /// The HTTP status, or null when the request itself failed.
  final int? statusCode;

  /// The Matrix error code from the body, such as `M_NOT_FOUND`.
  final String? errcode;
  final String? error;

  const BridgeProvisioningException(
    this.bridge, {
    this.statusCode,
    this.errcode,
    this.error,
  });

  @override
  String toString() =>
      'BridgeProvisioningException($bridge, $statusCode, $errcode: $error)';
}

/// What a bridge said when it failed to answer: its error message, else its
/// error code, else the HTTP status; for anything else, the error itself.
String bridgeErrorReason(Object error) {
  if (error is BridgeProvisioningException) {
    final status = error.statusCode;
    return error.error ??
        error.errcode ??
        (status == null ? error.toString() : 'HTTP $status');
  }
  return error.toString();
}

/// One bridge the user is logged in to, from its `whoami`.
class BridgeInfo {
  /// The proxy name, one of [provisionedBridgeNames].
  final String name;

  /// `network.network_id`, such as `imessage` or `gmessages`.
  final String networkId;

  /// `network.displayname`, such as "iMessage".
  final String displayName;

  /// `network.network_icon`, an `mxc://` URI.
  final Uri? icon;

  /// The first login's `id`, sent as `login_id` on later calls.
  final String loginId;

  /// The first login's `space_room`: the space the bridge puts its chats in.
  final String? spaceRoomId;

  /// `bridge_bot`: the bridge bot's Matrix ID, which its rooms name as
  /// `bridgebot` in their `m.bridge` state.
  final String? bridgeBot;

  const BridgeInfo({
    required this.name,
    required this.networkId,
    required this.displayName,
    required this.icon,
    required this.loginId,
    this.spaceRoomId,
    this.bridgeBot,
  });

  /// Reads a `whoami` body. Null when it has no network or no login, since
  /// such a bridge cannot start chats.
  static BridgeInfo? fromWhoami(String name, Map<String, Object?> json) {
    final network = json['network'];
    final logins = json['logins'];
    if (network is! Map || logins is! List || logins.isEmpty) return null;
    final login = logins.first;
    if (login is! Map) return null;
    final loginId = login['id'];
    if (loginId is! String || loginId.isEmpty) return null;
    final icon = network['network_icon'];
    final space = login['space_room'];
    final bot = json['bridge_bot'];
    return BridgeInfo(
      name: name,
      networkId: network['network_id'] as String? ?? name,
      displayName: network['displayname'] as String? ?? name,
      icon: icon is String && icon.isNotEmpty ? Uri.tryParse(icon) : null,
      loginId: loginId,
      spaceRoomId: space is String && space.isNotEmpty ? space : null,
      bridgeBot: bot is String && bot.isNotEmpty ? bot : null,
    );
  }
}

/// A person on a bridge's network: an entry of `contacts`, or the answer of
/// `resolve_identifier` and `create_dm` (`RespResolveIdentifier` in
/// mautrix-go).
class BridgeUser {
  /// The remote network's user ID.
  final String id;
  final String? name;
  final Uri? avatarUrl;

  /// URIs such as `tel:+14045551234` or `mailto:bob@example.com`.
  final List<String> identifiers;

  /// The bridge ghost's Matrix ID.
  final String? mxid;

  /// The direct chat with this person, when one exists (`dm_room_mxid`).
  final String? dmRoomId;

  const BridgeUser({
    required this.id,
    this.name,
    this.avatarUrl,
    this.identifiers = const [],
    this.mxid,
    this.dmRoomId,
  });

  static BridgeUser? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    String? string(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final avatar = string('avatar_url');
    final identifiers = json['identifiers'];
    return BridgeUser(
      id: id,
      name: string('name'),
      avatarUrl: avatar == null ? null : Uri.tryParse(avatar),
      identifiers: identifiers is List
          ? identifiers.whereType<String>().toList()
          : const [],
      mxid: string('mxid'),
      dmRoomId: string('dm_room_mxid'),
    );
  }
}

/// What a bridge can look a person up by in `resolve_identifier`.
class BridgeLookups {
  /// Whether it takes a phone number: `lookup_phone`, or `any_phone` for a
  /// network that reaches any number without a lookup.
  final bool phone;

  /// Whether it takes an email address (`lookup_email`).
  final bool email;

  const BridgeLookups({required this.phone, required this.email});

  /// The networks known to take phone numbers, by bridge name or network
  /// ID, for a bridge that does not declare its lookups.
  static const phoneNetworks = {
    'imessage',
    'gmessages',
    'signal',
    'whatsapp',
    'telegram',
  };

  /// The networks known to take email addresses, likewise.
  static const emailNetworks = {'imessage'};

  /// From `resolve_identifier` in a bridge's `GET /v3/capabilities`
  /// (`ResolveIdentifierCapabilities` in mautrix-go). Null when it declares
  /// no way to look anyone up, as a bridge that predates the field does.
  static BridgeLookups? fromCapabilities(Map<String, Object?> json) {
    final lookups = json['resolve_identifier'];
    if (lookups is! Map) return null;
    bool flag(String key) => lookups[key] == true;
    final phone = flag('lookup_phone') || flag('any_phone');
    final email = flag('lookup_email');
    if (!phone && !email && !flag('lookup_username')) return null;
    return BridgeLookups(phone: phone, email: email);
  }

  /// What [bridge] is known to take, by its name or network ID.
  static BridgeLookups knownFor(BridgeInfo bridge) {
    bool known(Set<String> networks) =>
        networks.contains(bridge.name) || networks.contains(bridge.networkId);
    return BridgeLookups(
      phone: known(phoneNetworks),
      email: known(emailNetworks),
    );
  }
}

/// The kinds of group in a bridge's [capabilities] (`group_creation`).
/// Empty when it creates none.
List<BridgeGroupType> groupTypesOf(Map<String, Object?> capabilities) {
  final types = capabilities['group_creation'];
  if (types is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in types.entries)
      if (key is String) BridgeGroupType.fromJson(key, value),
  ];
}

/// Whether [error], from `resolve_identifier`, says the bridge cannot take
/// that kind of identifier at all (such as a phone number on a network of
/// usernames), which means the person is not reachable there rather than
/// that the bridge failed to answer.
bool bridgeRejectsIdentifier(Object error) {
  if (error is! BridgeProvisioningException) return false;
  final text = '${error.errcode ?? ''} ${error.error ?? ''}'.toLowerCase();
  return RegExp(
    r'(invalid|unsupported|not supported|unrecognized)[^.]*identifier'
    r'|identifier[^.]*(invalid|not supported|unsupported)'
    r'|invalid (phone|email|user ?name)',
  ).hasMatch(text);
}

/// One kind of group a bridge can create: an entry of `group_creation` in
/// its `GET /v3/capabilities` (`GroupTypeCapabilities` in mautrix-go).
class BridgeGroupType {
  /// The key in `group_creation`, sent as `{type}` in `create_group`.
  final String id;

  /// `type_description`, such as "mms/rcs group".
  final String? description;

  /// Whether the create request may carry a name (`name.allowed`), and
  /// whether it must (`name.required`).
  final bool nameAllowed;
  final bool nameRequired;

  /// How many people the group needs besides the user
  /// (`participants.min_length`), and at most (`participants.max_length`,
  /// 0 for no limit).
  final int minParticipants;
  final int maxParticipants;

  const BridgeGroupType({
    required this.id,
    this.description,
    this.nameAllowed = false,
    this.nameRequired = false,
    this.minParticipants = 0,
    this.maxParticipants = 0,
  });

  static BridgeGroupType fromJson(String id, Object? json) {
    final map = json is Map ? json : const {};
    Map field(String key) => map[key] is Map ? map[key] as Map : const {};
    int number(Map field, String key) {
      final value = field[key];
      return value is int ? value : 0;
    }

    final name = field('name');
    final participants = field('participants');
    final description = map['type_description'];
    return BridgeGroupType(
      id: id,
      description: description is String && description.isNotEmpty
          ? description
          : null,
      nameAllowed: name['allowed'] == true,
      nameRequired: name['required'] == true,
      minParticipants: number(participants, 'min_length'),
      maxParticipants: number(participants, 'max_length'),
    );
  }
}

/// The answer of `create_group` (`RespCreateGroup` in mautrix-go).
class CreatedGroup {
  /// The new room (`mxid`).
  final String roomId;

  /// The people the network could not add, by network user ID, with the
  /// bridge's reason (`failed_participants`).
  final Map<String, String> failedParticipants;

  const CreatedGroup(this.roomId, {this.failedParticipants = const {}});
}

class BridgeProvisioning {
  final http.Client httpClient;
  final Uri homeserver;
  final String accessToken;
  final String userId;
  final List<String> bridgeNames;

  const BridgeProvisioning({
    required this.httpClient,
    required this.homeserver,
    required this.accessToken,
    required this.userId,
    this.bridgeNames = provisionedBridgeNames,
  });

  static const Duration timeout = Duration(seconds: 20);

  Uri _url(
    String bridge,
    List<String> path, [
    Map<String, String> query = const {},
  ]) => homeserver.replace(
    // Every segment is fully escaped, `+` included, so a phone number
    // reaches the bridge as written whatever decodes the path on the way.
    path: [
      ...homeserver.pathSegments.where((segment) => segment.isNotEmpty),
      '_matrix',
      'client',
      'unstable',
      'net.graysons.bridge',
      bridge,
      'v3',
      ...path,
    ].map(Uri.encodeComponent).join('/'),
    queryParameters: {'user_id': userId, ...query},
  );

  Future<Map<String, Object?>> _send(
    String bridge,
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Object? body,
  }) async {
    final http.Response response;
    try {
      final request = http.Request(method, _url(bridge, path, query))
        ..headers['Authorization'] = 'Bearer $accessToken';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      response = await http.Response.fromStream(
        await httpClient.send(request).timeout(timeout),
      ).timeout(timeout);
    } catch (e) {
      throw BridgeProvisioningException(bridge, error: e.toString());
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      json = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (json is Map<String, Object?>) return json;
      throw BridgeProvisioningException(
        bridge,
        statusCode: response.statusCode,
        error: 'Response is not a JSON object',
      );
    }
    throw BridgeProvisioningException(
      bridge,
      statusCode: response.statusCode,
      errcode: json is Map ? json['errcode'] as String? : null,
      error: json is Map ? json['error'] as String? : null,
    );
  }

  /// `GET /v3/whoami` of [bridge]. Null when it has no login.
  Future<BridgeInfo?> whoami(String bridge) async =>
      BridgeInfo.fromWhoami(bridge, await _send(bridge, 'GET', ['whoami']));

  /// Every bridge in [bridgeNames] the user is logged in to, in that order.
  /// Bridges whose `whoami` fails are left out.
  Future<List<BridgeInfo>> discover() async {
    final results = await Future.wait(
      bridgeNames.map((name) async {
        try {
          return await whoami(name);
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<BridgeInfo>().toList();
  }

  /// `GET /v3/contacts`. Null when the bridge cannot list contacts (it
  /// answers `M_UNRECOGNIZED`, as the iMessage bridge does).
  Future<List<BridgeUser>?> contacts(BridgeInfo bridge) async {
    final Map<String, Object?> json;
    try {
      json = await _send(
        bridge.name,
        'GET',
        ['contacts'],
        query: {'login_id': bridge.loginId},
      );
    } on BridgeProvisioningException catch (e) {
      if (e.errcode == 'M_UNRECOGNIZED') return null;
      rethrow;
    }
    final list = json['contacts'];
    if (list is! List) return const [];
    return list.map(BridgeUser.fromJson).whereType<BridgeUser>().toList();
  }

  /// `GET /v3/resolve_identifier/{identifier}`: whether [identifier] (a
  /// phone number, email, network user ID or ghost Matrix ID) is reachable
  /// on [bridge]. Null when the bridge does not know it (`M_NOT_FOUND`).
  /// Does not start a chat.
  Future<BridgeUser?> resolveIdentifier(
    BridgeInfo bridge,
    String identifier,
  ) async {
    try {
      return BridgeUser.fromJson(
        await _send(
          bridge.name,
          'GET',
          ['resolve_identifier', identifier],
          query: {'login_id': bridge.loginId},
        ),
      );
    } on BridgeProvisioningException catch (e) {
      if (e.errcode == 'M_NOT_FOUND') return null;
      rethrow;
    }
  }

  /// `POST /v3/create_dm/{identifier}`: starts a direct chat with
  /// [identifier] on [bridge], or finds the existing one, and returns its
  /// room ID (`dm_room_mxid`).
  Future<String> createDm(BridgeInfo bridge, String identifier) async {
    final json = await _send(
      bridge.name,
      'POST',
      ['create_dm', identifier],
      query: {'login_id': bridge.loginId},
      body: const <String, Object?>{},
    );
    final roomId = BridgeUser.fromJson(json)?.dmRoomId;
    if (roomId == null) {
      throw BridgeProvisioningException(
        bridge.name,
        error: 'create_dm returned no dm_room_mxid',
      );
    }
    return roomId;
  }

  /// `GET /v3/capabilities`: what [bridge] can do through this API
  /// (`ProvisioningCapabilities` in mautrix-go).
  Future<Map<String, Object?>> capabilities(BridgeInfo bridge) =>
      _send(bridge.name, 'GET', ['capabilities']);

  /// The kinds of group [bridge] can create, from `GET /v3/capabilities`
  /// (`group_creation`). Empty when it creates none.
  Future<List<BridgeGroupType>> groupTypes(BridgeInfo bridge) async =>
      groupTypesOf(await capabilities(bridge));

  /// `POST /v3/create_group/{type}`: creates a group of [type] with
  /// [participants] (network user IDs, as `resolve_identifier` answers
  /// them in `id`) on [bridge], named [name] when given.
  Future<CreatedGroup> createGroup(
    BridgeInfo bridge,
    BridgeGroupType type, {
    required List<String> participants,
    String? name,
  }) async {
    final json = await _send(
      bridge.name,
      'POST',
      ['create_group', type.id],
      query: {'login_id': bridge.loginId},
      body: <String, Object?>{
        'participants': participants,
        if (name != null && name.isNotEmpty) 'name': {'name': name},
      },
    );
    final roomId = json['mxid'];
    if (roomId is! String || roomId.isEmpty) {
      throw BridgeProvisioningException(
        bridge.name,
        error: 'create_group returned no mxid',
      );
    }
    final failed = json['failed_participants'];
    return CreatedGroup(
      roomId,
      failedParticipants: {
        if (failed is Map)
          for (final MapEntry(:key, :value) in failed.entries)
            if (key is String)
              key: value is Map && value['reason'] is String
                  ? value['reason'] as String
                  : '',
      },
    );
  }
}
