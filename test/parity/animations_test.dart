// SPDX-FileCopyrightText: 2026 Grayson Adams
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// Records the animations the website reproduces, from the app's real
/// widgets, into `anim/<name>.json` and `anim/<name>.png`.
/// `--update-goldens` rewrites them; without it the measurements are
/// checked against the files. See README.md in this folder.
library;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/input_bar.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'anim_recorder.dart';
import 'harness.dart';
import 'screens/chat.dart';
import 'screens/chat_list.dart';

const _timeout = Timeout(Duration(minutes: 3));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadParityFonts);

  for (final size in [8.0, 4.0]) {
    testWidgets('typing-dots-${size.round()}', (tester) async {
      final fixture = ParityFixture.load('chat-dm');
      setUpParityView(tester, fixture);
      final prefs = await setUpParitySettings(fixture);
      final client = (await tester.runAsync(
        () => ParityClient.create('parity dots $size'),
      ))!;
      addTearDown(() => _dispose(client));
      // The app shell first, settled; then the animation mounts in it.
      final shown = ValueNotifier(false);
      addTearDown(shown.dispose);
      await pumpParityApp(
        tester,
        client: client,
        prefs: prefs,
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (context, show, _) => show
                      ? TypingAnimation(size: size)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      );
      await settleParity(tester);
      final bars = find.descendant(
        of: find.byType(TypingAnimation),
        matching: find.byType(DecoratedBox),
      );
      await recordAnimation(
        tester,
        AnimationSpec(
          name: 'typing-dots-${size.round()}',
          source: 'lib/widgets/typing_animation.dart TypingAnimation',
          endMs: 2400,
          rects: {
            for (var i = 0; i < 3; i++)
              'bar${i + 1}': rectOf(tester, bars.at(i)),
          },
          colors: {'bar1': bars.at(0)},
          crop: () => [tester.getRect(find.byType(TypingAnimation)).inflate(4)],
        ),
        // Mounting starts it: t=0 is the frame it mounts in.
        () async => shown.value = true,
        notes: {
          'bars':
              'each bar is the painted box of its AnimatedContainer, '
              'without its margin',
        },
      );
      await _finish(tester);
    }, timeout: _timeout);
  }

  testWidgets('typing-row-in', (tester) async {
    final chat = await pumpChat(tester, ParityFixture.load('chat-dm'));
    await recordAnimation(
      tester,
      _typingSpec(tester, 'typing-row-in', chat),
      () => _typing(chat, typing: true),
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('typing-row-out', (tester) async {
    final chat = await pumpChat(tester, ParityFixture.load('chat-dm'));
    await _typing(chat, typing: true);
    await settleParity(tester);
    await recordAnimation(
      tester,
      _typingSpec(tester, 'typing-row-out', chat),
      () => _typing(chat, typing: false),
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('message-in', (tester) async {
    final chat = await pumpChat(tester, ParityFixture.load('chat-dm'));
    await _typing(chat, typing: true);
    await settleParity(tester);
    const reply = 'Pulling into the lot now';
    final last = _lastMessageBody(chat);
    await recordAnimation(
      tester,
      AnimationSpec(
        name: 'message-in',
        source:
            'lib/pages/chat/events/message.dart _AnimateIn; '
            'lib/pages/chat/typing_indicators.dart TypingIndicators',
        endMs: 600,
        rects: {
          'newBubble': rectOf(tester, _animateInBox(reply)),
          'newBubbleChild': rectOf(tester, _bubble(reply)),
          'lastBubble': rectOf(tester, _bubble(last)),
          'row': rectOf(tester, _typingRow),
        },
        // The chat marks a message it inserts at the bottom to grow in, and
        // clears the mark once the animation's duration has passed.
        texts: {
          'animateInEventId': () => tester
              .state<ChatController>(find.byType(ChatPageWithRoom))
              .animateInEventId,
        },
        crop: () => [_bottomBand(tester, 0.5)],
      ),
      // One sync brings the reply and ends the typing, as a real reply does.
      () => _sync(
        chat,
        typing: false,
        message: (sender: chat.partners.values.first, body: reply),
      ),
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('message-out', (tester) async {
    final chat = await pumpChat(tester, ParityFixture.load('chat-dm-linked'));
    const text = 'On it';
    await tester.enterText(find.byType(InputBar), text);
    await settleParity(tester);
    final previous = _lastMessageBody(chat);
    await recordAnimation(
      tester,
      AnimationSpec(
        name: 'message-out',
        source:
            'lib/pages/chat/events/message.dart _AnimateIn; '
            'lib/pages/chat/chat_input_row.dart ChatInputRow, ChatSendButton',
        endMs: 600,
        rects: {
          'newBubble': rectOf(tester, _animateInBox(text)),
          'newBubbleChild': rectOf(tester, _bubble(text)),
          'prevBubble': rectOf(tester, _bubble(previous)),
          'composerPill': rectOf(tester, _composerPill),
          'attachSlot': rectOf(tester, _attachSlot),
          'sendButton': rectOf(tester, _sendButton),
        },
        colors: {'sendButton': _sendButton},
        crop: () => [_bottomBand(tester, 0.5)],
      ),
      () => tester.tap(find.byKey(const Key('send_button'))),
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('switch-network', (tester) async {
    final fixture = ParityFixture.load('chat-dm-linked');
    await pumpChat(tester, fixture);
    final buttons = find.descendant(
      of: find.byType(ChatNetworkIcons),
      matching: find.byType(AnimatedContainer),
    );
    await recordAnimation(
      tester,
      AnimationSpec(
        name: 'switch-network',
        source:
            'lib/pages/chat/chat_app_bar_title.dart ChatNetworkIcons; '
            'lib/pages/chat/chat_input_row.dart ChatSendButton',
        endMs: 600,
        rects: {
          'btn1': rectOf(tester, buttons.at(0)),
          'btn2': rectOf(tester, buttons.at(1)),
          'sendButton': rectOf(tester, _sendButton),
        },
        colors: {
          'btn1': buttons.at(0),
          'btn2': buttons.at(1),
          'sendButton': _sendButton,
        },
        texts: {'hint': () => _hint(tester)},
        crop: () => [
          Rect.fromLTWH(0, 0, _width(tester), fixture.statusBar + 56),
          _bottomBand(tester, 0.88),
        ],
      ),
      () => tester.tap(buttons.at(1)),
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('composer-type', (tester) async {
    await pumpChat(tester, ParityFixture.load('chat-dm-linked'));
    await recordAnimation(
      tester,
      AnimationSpec(
        name: 'composer-type',
        source: 'lib/pages/chat/chat_input_row.dart ChatInputRow',
        endMs: 600,
        rects: {
          'attachSlot': rectOf(tester, _attachSlot),
          'input': rectOf(tester, find.byType(InputBar)),
          'sendButton': rectOf(tester, _sendButton),
        },
        texts: {'sendIcon': () => _sendIconName(tester)},
        crop: () => [_bottomBand(tester, 0.88)],
      ),
      () => tester.enterText(find.byType(InputBar), 'On it'),
      notes: {
        'sendIcon':
            'the reference phone has voice messages off (fixture '
            'composer.mic is false), so the button shows send_outlined '
            'before any text too',
      },
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('list-typing-preview', (tester) async {
    final client = await pumpChatList(tester, ParityFixture.load('chat-list'));
    // Omar Sayegh, a read chat from someone else.
    final room = client.getRoomById('!row1:$homeserver')!;
    final item = _listItem(room.id);
    final slot = find.descendant(of: item, matching: find.byType(AnimatedSize));
    await recordAnimation(
      tester,
      AnimationSpec(
        name: 'list-typing-preview',
        source: 'lib/pages/chat_list/chat_list_item.dart ChatListItem',
        endMs: 600,
        rects: {
          'typingSlot': rectOf(tester, slot.first),
          'preview': () => _previewRect(tester, slot.first),
        },
        crop: () => [tester.getRect(item).inflate(4)],
      ),
      () => client.handleSync(
        _syncUpdate(room.id, typing: [room.directChatMatrixID!]),
      ),
    );
    await _finish(tester);
  }, timeout: _timeout);

  testWidgets('unread-arrive', (tester) async {
    final client = await pumpChatList(tester, ParityFixture.load('chat-list'));
    // Lena Brandt, the newest chat, read; a new message keeps it on top.
    final room = client.getRoomById('!row0:$homeserver')!;
    final item = _listItem(room.id);
    final bubble = find.descendant(
      of: find.descendant(of: item, matching: find.byType(UnreadBubble)),
      matching: find.byType(AnimatedContainer),
    );
    await recordAnimation(
      tester,
      AnimationSpec(
        name: 'unread-arrive',
        source: 'lib/pages/chat_list/unread_bubble.dart UnreadBubble',
        endMs: 600,
        rects: {
          'unreadBubble': rectOf(tester, bubble.first),
          'title': rectOf(
            tester,
            find.descendant(of: item, matching: find.text('Lena Brandt')),
          ),
        },
        colors: {'unreadBubble': bubble.first},
        crop: () => [tester.getRect(item).inflate(4)],
      ),
      () => client.handleSync(
        _syncUpdate(
          room.id,
          message: (
            sender: room.directChatMatrixID!,
            body: 'Are you still up for tomorrow?',
          ),
          // A fixed time keeps the row's time label, and so the title's
          // width, the same on every run; later than the chat's 21:16.
          sentAt: _todayAt(21, 30),
          notificationCount: 1,
        ),
      ),
    );
    await _finish(tester);
  }, timeout: _timeout);
}

var _syncCount = 0;

/// A sync for [roomId] from the fake server: who is typing, a new message
/// and the room's unread count, each when given.
SyncUpdate _syncUpdate(
  String roomId, {
  List<String>? typing,
  ({String sender, String body})? message,
  DateTime? sentAt,
  int? notificationCount,
}) {
  final n = ++_syncCount;
  return SyncUpdate(
    nextBatch: 'parity-$n',
    rooms: RoomsUpdate(
      join: {
        roomId: JoinedRoomUpdate(
          ephemeral: [
            if (typing != null)
              BasicEvent(type: 'm.typing', content: {'user_ids': typing}),
          ],
          timeline: TimelineUpdate(
            events: [
              if (message != null)
                MatrixEvent(
                  type: EventTypes.Message,
                  content: {'msgtype': MessageTypes.Text, 'body': message.body},
                  senderId: message.sender,
                  eventId: '\$parity-sync-$n',
                  originServerTs: sentAt ?? DateTime.now(),
                ),
            ],
          ),
          unreadNotifications: notificationCount == null
              ? null
              : UnreadNotificationCounts(
                  notificationCount: notificationCount,
                  highlightCount: 0,
                ),
        ),
      },
    ),
  );
}

DateTime _todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

/// The chat's partner starts or stops typing.
Future<void> _typing(ParityChat chat, {required bool typing}) =>
    _sync(chat, typing: typing);

Future<void> _sync(
  ParityChat chat, {
  required bool typing,
  ({String sender, String body})? message,
}) {
  final network = chat.rooms.keys.first;
  return chat.client.handleSync(
    _syncUpdate(
      chat.rooms[network]!.id,
      typing: typing ? [chat.partners[network]!] : const [],
      message: message,
    ),
  );
}

AnimationSpec _typingSpec(WidgetTester tester, String name, ParityChat chat) =>
    AnimationSpec(
      name: name,
      source: 'lib/pages/chat/typing_indicators.dart TypingIndicators',
      endMs: 600,
      rects: {
        'row': rectOf(tester, _typingRow),
        'pill': rectOf(tester, _typingPill),
        'lastBubble': rectOf(tester, _bubble(_lastMessageBody(chat))),
      },
      crop: () => [_bottomBand(tester, 0.5)],
    );

/// The body of the newest text message in the fixture's timeline.
String _lastMessageBody(ParityChat chat) {
  final events = [for (final room in chat.rooms.values) ...room.events]
    ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
  return events
      .lastWhere(
        (event) =>
            event.type == EventTypes.Message &&
            event.messageType == MessageTypes.Text,
      )
      .body;
}

Finder _message(String body) => find.byWidgetPredicate(
  (widget) => widget is Message && widget.event.body == body,
);

/// The message bubble of the message reading [body].
Finder _bubble(String body) => find
    .descendant(of: _message(body), matching: find.byType(BubbleBackground))
    .first;

/// The box a new message grows in while it animates in.
Finder _animateInBox(String body) => find
    .descendant(of: _message(body), matching: find.byType(AnimatedSize))
    .first;

final _typingRow = find
    .descendant(
      of: find.byType(TypingIndicators),
      matching: find.byType(AnimatedContainer),
    )
    .first;

final _typingPill = find
    .descendant(
      of: find.byType(TypingIndicators),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.borderRadius ==
                const BorderRadius.all(Radius.circular(AppConfig.borderRadius)),
      ),
    )
    .first;

final _composerPill = find
    .descendant(of: find.byType(ChatComposer), matching: find.byType(Material))
    .first;

/// The add-attachment slot, 44 wide while the composer is empty and 16
/// with text.
final _attachSlot = find
    .descendant(
      of: find.byType(ChatInputRow),
      matching: find.byType(AnimatedContainer),
    )
    .first;

final _sendButton = find
    .descendant(
      of: find.byType(ChatSendButton),
      matching: find.byType(IconButton),
    )
    .first;

String? _hint(WidgetTester tester) {
  final field = find.descendant(
    of: find.byType(InputBar),
    matching: find.byType(TextField),
  );
  if (field.evaluate().isEmpty) return null;
  return tester.widget<TextField>(field.first).decoration?.hintText;
}

String? _sendIconName(WidgetTester tester) {
  final icon = find.descendant(of: _sendButton, matching: find.byType(Icon));
  if (icon.evaluate().isEmpty) return null;
  final data = tester.widget<Icon>(icon.first).icon;
  if (data == Icons.send_outlined) return 'send_outlined';
  if (data == Icons.mic_none_outlined) return 'mic_none_outlined';
  if (data == Icons.mic) return 'mic';
  return data?.codePoint.toRadixString(16);
}

Finder _listItem(String roomId) => find.byWidgetPredicate(
  (widget) => widget is ChatListItem && widget.room.id == roomId,
);

/// The preview text beside a chat list row's typing slot [slot].
Rect? _previewRect(WidgetTester tester, Finder slot) {
  final found = slot.evaluate();
  if (found.isEmpty) return null;
  final slotElement = found.first;
  Element? row;
  slotElement.visitAncestorElements((element) {
    if (element.widget is Row) {
      row = element;
      return false;
    }
    return true;
  });
  RenderBox? text;
  void visit(Element element) {
    if (text != null || element == slotElement) return;
    if (element.widget is RichText) {
      text = element.renderObject as RenderBox?;
      return;
    }
    element.visitChildElements(visit);
  }

  row?.visitChildElements(visit);
  final box = text;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

double _width(WidgetTester tester) =>
    tester.view.physicalSize.width / tester.view.devicePixelRatio;

/// The full width of the screen from [fromFraction] of its height down.
Rect _bottomBand(WidgetTester tester, double fromFraction) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  return Rect.fromLTRB(0, size.height * fromFraction, size.width, size.height);
}

/// Takes the screen down and lets what it started run out, including the
/// 30 second timeout of a typing notice.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 31));
}

void _dispose(Client client) {
  MergeSuggestionService.disposeFor(client);
  MergedContactsStore.disposeFor(client);
}
