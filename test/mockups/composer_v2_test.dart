// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

// Renders the composer as it is today and three layouts for its attach and
// emoji buttons, at a Windows width (1000) and a phone width (412), empty
// and while typing, dark and light, to PNGs under build/composer_v2/, with
// the measured paddings of each in build/composer_v2/metrics.json:
//
//   flutter test test/mockups/composer_v2_test.dart
//
// Every shot is built from the app's own pieces: its theme and font, the
// ComposerLeadingButtons, InputBar and ChatSendButton the composer uses,
// and the same pill. "today" is checked against the real ChatComposer of
// an open chat, so the replica cannot drift from what ships.
//
//   today  (+) and emoji leading, 48 targets: icons 12 from the edge, 24
//          apart, 24 to the text.
//   a      (+) leading; the emoji button is a trailing icon before send,
//          as in Google Messages. A phone has no emoji button.
//   b      (+) and emoji leading as one cluster: 40 containers 4 apart (44
//          pointer targets), text 8 after the cluster.
//   c      (+) leading only; emoji from the (+) menu or Win+.
//
// The tests run on the Windows host, so every shot shows the send arrow;
// Android shows the mic there while the field is empty, the same 40 circle.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/pages/chat/input_bar.dart';
import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _ghost = '@imessage_drew:x';
const _hint = 'iMessage';
const _typed = 'Waffle House at 9?';
const _seed = Color(0xFF1A5AD7);
const _widths = [1000.0, 412.0];
const _variants = ['today', 'a', 'b', 'c'];

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// One layout of the composer, built from the app's own widgets.
class _MockComposer extends StatelessWidget {
  final ChatController controller;
  final RecordingViewModelState recording;
  final String variant;
  final bool phone;
  final TextEditingController text;
  final FocusNode focus;

  const _MockComposer({
    required this.controller,
    required this.recording,
    required this.variant,
    required this.phone,
    required this.text,
    required this.focus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onPrimaryContainer;

    Widget iconButton(Key key, IconData icon, double size) => SizedBox(
      height: ChatInputRow.height,
      width: size,
      child: Center(
        child: IconButton(
          key: key,
          style: IconButton.styleFrom(
            fixedSize: Size.square(size),
            minimumSize: Size.square(size),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          color: iconColor,
          icon: Icon(icon),
          onPressed: () {},
        ),
      ),
    );

    final attach48 = iconButton(
      const ValueKey('attach'),
      Icons.add_circle_outline,
      48,
    );
    final List<Widget> leading;
    final List<Widget> trailing;
    final double textLeft;
    final double textRight;
    switch (variant) {
      case 'today':
        leading = [
          ComposerLeadingButtons(
            attachmentPanelOpen: false,
            onAttach: () {},
            showEmojiButton: !phone,
            emojiPickerOpen: false,
            onEmoji: () {},
          ),
        ];
        trailing = const [];
        textLeft = 12;
        textRight = 6;
      case 'a':
        leading = [attach48];
        trailing = [
          if (!phone)
            iconButton(
              const ValueKey('emoji'),
              Icons.add_reaction_outlined,
              48,
            ),
        ];
        // The text starts 16 after the (+) icon and ends 16 before the
        // emoji icon, M3's padding between a text field's icons and text.
        textLeft = 4;
        textRight = phone ? 6 : 4;
      case 'b':
        leading = [
          const SizedBox(width: 4),
          iconButton(const ValueKey('attach'), Icons.add_circle_outline, 40),
          if (!phone) ...[
            const SizedBox(width: 4),
            iconButton(
              const ValueKey('emoji'),
              Icons.add_reaction_outlined,
              40,
            ),
          ],
        ];
        trailing = const [];
        textLeft = 8;
        textRight = 6;
      default:
        leading = [attach48];
        trailing = const [];
        textLeft = 4;
        textRight = 6;
    }

    return Material(
      key: const ValueKey('pill'),
      clipBehavior: Clip.hardEdge,
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(ChatInputRow.height / 2),
      child: Row(
        crossAxisAlignment: .end,
        children: [
          ...leading,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: InputBar(
                room: controller.room,
                minLines: 1,
                maxLines: 8,
                autofocus: false,
                keyboardType: TextInputType.multiline,
                focusNode: focus,
                controller: text,
                suggestionEmojis: const [],
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.only(
                    left: textLeft,
                    right: textRight,
                    bottom: 6.0,
                    top: 3.0,
                  ),
                  counter: const SizedBox.shrink(),
                  hintText: _hint,
                  hintMaxLines: 1,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),
          ...trailing,
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ChatSendButton(controller, recording, compact: true),
          ),
        ],
      ),
    );
  }
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

  setUpAll(() async {
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium']) {
      final file = File(
        'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
      );
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    await loader.load();
    final icons = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '/material_fonts/MaterialIcons-Regular.otf',
    );
    expect(icons.existsSync(), isTrue, reason: icons.path);
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
  });

  setUp(() async {
    client = await setUpFakeChatList('composer v2');
    room = addFakeChat(client, '!imsg:x', 'Drew', partner: _ghost);
    room.setState(
      StrippedStateEvent(
        type: 'm.bridge',
        content: {
          'bridgebot': '@imessagebot:x',
          'protocol': {'id': 'imessage', 'displayname': 'iMessage'},
        },
        senderId: '@imessagebot:x',
        stateKey: 'net/${room.id}',
      ),
    );
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

  testWidgets('composer v2 mockups', (tester) async {
    final out = Directory('build/composer_v2')..createSync(recursive: true);
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('chat list')),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (_, _) => ChatPage(roomId: room.id),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _Matrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/chat');
    await settle(tester);
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));

    /// Where a composer's icons and text sit, from its pill's left edge.
    Map<String, Object> measure(Finder scope) {
      final pill = tester.getRect(
        find
            .descendant(of: scope, matching: find.byType(Material))
            .first,
      );
      final icons =
          find
              .descendant(of: scope, matching: find.byType(Icon))
              .evaluate()
              .map((e) {
                final box = e.renderObject! as RenderBox;
                return box.localToGlobal(Offset.zero) & box.size;
              })
              .toList()
            ..sort((a, b) => a.left.compareTo(b.left));
      final text = tester.getRect(
        find.descendant(of: scope, matching: find.byType(EditableText)),
      );
      double r(double v) => (v * 10).round() / 10;
      return {
        'pill': [r(pill.width), r(pill.height)],
        'icons': [
          for (final icon in icons)
            [r(icon.left - pill.left), r(icon.right - pill.left)],
        ],
        'text': [r(text.left - pill.left), r(text.right - pill.left)],
      };
    }

    // The real composer, to hold the replica of today to.
    final real = measure(find.byType(ChatComposer));

    final shots = <String>[];
    final texts = <TextEditingController>[];
    final focuses = <FocusNode>[];
    addTearDown(() {
      for (final t in texts) {
        t.dispose();
      }
      for (final f in focuses) {
        f.dispose();
      }
    });

    final sheet = <Widget>[];
    for (final brightness in Brightness.values) {
      for (final typing in [false, true]) {
        for (final variant in _variants) {
          for (final width in _widths) {
            final phone = width < 600;
            final name =
                '${brightness.name}_${variant}_${width.toInt()}_'
                '${typing ? 'typing' : 'empty'}';
            shots.add(name);
            final text = TextEditingController(text: typing ? _typed : '');
            final focus = FocusNode();
            texts.add(text);
            focuses.add(focus);
            sheet.add(
              MediaQuery(
                data: MediaQueryData(size: Size(width, 800)),
                child: Builder(
                  builder: (context) {
                    final theme = FluffyThemes.buildTheme(
                      context,
                      brightness,
                      _seed,
                    );
                    return Theme(
                      data: theme,
                      child: RepaintBoundary(
                        key: ValueKey(name),
                        child: Container(
                          width: width,
                          color: theme.colorScheme.surface,
                          padding: EdgeInsets.all(phone ? 8 : 16),
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: FluffyThemes.maxTimelineWidth,
                            ),
                            child: RecordingViewModel(
                              builder: (context, recording) => _MockComposer(
                                controller: chat,
                                recording: recording,
                                variant: variant,
                                phone: phone,
                                text: text,
                                focus: focus,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        }
      }
    }

    tester.view.physicalSize = Size(1100, sheet.length * 100.0);
    final navigator = Navigator.of(
      tester.element(find.byType(ChatComposer)),
      rootNavigator: true,
    );
    navigator.push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                for (final shot in sheet)
                  Padding(padding: const EdgeInsets.all(4), child: shot),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    final metrics = <String, Object>{'real_today_1000': real};
    for (final name in shots) {
      final scope = find.byKey(ValueKey(name));
      metrics[name] = measure(
        find.descendant(of: scope, matching: find.byType(_MockComposer)),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(scope);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${out.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    File(
      '${out.path}/metrics.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));

    // The replica of today places its icons and text where the real
    // composer does.
    final replica = metrics['dark_today_1000_empty']! as Map<String, Object>;
    expect(
      jsonEncode((replica['icons']! as List).take(2).toList()),
      jsonEncode((real['icons']! as List).take(2).toList()),
    );
    expect(
      (replica['text']! as List).first,
      (real['text']! as List).first,
    );
  });
}
