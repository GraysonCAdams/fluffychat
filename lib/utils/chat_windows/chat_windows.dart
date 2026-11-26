// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Brightness, Color, FlutterView, Size;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:flutter/foundation.dart';

/// A chat that can be shown in a window of its own: one room, or a merged
/// contact with all of its rooms.
@immutable
class ChatWindowTarget {
  final String? roomId;
  final String? contactId;

  const ChatWindowTarget.room(String this.roomId) : contactId = null;

  const ChatWindowTarget.contact(String this.contactId) : roomId = null;

  /// Where the window's router opens. A room opens on its own (`single=1`)
  /// so a room that belongs to a merged contact shows just that room.
  String get location {
    final contactId = this.contactId;
    if (contactId != null) return mergedContactRoute(contactId);
    return Uri(
      path: '/rooms/$roomId',
      queryParameters: {'single': '1'},
    ).toString();
  }

  /// Whether [uri] is this chat or one of its pages (details, search and
  /// so on). [contactRooms] are the rooms of the merged contact a room
  /// belongs to, or of this contact, whose pages count as this chat's too.
  bool owns(Uri uri, {Iterable<String> contactRooms = const []}) {
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'rooms') return false;
    if (segments[1] == 'contact') {
      if (segments.length < 3) return false;
      final contactId = this.contactId;
      return contactId != null
          ? segments[2] == contactId
          : contactRooms.contains(roomId);
    }
    return segments[1] == roomId || contactRooms.contains(segments[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is ChatWindowTarget &&
      other.roomId == roomId &&
      other.contactId == contactId;

  @override
  int get hashCode => Object.hash(roomId, contactId);

  @override
  String toString() => contactId != null
      ? 'ChatWindowTarget.contact($contactId)'
      : 'ChatWindowTarget.room($roomId)';
}

/// A native window that shows one chat, as [ChatWindowBackend.create] made
/// it.
abstract class ChatWindowHandle {
  /// The view the window's content is drawn into.
  FlutterView get view;

  /// The size of the area inside the window frame, in logical pixels.
  Size get contentSize;

  bool get isMinimized;

  bool get isMaximized;

  /// Restores the window if it is minimized and brings it to the front.
  void focus();

  /// Matches the native title bar to the chat's theme.
  void setTitleBarColors({
    required Brightness brightness,
    required Color caption,
    required Color text,
  });

  /// Closes the window. [ChatWindowBackend.create]'s `onDestroyed` follows.
  void destroy();
}

/// Opens native windows. Set on [ChatWindows.backend] where the platform
/// supports more than one window.
abstract class ChatWindowBackend {
  /// Opens a window titled [title] whose content area is [size].
  /// [onCloseRequested] runs when the user asks to close it and must call
  /// [ChatWindowHandle.destroy] for it to close; [onDestroyed] runs once it
  /// is gone; [onChanged] runs whenever it is resized or activated.
  ChatWindowHandle create({
    required Size size,
    required String title,
    required VoidCallback onCloseRequested,
    required VoidCallback onDestroyed,
    required VoidCallback onChanged,
  });
}

/// The chats open in windows of their own, at most one window per chat.
/// Nothing about a window outlives it: once closed, its chat opens in the
/// app again. The size of the last window resized or closed is kept in
/// [AppSettings.chatWindowSize] for the next one.
class ChatWindows extends ChangeNotifier {
  ChatWindows();

  static final ChatWindows instance = ChatWindows();

  /// The size of a chat window when none has been resized or closed yet.
  static const Size defaultSize = Size(480, 720);

  /// Saved sizes below this are ignored, so a window squeezed to a sliver
  /// does not make the next one open as one.
  static const Size minimumSize = Size(320, 240);

  /// How long resizing has to pause before the size is saved.
  static const Duration saveDelay = Duration(milliseconds: 500);

  /// Opens the windows; null where only the main window exists.
  ChatWindowBackend? backend;

  bool get isSupported => backend != null;

  final _windows = <ChatWindowTarget, ChatWindowHandle>{};
  Timer? _saveTimer;

  /// The open windows by chat, oldest first.
  Map<ChatWindowTarget, ChatWindowHandle> get windows =>
      UnmodifiableMapView(_windows);

  bool isOpen(ChatWindowTarget target) => _windows.containsKey(target);

  /// Brings the window of [target] to the front. Returns false when the
  /// chat has none.
  bool focus(ChatWindowTarget target) {
    final handle = _windows[target];
    if (handle == null) return false;
    handle.focus();
    return true;
  }

  /// Opens [target] in a window titled [title], or brings its window to
  /// the front when it already has one.
  void open(ChatWindowTarget target, {required String title}) {
    final backend = this.backend;
    if (backend == null || focus(target)) return;
    late final ChatWindowHandle handle;
    handle = backend.create(
      size: savedSize,
      title: title,
      onCloseRequested: () => close(target),
      onDestroyed: () {
        if (!identical(_windows[target], handle)) return;
        _windows.remove(target);
        notifyListeners();
      },
      onChanged: () => _scheduleSave(handle),
    );
    _windows[target] = handle;
    notifyListeners();
  }

  /// Closes the window of [target], if it has one, keeping its size.
  void close(ChatWindowTarget target) {
    final handle = _windows[target];
    if (handle == null) return;
    _saveSize(handle);
    handle.destroy();
  }

  /// Closes every window, keeping the size of the newest.
  void closeAll() {
    final handles = _windows.values.toList();
    if (handles.isNotEmpty) _saveSize(handles.last);
    for (final handle in handles) {
      handle.destroy();
    }
  }

  /// The size new windows open at.
  Size get savedSize {
    final parts = AppSettings.chatWindowSize.value.split(',');
    if (parts.length != 2) return defaultSize;
    final width = double.tryParse(parts[0]);
    final height = double.tryParse(parts[1]);
    if (width == null ||
        height == null ||
        width < minimumSize.width ||
        height < minimumSize.height) {
      return defaultSize;
    }
    return Size(width, height);
  }

  void _scheduleSave(ChatWindowHandle handle) {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () {
      if (_windows.containsValue(handle)) _saveSize(handle);
    });
  }

  /// Keeps the size of [handle] unless it is minimized or maximized, which
  /// say nothing about the size the user wants.
  void _saveSize(ChatWindowHandle handle) {
    _saveTimer?.cancel();
    if (handle.isMinimized || handle.isMaximized) return;
    final size = handle.contentSize;
    if (size.width < minimumSize.width || size.height < minimumSize.height) {
      return;
    }
    final value = '${size.width.round()},${size.height.round()}';
    if (value == AppSettings.chatWindowSize.value) return;
    unawaited(AppSettings.chatWindowSize.setItem(value));
  }
}
