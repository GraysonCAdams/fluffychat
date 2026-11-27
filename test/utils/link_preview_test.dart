// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/link_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<MatrixSdkDatabase> _memoryDatabase(String name) async =>
    MatrixSdkDatabase.init(
      name,
      database: await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      ),
      sqfliteFactory: databaseFactoryFfi,
    );

void main() {
  group('fromOpenGraph', () {
    test('reads a title-only preview, the commonest bridge shape', () {
      final preview = LinkPreviewData.fromOpenGraph({
        'matched_url': 'https://example.com/a',
        'og:title': 'A page',
        'og:url': 'https://example.com/canonical',
      })!;
      expect(preview.title, 'A page');
      expect(preview.url, Uri.parse('https://example.com/canonical'));
      expect(preview.image, isNull);
    });

    test('keeps an mxc image and its size', () {
      final preview = LinkPreviewData.fromOpenGraph({
        'matched_url': 'https://example.com',
        'og:image': 'mxc://hs/abc',
        'og:image:width': 1200,
        'og:image:height': '630',
      })!;
      expect(preview.image, Uri.parse('mxc://hs/abc'));
      expect(preview.imageWidth, 1200);
      expect(preview.imageHeight, 630);
    });

    test('drops an encrypted or non-mxc image', () {
      expect(
        LinkPreviewData.fromOpenGraph({
          'matched_url': 'https://example.com',
          'og:title': 't',
          'og:image': 'mxc://hs/abc',
          'beeper:image:encryption': {'key': {}},
        })!.image,
        isNull,
      );
      expect(
        LinkPreviewData.fromOpenGraph({
          'matched_url': 'https://example.com',
          'og:title': 't',
          'og:image': 'https://cdn.example.com/a.png',
        })!.image,
        isNull,
      );
    });

    test('falls back to matched_url, then the given link', () {
      expect(
        LinkPreviewData.fromOpenGraph({
          'og:url': 'javascript:alert(1)',
          'matched_url': 'https://example.com/m',
          'og:title': 't',
        })!.url,
        Uri.parse('https://example.com/m'),
      );
      expect(
        LinkPreviewData.fromOpenGraph({
          'og:title': 't',
        }, fallbackUrl: Uri.parse('https://example.com/f'))!.url,
        Uri.parse('https://example.com/f'),
      );
    });

    test('is null with nothing to show or no link', () {
      expect(
        LinkPreviewData.fromOpenGraph({'matched_url': 'https://example.com'}),
        isNull,
      );
      expect(
        LinkPreviewData.fromOpenGraph({'og:title': ' ', 'og:description': ''}),
        isNull,
      );
      expect(LinkPreviewData.fromOpenGraph({'og:title': 'no link'}), isNull);
    });
  });

  group('firstLinkIn', () {
    test('finds the first http link and trims sentence punctuation', () {
      expect(
        firstLinkIn('look at https://example.com/a?b=1. and http://x.org'),
        Uri.parse('https://example.com/a?b=1'),
      );
      expect(
        firstLinkIn('(see https://example.com/page)'),
        Uri.parse('https://example.com/page'),
      );
    });

    test('keeps a bracket that belongs to the link', () {
      expect(
        firstLinkIn('https://en.wikipedia.org/wiki/Mercury_(planet)!'),
        Uri.parse('https://en.wikipedia.org/wiki/Mercury_(planet)'),
      );
    });

    test('is null without a link', () {
      expect(firstLinkIn('no links, just mxc://hs/a and ftp://x'), isNull);
    });
  });

  group('with a room', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = Client(
        'link preview test',
        database: await _memoryDatabase('link preview test'),
      );
      room = Room(id: '!r:hs', client: client);
    });

    Event message(Map<String, Object?> content, {Room? inRoom}) => Event(
      content: {'msgtype': 'm.text', 'body': 'https://example.com', ...content},
      type: EventTypes.Message,
      eventId: '\$e',
      senderId: '@a:hs',
      originServerTs: DateTime(2026),
      room: inRoom ?? room,
    );

    void encrypt(Room room) => room.setState(
      StrippedStateEvent(
        type: EventTypes.Encryption,
        content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
        senderId: '@a:hs',
        stateKey: '',
      ),
    );

    test('bridgeLinkPreviews tells absent from deliberately empty', () {
      expect(bridgeLinkPreviews(message({})), isNull);
      expect(bridgeLinkPreviews(message({beeperLinkPreviewsKey: []})), isEmpty);
      final previews = bridgeLinkPreviews(
        message({
          beeperLinkPreviewsKey: [
            {'matched_url': 'https://example.com', 'og:title': 'One'},
            {'matched_url': 'https://example.com'},
            'junk',
          ],
        }),
      )!;
      expect(previews.map((p) => p.title), ['One']);
    });

    test('the server is asked only in unencrypted rooms by default', () {
      bool fetch(Event e, {bool enabled = true, bool e2ee = false}) =>
          shouldFetchServerPreview(e, enabled: enabled, inEncryptedRooms: e2ee);

      expect(fetch(message({})), isTrue);
      expect(fetch(message({}), enabled: false), isFalse);
      expect(fetch(message({beeperLinkPreviewsKey: []})), isFalse);

      final secret = Room(id: '!s:hs', client: client);
      encrypt(secret);
      expect(secret.encrypted, isTrue);
      expect(fetch(message({}, inRoom: secret)), isFalse);
      expect(fetch(message({}, inRoom: secret), e2ee: true), isTrue);
    });
  });

  group('serverLinkPreview', () {
    late List<Uri> previewRequests;

    Future<Client> serverClient(http.Response Function() preview) async {
      final client = Client(
        'link preview server test',
        database: await _memoryDatabase('link preview server test'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/_matrix/client/versions') {
            return _json(200, {
              'versions': ['v1.11'],
            });
          }
          if (request.url.path == '/_matrix/client/v1/media/preview_url') {
            previewRequests.add(request.url);
            return preview();
          }
          return _json(404, {'errcode': 'M_UNRECOGNIZED'});
        }),
      );
      client.homeserver = Uri.parse('https://hs.example.com');
      client.accessToken = 'token';
      return client;
    }

    setUp(() {
      previewRequests = [];
      clearServerLinkPreviewCache();
    });

    test('reads the authenticated endpoint once per link', () async {
      final client = await serverClient(
        () => _json(200, {
          'og:title': 'Matrix',
          'og:description': 'An open network',
          'og:image': 'mxc://hs/img',
          'matrix:image:size': 1024,
        }),
      );
      final link = Uri.parse('https://matrix.org');
      final preview = (await serverLinkPreview(client, link))!;
      expect(preview.title, 'Matrix');
      expect(preview.description, 'An open network');
      expect(preview.image, Uri.parse('mxc://hs/img'));
      expect(preview.url, link);

      await serverLinkPreview(client, link);
      expect(previewRequests, hasLength(1));
      expect(previewRequests.single.queryParameters['url'], link.toString());
    });

    test('a failing server gives no preview instead of an error', () async {
      final client = await serverClient(
        () => _json(500, {'errcode': 'M_UNKNOWN', 'error': 'boom'}),
      );
      expect(
        await serverLinkPreview(client, Uri.parse('https://example.com')),
        isNull,
      );
    });
  });
}
