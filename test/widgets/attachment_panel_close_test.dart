// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages


import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

XFile _photo() =>
    XFile.fromData(Uint8List(16), name: 'waffles.jpg', mimeType: 'image/jpeg');

/// A system picker that returns a photo, or nothing when [cancel] is set.
class _ImagePicker extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  bool cancel = false;

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async =>
      cancel ? [] : [_photo()];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => cancel ? null : _photo();

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => cancel ? null : _photo();
}

final class _PickedFile extends PlatformFile {
  @override
  String get name => 'waffles.jpg';

  @override
  Uri get uri => Uri.parse('memory:waffles.jpg');

  @override
  XFile get xFile => _photo();

  @override
  int? lengthSync() => 16;

  @override
  Future<int?> length() async => 16;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(16);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(16));
}

class _FilePicker extends FilePickerPlatform with MockPlatformInterfaceMixin {
  bool cancel = false;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => cancel ? [] : [_PickedFile()];
}

/// Picking from the attachment panel closes it whether a file came back or
/// the picker was cancelled, and hands focus back to the text field, with
/// what was picked staged above it.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  late _ImagePicker imagePicker;
  late _FilePicker filePicker;

  setUp(() async {
    client = await setUpFakeChatList('attachment panel close');
    room = addFakeChat(client, '!grp:x', 'Squad Goals');
    imagePicker = _ImagePicker();
    filePicker = _FilePicker();
    ImagePickerPlatform.instance = imagePicker;
    FilePickerPlatform.instance = filePicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ChatController> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => ChatPage(roomId: room.id),
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<AppLock>.value(
        value: AppLock(),
        child: Provider<MatrixState>.value(
          value: _Matrix(client, prefs),
          child: MaterialApp.router(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await settle(tester);
    return tester.state<ChatController>(find.byType(ChatPageWithRoom));
  }

  Future<void> openPanel(WidgetTester tester, ChatController chat) async {
    await tester.tap(find.byKey(const ValueKey('composer-attach')));
    await settle(tester);
    expect(chat.showAttachmentPanel, isTrue);
    expect(chat.inputFocus.hasFocus, isFalse);
  }

  void expectClosed(ChatController chat, {required bool picked}) {
    expect(chat.showAttachmentPanel, isFalse, reason: 'panel');
    expect(chat.inputFocus.hasFocus, isTrue, reason: 'focus');
    expect(chat.pendingAttachments, hasLength(picked ? 1 : 0));
  }

  for (final width in [1000.0, 400.0]) {
    for (final cancel in [false, true]) {
      final outcome = cancel ? 'cancelled' : 'picked';
      final wide = '${width.toInt()} wide';

      // The entries every platform shows, tapped in the panel.
      for (final (label, l10n) in [
        ('Gallery', (L10n l) => l.gallery),
        ('Files', (L10n l) => l.files),
      ]) {
        testWidgets('$label, $outcome, closes the panel, $wide', (
          tester,
        ) async {
          imagePicker.cancel = cancel;
          filePicker.cancel = cancel;
          final chat = await open(tester, width);
          await openPanel(tester, chat);
          await tester.tap(
            find.bySemanticsLabel(
              l10n(L10n.of(tester.element(find.byType(ChatPageWithRoom)))),
            ),
          );
          await settle(tester);
          expectClosed(chat, picked: !cancel);
        });
      }

      if (!cancel) {
        testWidgets('Poll closes the panel once its sheet is done, $wide', (
          tester,
        ) async {
          final chat = await open(tester, width);
          await openPanel(tester, chat);
          await tester.tap(find.bySemanticsLabel('Poll'));
          await settle(tester);
          final sheet = find.byType(StartPollBottomSheet);
          expect(sheet, findsOneWidget);
          Navigator.of(tester.element(sheet)).pop();
          await settle(tester);
          expect(chat.showAttachmentPanel, isFalse, reason: 'panel');
          expect(chat.inputFocus.hasFocus, isTrue, reason: 'focus');
        });
      }

      // The phone's camera entries, run as the panel runs them; the test
      // host is not a phone, so the panel does not list them here.
      final actions = <String, Future<void> Function(ChatController)>{
        'camera': (chat) => chat.attachFromPanel(chat.openCameraAction),
        'video camera': (chat) =>
            chat.attachFromPanel(chat.openVideoCameraAction),
      };
      for (final MapEntry(key: label, value: action) in actions.entries) {
        testWidgets('$label, $outcome, closes the panel, $wide', (
          tester,
        ) async {
          imagePicker.cancel = cancel;
          final chat = await open(tester, width);
          await openPanel(tester, chat);
          await tester.runAsync(() => action(chat));
          await settle(tester);
          expectClosed(chat, picked: !cancel);
        });
      }
    }
  }
}
