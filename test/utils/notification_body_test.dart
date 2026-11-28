// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/notification_body.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

void main() {
  late Room room;
  late L10n l10n;

  setUpAll(() async {
    final client = await createSearchTestClient();
    room = client.getRoomById('!726s6s6q:example.com')!;
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Event event(
    Map<String, Object?> content, {
    String sender = '@gmessages_15551234567:example.com',
  }) => Event(
    content: content,
    type: EventTypes.Message,
    eventId: r'$e',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    room: room,
  );

  test('a bridge placeholder notifies as the photo it stands for', () {
    expect(
      notificationBodyOf(
        event({
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_1.jpg',
          'fi.mau.gmessages.media_pending': true,
        }),
        l10n,
      ),
      'Photo',
    );
  });

  test('a bridge placeholder for a video notifies as Video', () {
    expect(
      notificationBodyOf(
        event({
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_2.mp4',
          'fi.mau.gmessages.media_pending': true,
        }),
        l10n,
      ),
      'Video',
    );
  });

  test('a failed transfer, also when it is an edit, says so', () {
    expect(
      notificationBodyOf(
        event({
          'msgtype': MessageTypes.Notice,
          'body': 'Failed to transfer attachment PXL_3.jpg',
        }),
        l10n,
      ),
      "Photo didn't arrive",
    );
    expect(
      notificationBodyOf(
        event({
          'msgtype': MessageTypes.Notice,
          'body': '* Failed to transfer attachment PXL_3.jpg',
          'm.new_content': {
            'msgtype': MessageTypes.Notice,
            'body': 'Failed to transfer attachment PXL_3.jpg',
          },
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$p'},
        }),
        l10n,
      ),
      "Photo didn't arrive",
    );
  });

  test('the same notice from anyone else is its text', () {
    expect(
      notificationBodyOf(
        event({
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_1.jpg',
        }, sender: '@whatsappbot:example.com'),
        l10n,
      ),
      'Waiting for attachment PXL_1.jpg',
    );
  });
}
