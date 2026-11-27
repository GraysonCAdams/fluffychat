// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/windows_shell_ffi.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// Thin coloured strips in [theme]'s divider colour: the lines that used to
/// separate the panes.
Finder dividerLines(ThemeData theme) => find.byWidgetPredicate((widget) {
  if (widget is! Container) return false;
  final decoration = widget.decoration;
  final color =
      widget.color ?? (decoration is BoxDecoration ? decoration.color : null);
  if (color != theme.dividerColor) return false;
  final constraints = widget.constraints;
  return constraints != null &&
      constraints.hasTightWidth &&
      constraints.maxWidth <= 1;
});

void main() {
  const desktop = Size(1600, 900);
  final theme = ThemeData(useMaterial3: true);

  Future<void> pumpLayout(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const TwoColumnLayout(
          mainView: SizedBox.expand(key: Key('list')),
          sideView: Scaffold(body: SizedBox.expand(key: Key('chat'))),
        ),
      ),
    );
  }

  group('column mode', () {
    testWidgets('has no divider between the list and the chat', (tester) async {
      await pumpLayout(tester, desktop);
      expect(dividerLines(theme), findsNothing);
    });

    testWidgets('shows the chat as a card inset 8 dp right and bottom', (
      tester,
    ) async {
      await pumpLayout(tester, desktop);
      final card = find.ancestor(
        of: find.byKey(const Key('chat')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ClipRRect &&
              widget.borderRadius == BorderRadius.circular(16),
        ),
      );
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.right, desktop.width - 8);
      expect(rect.bottom, desktop.height - 8);
      expect(rect.top, 0);
      expect(rect.left, FluffyThemes.columnWidth + FluffyThemes.navRailWidth);
    });

    testWidgets('paints the card in surfaceContainerLow', (tester) async {
      await pumpLayout(tester, desktop);
      // The chat page's own scaffold, the nearest one.
      final scaffold = find
          .ancestor(
            of: find.byKey(const Key('chat')),
            matching: find.byType(Scaffold),
          )
          .first;
      final context = tester.element(scaffold);
      expect(
        Theme.of(context).colorScheme.surface,
        theme.colorScheme.surfaceContainerLow,
      );
      final material = tester.widget<Material>(
        find.descendant(of: scaffold, matching: find.byType(Material)).first,
      );
      expect(material.color, theme.colorScheme.surfaceContainerLow);
    });
  });

  group('under the Windows title bar', () {
    late FakeChatListClient client;
    setUp(() async {
      client = await setUpFakeChatList('two column card bar test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            (call) async => call.method == 'isMaximized' ? false : null,
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          );
      tearDownFakeChatList(client);
    });

    testWidgets('the card starts below the bar with its corners rounded', (
      tester,
    ) async {
      tester.view.physicalSize = desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();
      final key = GlobalKey();
      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: FakeMatrix(client, prefs),
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) =>
                  WindowsChrome(showChatList: () {}, child: child!),
              home: const TwoColumnLayout(
                mainView: SizedBox.expand(),
                sideView: Scaffold(body: SizedBox.expand(key: Key('chat'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find.ancestor(
          of: find.byKey(const Key('chat')),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(card.top, WindowsChrome.height);
      // The chat's own app bar needs no room for the bar above the card.
      expect(
        MediaQuery.paddingOf(tester.element(find.byKey(const Key('chat')))).top,
        0,
      );

      // Drawn, the card's top left corner is the bar's color, the base
      // surface, and the card's own color starts a corner radius in.
      final pixels = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        return (await image.toByteData())!.buffer.asUint8List();
      });
      int pixel(Offset at) {
        final i = (at.dy.floor() * desktop.width.toInt() + at.dx.floor()) * 4;
        return Color.fromARGB(
          pixels![i + 3],
          pixels[i],
          pixels[i + 1],
          pixels[i + 2],
        ).toARGB32();
      }

      expect(
        pixel(card.topLeft + const Offset(1, 1)),
        theme.colorScheme.surface.toARGB32(),
      );
      expect(
        pixel(card.topLeft + const Offset(16, 16)),
        theme.colorScheme.surfaceContainerLow.toARGB32(),
      );
      await tester.pumpWidget(const SizedBox());
      await finishFakeChatList(tester, client);
    });
  });

  group('chat list', () {
    late FakeChatListClient client;
    setUp(() async {
      client = await setUpFakeChatList('two column card test');
      addFakeChat(client, '!a:x', 'Harrison Young');
    });
    tearDown(() => tearDownFakeChatList(client));

    testWidgets('has no line between the rail and the list in column mode', (
      tester,
    ) async {
      tester.view.physicalSize = desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpFakeChatList(tester, client);
      final context = tester.element(find.byType(Scaffold).first);
      expect(dividerLines(Theme.of(context)), findsNothing);
      await finishFakeChatList(tester, client);
    });

    testWidgets('a single column has no card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await pumpFakeChatList(tester, client);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ClipRRect &&
              widget.borderRadius == BorderRadius.circular(16),
        ),
        findsNothing,
      );
      await finishFakeChatList(tester, client);
    });
  });
}
