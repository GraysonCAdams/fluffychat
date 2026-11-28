// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/edited_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

void main() {
  late Room room;

  setUpAll(() async {
    final client = await createSearchTestClient();
    room = client.getRoomById('!726s6s6q:example.com')!;
  });

  /// An m.replace edit of `$placeholder`, as mautrix-gmessages sends one
  /// when the attachment it was waiting for arrives.
  Event edit(String id, {Object? dontRender}) => Event(
    content: {
      'msgtype': MessageTypes.Image,
      'body': '* IMG.jpg',
      'm.new_content': {
        'msgtype': MessageTypes.Image,
        'body': 'IMG.jpg',
        'url': 'mxc://example.com/photo',
      },
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': r'$placeholder',
      },
      'com.beeper.dont_render_edited': ?dontRender,
    },
    type: EventTypes.Message,
    eventId: id,
    senderId: '@gmessages_1:example.com',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    room: room,
  );

  test('an ordinary edit shows the edited mark', () {
    expect(editShowsEditedMark(edit(r'$e1')), isTrue);
    expect(showsEditedMark([edit(r'$e1')]), isTrue);
  });

  test('a bridge edit flagged dont_render_edited does not', () {
    final flagged = edit(r'$e1', dontRender: true);
    expect(editShowsEditedMark(flagged), isFalse);
    expect(showsEditedMark([flagged]), isFalse);
  });

  test('only a true flag hides the mark', () {
    expect(editShowsEditedMark(edit(r'$e1', dontRender: false)), isTrue);
    expect(editShowsEditedMark(edit(r'$e1', dontRender: 'true')), isTrue);
  });

  test('a later edit by the sender brings the mark back', () {
    expect(
      showsEditedMark([edit(r'$e1', dontRender: true), edit(r'$e2')]),
      isTrue,
    );
  });

  test('a message without edits shows no mark', () {
    expect(showsEditedMark(const []), isFalse);
  });
}
