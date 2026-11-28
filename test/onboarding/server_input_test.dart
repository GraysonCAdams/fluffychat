// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/sign_in_flows/server_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerInput.parse', () {
    test('a bare server name becomes an https address', () {
      final input = ServerInput.parse(' d.graysons.network ')!;
      expect(input.homeserver, Uri.https('d.graysons.network', ''));
      expect(input.username, isNull);
      expect(input.label, 'd.graysons.network');
    });

    test('a Matrix ID gives its server and the username', () {
      final input = ServerInput.parse('@gray:d.graysons.network')!;
      expect(input.homeserver, Uri.https('d.graysons.network', ''));
      expect(input.username, 'gray');
      expect(input.matrixId, '@gray:d.graysons.network');
      expect(input.label, 'd.graysons.network');
    });

    test('a full address keeps its scheme and port', () {
      final input = ServerInput.parse('http://localhost:8008')!;
      expect(input.homeserver, Uri.parse('http://localhost:8008'));
      expect(input.label, 'localhost:8008');
    });

    test('a server name with a port', () {
      final input = ServerInput.parse('matrix.example.org:8448')!;
      expect(input.homeserver, Uri.parse('https://matrix.example.org:8448'));
    });

    test('half-typed or empty input is not a server yet', () {
      for (final text in ['', '  ', 'd', 'd.', '@gray', '@gray:', 'a b.org']) {
        expect(ServerInput.parse(text), isNull, reason: text);
      }
    });
  });
}
