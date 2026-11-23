// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:flutter_test/flutter_test.dart';

const imessage = '!imessage:x';
const sms = '!sms:x';
const telegram = '!telegram:x';

SendRouter router({
  SendMode mode = SendMode.preferred,
  String? lastReceived,
  String? oneOff,
}) => SendRouter(
  roomIds: const [imessage, sms, telegram],
  sendVia: imessage,
  sendMode: mode,
  lastReceivedRoomId: lastReceived,
  oneOffRoomId: oneOff,
);

void main() {
  const newActions = [
    SendAction.message,
    SendAction.attachment,
    SendAction.voiceMessage,
    SendAction.sticker,
    SendAction.location,
    SendAction.poll,
    SendAction.typing,
  ];
  const eventActions = [
    SendAction.reply,
    SendAction.threadReply,
    SendAction.reaction,
    SendAction.edit,
    SendAction.redaction,
    SendAction.pin,
    SendAction.readReceipt,
  ];

  test('every action is classified', () {
    expect({...newActions, ...eventActions}, SendAction.values.toSet());
    for (final action in newActions) {
      expect(action.actsOnEvent, isFalse, reason: '$action');
    }
    for (final action in eventActions) {
      expect(action.actsOnEvent, isTrue, reason: '$action');
    }
  });

  group('something new goes to the target network', () {
    for (final action in newActions) {
      test('$action uses send_via', () {
        expect(router().route(action), imessage);
      });
      test('$action uses a one-off pick', () {
        expect(router(oneOff: telegram).route(action), telegram);
      });
      test('$action ignores a related event room', () {
        // Even when a caller passes one, a new message is not tied to it.
        expect(router().route(action, eventRoomId: sms), imessage);
      });
    }
  });

  group('acting on a message goes to that message\'s network', () {
    for (final action in eventActions) {
      test('$action stays on the event\'s room over send_via', () {
        expect(router().route(action, eventRoomId: sms), sms);
      });
      test('$action stays on the event\'s room over a one-off pick', () {
        expect(router(oneOff: telegram).route(action, eventRoomId: sms), sms);
      });
      test('$action stays on the event\'s room over last received', () {
        expect(
          router(
            mode: SendMode.lastReceived,
            lastReceived: telegram,
          ).route(action, eventRoomId: imessage),
          imessage,
        );
      });
      test('$action without the event\'s room is an error', () {
        expect(() => router().route(action), throwsArgumentError);
      });
    }
  });

  group('target for new messages', () {
    test('preferred mode ignores where they last wrote', () {
      expect(router(lastReceived: sms).newMessageRoomId, imessage);
    });
    test('last received mode follows them', () {
      expect(
        router(mode: SendMode.lastReceived, lastReceived: sms).newMessageRoomId,
        sms,
      );
    });
    test('last received mode before they ever wrote uses send_via', () {
      expect(router(mode: SendMode.lastReceived).newMessageRoomId, imessage);
    });
    test('a one-off pick beats last received', () {
      expect(
        router(
          mode: SendMode.lastReceived,
          lastReceived: sms,
          oneOff: telegram,
        ).newMessageRoomId,
        telegram,
      );
    });
    test('a pick or send_via outside the contact is ignored', () {
      expect(router(oneOff: '!elsewhere:x').newMessageRoomId, imessage);
      expect(
        SendRouter(
          roomIds: const [sms, telegram],
          sendVia: imessage,
        ).newMessageRoomId,
        sms,
      );
    });
    test('clearing the one-off pick goes back to the default', () {
      final picked = router(oneOff: telegram);
      expect(
        picked.copyWith(oneOffRoomId: () => null).newMessageRoomId,
        imessage,
      );
    });
    test('a single room sends everything there', () {
      final single = SendRouter.single(sms);
      expect(single.isMerged, isFalse);
      expect(single.route(SendAction.message), sms);
      expect(single.composerTarget(), const SendTarget(sms));
    });
    test('built from a stored contact', () {
      const contact = MergedContactEntry(
        id: 'c',
        rooms: [imessage, sms],
        sendVia: sms,
        updated: 1,
        sendMode: SendMode.lastReceived,
      );
      expect(SendRouter.contact(contact).newMessageRoomId, sms);
      expect(
        SendRouter.contact(
          contact,
          lastReceivedRoomId: imessage,
        ).newMessageRoomId,
        imessage,
      );
    });
  });

  group('the composer and the send-via button', () {
    test('a plain message is not locked', () {
      expect(router(oneOff: sms).composerTarget(), const SendTarget(sms));
    });
    test('replying shows the reply\'s network, locked', () {
      expect(
        router(oneOff: telegram).composerTarget(replyRoomId: sms),
        const SendTarget(sms, locked: true),
      );
    });
    test('editing uses the edited message\'s network, locked', () {
      expect(
        router().composerTarget(editRoomId: telegram, replyRoomId: sms),
        const SendTarget(telegram, locked: true),
      );
    });
    test('a thread reply goes to the thread\'s network, locked', () {
      expect(
        router().composerTarget(threadRoomId: sms),
        const SendTarget(sms, locked: true),
      );
    });
  });

  test('next network for a failed send', () {
    expect(router().nextRoomAfter(imessage), sms);
    expect(router().nextRoomAfter(telegram), imessage);
    expect(SendRouter.single(sms).nextRoomAfter(sms), isNull);
  });

  group('fallback offer on a failed send', () {
    const text = {'msgtype': 'm.text', 'body': 'hi'};
    test('off unless the contact turned it on', () {
      expect(
        router().fallbackRoomFor(
          failedRoomId: imessage,
          content: text,
          enabled: false,
        ),
        isNull,
      );
    });
    test('offers the next network in the contact\'s order', () {
      expect(
        router().fallbackRoomFor(
          failedRoomId: imessage,
          content: text,
          enabled: true,
        ),
        sms,
      );
      expect(
        router().fallbackRoomFor(
          failedRoomId: telegram,
          content: text,
          enabled: true,
        ),
        imessage,
      );
    });
    test('never moves a reply, thread reply or edit', () {
      for (final content in [
        {
          ...text,
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$x'},
          },
        },
        {
          ...text,
          'm.relates_to': {'rel_type': 'm.thread', 'event_id': r'$x'},
        },
        {
          ...text,
          'm.new_content': text,
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$x'},
        },
      ]) {
        expect(
          router().fallbackRoomFor(
            failedRoomId: imessage,
            content: content,
            enabled: true,
          ),
          isNull,
          reason: '$content',
        );
      }
    });
    test('a single room has nowhere to fall back to', () {
      expect(
        SendRouter.single(
          sms,
        ).fallbackRoomFor(failedRoomId: sms, content: text, enabled: true),
        isNull,
      );
    });
  });
}
