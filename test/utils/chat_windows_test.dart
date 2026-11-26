// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/chat_windows/chat_windows.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_chat_windows.dart';

void main() {
  late FakeChatWindowBackend backend;
  final windows = ChatWindows.instance;
  const room = ChatWindowTarget.room('!a:x');
  const other = ChatWindowTarget.room('!b:x');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    // The settings store outlives a test's mock values.
    await AppSettings.chatWindowSize.setItem('');
    backend = installFakeChatWindows();
  });

  tearDown(removeFakeChatWindows);

  test('unsupported without a backend, and open does nothing', () {
    windows.backend = null;
    expect(windows.isSupported, isFalse);
    windows.open(room, title: 'A');
    expect(windows.isOpen(room), isFalse);
  });

  test('a chat gets one window; opening it again focuses that window', () {
    windows.open(room, title: 'A');
    windows.open(room, title: 'A');
    expect(backend.windows, hasLength(1));
    expect(backend.windows.single.title, 'A');
    expect(backend.windows.single.focusCount, 1);

    windows.open(other, title: 'B');
    expect(backend.windows, hasLength(2));
    expect(windows.windows.keys, [room, other]);
  });

  test('the first window opens at the default size', () {
    windows.open(room, title: 'A');
    expect(backend.windows.single.size, ChatWindows.defaultSize);
  });

  test('closing leaves nothing behind: the chat opens in a new window', () {
    windows.open(room, title: 'A');
    final first = backend.windows.single;
    first.onCloseRequested();
    expect(first.destroyed, isTrue);
    expect(windows.isOpen(room), isFalse);
    expect(windows.focus(room), isFalse);

    windows.open(room, title: 'A');
    expect(backend.windows, hasLength(2));
    expect(first.focusCount, 0);
  });

  test('a new window opens at the size the last one was closed at', () {
    windows.open(room, title: 'A');
    backend.windows.single
      ..size = const Size(610.4, 820.6)
      ..onCloseRequested();
    expect(AppSettings.chatWindowSize.value, '610,821');

    windows.open(other, title: 'B');
    expect(backend.windows.last.size, const Size(610, 821));
  });

  testWidgets('a resize is kept once resizing pauses', (tester) async {
    windows.open(room, title: 'A');
    final window = backend.windows.single;
    window.resize(const Size(500, 600));
    window.resize(const Size(520, 640));
    await tester.pump(ChatWindows.saveDelay ~/ 2);
    expect(AppSettings.chatWindowSize.value, '');

    await tester.pump(ChatWindows.saveDelay);
    expect(AppSettings.chatWindowSize.value, '520,640');

    windows.open(other, title: 'B');
    expect(backend.windows.last.size, const Size(520, 640));
  });

  test('a minimized, maximized or tiny window does not set the size', () {
    windows.open(room, title: 'A');
    final window = backend.windows.single
      ..size = const Size(700, 700)
      ..onCloseRequested();
    expect(AppSettings.chatWindowSize.value, '700,700');

    for (final change in <void Function(FakeChatWindow)>[
      (w) => w.minimized = true,
      (w) => w.maximized = true,
      (w) => w.size = const Size(100, 900),
    ]) {
      windows.open(room, title: 'A');
      final next = backend.windows.last..size = const Size(900, 900);
      change(next);
      next.onCloseRequested();
      expect(AppSettings.chatWindowSize.value, '700,700');
    }
    expect(window.destroyed, isTrue);
  });

  test('a saved size that is malformed or too small is ignored', () async {
    for (final saved in ['', 'garbage', '700', '10,10', 'a,b']) {
      await AppSettings.chatWindowSize.setItem(saved);
      expect(windows.savedSize, ChatWindows.defaultSize, reason: saved);
    }
  });

  test('closeAll closes every window', () {
    windows.open(room, title: 'A');
    windows.open(other, title: 'B');
    windows.closeAll();
    expect(windows.windows, isEmpty);
    expect(backend.windows.every((w) => w.destroyed), isTrue);
  });

  group('ChatWindowTarget', () {
    test('a room opens on its own and owns its pages', () {
      expect(room.location, '/rooms/!a:x?single=1');
      expect(room.owns(Uri.parse('/rooms/!a:x')), isTrue);
      expect(room.owns(Uri.parse('/rooms/!a:x/details/members')), isTrue);
      expect(room.owns(Uri.parse('/rooms/!b:x')), isFalse);
      expect(room.owns(Uri.parse('/rooms')), isFalse);
      expect(room.owns(Uri.parse('/rooms/settings')), isFalse);
      expect(room.owns(Uri.parse('/rooms/contact/c1')), isFalse);
      expect(
        room.owns(Uri.parse('/rooms/contact/c1'), contactRooms: ['!a:x']),
        isTrue,
      );
    });

    test('a contact owns its screen and its rooms\' pages', () {
      const contact = ChatWindowTarget.contact('c1');
      expect(contact.location, '/rooms/contact/c1');
      expect(contact.owns(Uri.parse('/rooms/contact/c1?event=e')), isTrue);
      expect(contact.owns(Uri.parse('/rooms/contact/c2')), isFalse);
      expect(contact.owns(Uri.parse('/rooms/!a:x/details')), isFalse);
      expect(
        contact.owns(
          Uri.parse('/rooms/!a:x/details'),
          contactRooms: ['!a:x', '!b:x'],
        ),
        isTrue,
      );
    });
  });
}
