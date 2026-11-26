// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = '/_matrix/client/unstable/net.graysons.bridge';

Map<String, Object?> _whoami(String id, String name) => {
  'network': {
    'displayname': name,
    'network_url': 'https://example.com',
    'network_icon': 'mxc://example.com/$id',
    'network_id': id,
    'beeper_bridge_type': id,
  },
  'login_flows': [],
  'bridge_bot': '@${id}bot:hs',
  'logins': [
    {'id': 'login-$id', 'state': 'CONNECTED', 'space_room': '!space-$id:hs'},
  ],
};

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> requests;

  BridgeProvisioning api(
    Future<http.Response> Function(http.Request) handler, {
    List<String> bridges = provisionedBridgeNames,
  }) => BridgeProvisioning(
    httpClient: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    homeserver: Uri.parse('https://matrix.example.com'),
    accessToken: 'token',
    userId: '@me:example.com',
    bridgeNames: bridges,
  );

  setUp(() => requests = []);

  const gmessages = BridgeInfo(
    name: 'gmessages',
    networkId: 'gmessages',
    displayName: 'Google Messages',
    icon: null,
    loginId: 'login-gm',
  );

  test('requests carry the token, user_id and the proxied path', () async {
    await api(
      (_) async => _json(200, _whoami('imessage', 'iMessage')),
    ).whoami('imessage');
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '$_base/imessage/v3/whoami');
    expect(request.url.queryParameters['user_id'], '@me:example.com');
    expect(request.headers['Authorization'], 'Bearer token');
  });

  test('whoami reads the network and the first login', () async {
    final info = await api(
      (_) async => _json(200, _whoami('imessage', 'iMessage')),
    ).whoami('imessage');
    expect(info!.displayName, 'iMessage');
    expect(info.networkId, 'imessage');
    expect(info.icon, Uri.parse('mxc://example.com/imessage'));
    expect(info.loginId, 'login-imessage');
    expect(info.spaceRoomId, '!space-imessage:hs');
    expect(info.bridgeBot, '@imessagebot:hs');
  });

  test('whoami without a login is null', () async {
    final info = await api(
      (_) async => _json(200, {..._whoami('xbox', 'Xbox'), 'logins': []}),
    ).whoami('xbox');
    expect(info, isNull);
  });

  test('discover skips failing and unknown bridges, keeping order', () async {
    final bridges = await api((request) async {
      final name = request.url.pathSegments[4];
      return switch (name) {
        'imessage' => _json(200, _whoami('imessage', 'iMessage')),
        'gmessages' => _json(200, _whoami('gmessages', 'Google Messages')),
        'telegram' => http.Response('Bad gateway', 502),
        'linkedin' => throw http.ClientException('connection refused'),
        _ => http.Response('404 page not found', 404),
      };
    }).discover();
    expect(bridges.map((b) => b.name), ['imessage', 'gmessages']);
  });

  test('contacts parses the list and sends login_id', () async {
    final contacts = await api(
      (_) async => _json(200, {
        'contacts': [
          {
            'id': 'c1',
            'name': 'Alice',
            'identifiers': ['tel:+14045551234'],
            'mxid': '@gmessages_1.1:hs',
          },
          {'name': 'no id'},
        ],
      }),
    ).contacts(gmessages);
    expect(contacts, hasLength(1));
    expect(contacts!.single.name, 'Alice');
    expect(contacts.single.identifiers, ['tel:+14045551234']);
    expect(contacts.single.mxid, '@gmessages_1.1:hs');
    expect(requests.single.url.path, '$_base/gmessages/v3/contacts');
    expect(requests.single.url.queryParameters['login_id'], 'login-gm');
  });

  test('contacts is null when the bridge cannot list them', () async {
    final contacts = await api(
      (_) async => _json(404, {
        'errcode': 'M_UNRECOGNIZED',
        'error': 'This bridge does not support listing contacts',
      }),
    ).contacts(gmessages);
    expect(contacts, isNull);
  });

  test('other contacts errors are thrown', () async {
    expect(
      api(
        (_) async => _json(500, {'errcode': 'M_UNKNOWN', 'error': 'boom'}),
      ).contacts(gmessages),
      throwsA(
        isA<BridgeProvisioningException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.errcode, 'errcode', 'M_UNKNOWN'),
      ),
    );
  });

  test('resolve_identifier escapes the identifier and reads the DM', () async {
    final user = await api(
      (_) async => _json(200, {
        'id': '1.2',
        'name': 'Bob',
        'mxid': '@gmessages_1.2:hs',
        'dm_room_mxid': '!dm:hs',
      }),
    ).resolveIdentifier(gmessages, '+14045551234');
    expect(user!.dmRoomId, '!dm:hs');
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.pathSegments.sublist(4), [
      'gmessages',
      'v3',
      'resolve_identifier',
      '+14045551234',
    ]);
    expect(request.url.toString(), contains('resolve_identifier/%2B1404'));
  });

  test('resolve_identifier is null for an unknown identifier', () async {
    final user = await api(
      (_) async => _json(404, {
        'errcode': 'M_NOT_FOUND',
        'error': 'Identifier not found',
      }),
    ).resolveIdentifier(gmessages, '+14045551234');
    expect(user, isNull);
  });

  test('create_dm posts and returns dm_room_mxid', () async {
    final roomId = await api(
      (_) async => _json(201, {'id': '1.2', 'dm_room_mxid': '!new:hs'}),
    ).createDm(gmessages, '@gmessages_1.2:hs');
    expect(roomId, '!new:hs');
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.pathSegments.sublist(6), [
      'create_dm',
      '@gmessages_1.2:hs',
    ]);
    expect(request.url.queryParameters['login_id'], 'login-gm');
  });

  test('create_dm without a room ID is an error', () async {
    expect(
      api((_) async => _json(200, {'id': '1.2'})).createDm(gmessages, 'x'),
      throwsA(isA<BridgeProvisioningException>()),
    );
  });

  test('capabilities lists the group types the bridge creates', () async {
    // The answer of mautrix-gmessages v0.2611.0.
    final types = await api(
      (_) async => _json(200, {
        'resolve_identifier': {'create_dm': true, 'lookup_phone': true},
        'group_creation': {
          'group': {
            'type_description': 'mms/rcs group',
            'name': {'allowed': true},
            'username': {'allowed': false},
            'avatar': {'allowed': false},
            'topic': {'allowed': false},
            'disappear': {'allowed': false},
            'participants': {
              'allowed': true,
              'required': true,
              'min_length': 2,
            },
            'parent': {'allowed': false},
          },
        },
      }),
    ).groupTypes(gmessages);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '$_base/gmessages/v3/capabilities');
    final type = types.single;
    expect(type.id, 'group');
    expect(type.description, 'mms/rcs group');
    expect(type.nameAllowed, isTrue);
    expect(type.nameRequired, isFalse);
    expect(type.minParticipants, 2);
    expect(type.maxParticipants, 0);
  });

  test('capabilities without group_creation creates no groups', () async {
    final types = await api(
      (_) async => _json(200, {'resolve_identifier': <String, Object?>{}}),
    ).groupTypes(gmessages);
    expect(types, isEmpty);
  });

  test('create_group posts the participants and name to its type', () async {
    final created =
        await api(
          (_) async => _json(200, {
            'id': 'portal-1',
            'mxid': '!group:hs',
            'failed_participants': {
              '+13125550188': {'reason': 'not reachable'},
            },
          }),
        ).createGroup(
          gmessages,
          const BridgeGroupType(id: 'group', nameAllowed: true),
          participants: ['1.2', '+13125550188'],
          name: 'Trip',
        );
    expect(created.roomId, '!group:hs');
    expect(created.failedParticipants, {'+13125550188': 'not reachable'});
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '$_base/gmessages/v3/create_group/group');
    expect(request.url.queryParameters['login_id'], 'login-gm');
    expect(request.url.queryParameters['user_id'], '@me:example.com');
    expect(request.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(request.body), {
      'participants': ['1.2', '+13125550188'],
      'name': {'name': 'Trip'},
    });
  });

  test('create_group leaves out an empty name', () async {
    await api((_) async => _json(200, {'mxid': '!group:hs'})).createGroup(
      gmessages,
      const BridgeGroupType(id: 'group'),
      participants: ['1.2', '1.3'],
      name: '',
    );
    expect(jsonDecode(requests.single.body), {
      'participants': ['1.2', '1.3'],
    });
  });

  test('create_group without a room ID is an error', () async {
    expect(
      api((_) async => _json(200, {'id': 'portal-1'})).createGroup(
        gmessages,
        const BridgeGroupType(id: 'group'),
        participants: ['1.2', '1.3'],
      ),
      throwsA(isA<BridgeProvisioningException>()),
    );
  });
}
