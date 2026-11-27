// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/windows_shell_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _seed = Color(0xFF1A5AD7);

void main() {
  /// A window [size] big with Seam's theme in [brightness], whose bottom
  /// [taskbar] pixels something outside the app covers. Opens a menu of
  /// [items] rows from [at].
  Future<void> openMenu(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(400, 600),
    double taskbar = 0,
    int items = 3,
    Offset at = const Offset(16, 16),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MenuObscuredInsets(
        insets: EdgeInsets.only(bottom: taskbar),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: FluffyThemes.buildTheme(context, brightness, _seed),
            home: Scaffold(
              body: Builder(
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showMenu<int>(
                    context: context,
                    position: RelativeRect.fromRect(
                      at & Size.zero,
                      Offset.zero & size,
                    ),
                    items: [
                      for (var i = 0; i < items; i++)
                        PopupMenuItem(value: i, child: Text('Row $i')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
  }

  /// The menu's panel.
  Finder panel() => find.ancestor(
    of: find.text('Row 0'),
    matching: find.byWidgetPredicate(
      (w) => w is Material && w.type == MaterialType.card,
    ),
  );

  for (final brightness in Brightness.values) {
    testWidgets('a ${brightness.name} menu stands a step off the page, '
        'with a shadow and no outline', (tester) async {
      await openMenu(tester, brightness: brightness);
      final scheme = ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: _seed,
        dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
      );
      final material = tester.widget<Material>(panel());
      expect(
        material.color,
        brightness == Brightness.dark
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLowest,
      );
      expect(material.elevation, 3);
      expect(material.surfaceTintColor, Colors.transparent);
      expect((material.shape! as RoundedRectangleBorder).side, BorderSide.none);

      // MenuAnchor menus take the same surface.
      final style = Theme.of(tester.element(panel())).menuTheme.style!;
      expect(style.backgroundColor!.resolve({}), material.color);
      expect(style.elevation!.resolve({}), 3);
      expect(
        (style.shape!.resolve({})! as RoundedRectangleBorder).side,
        BorderSide.none,
      );
    });
  }

  testWidgets('a menu too tall for the window stops 8 above the taskbar '
      'and scrolls with its scrollbar showing', (tester) async {
    await openMenu(tester, size: const Size(400, 400), taskbar: 48, items: 20);
    final rect = tester.getRect(panel());
    expect(rect.bottom, moreOrLessEquals(400 - 48 - 8));
    expect(rect.top, greaterThanOrEqualTo(8));
    final scrollbar = find.descendant(
      of: panel(),
      matching: find.byType(Scrollbar),
    );
    expect(scrollbar, findsOneWidget);
    expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isTrue);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: panel(), matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('a menu with no room below opens above where it was asked', (
    tester,
  ) async {
    await openMenu(
      tester,
      size: const Size(400, 400),
      at: const Offset(16, 340),
    );
    final rect = tester.getRect(panel());
    expect(rect.bottom, moreOrLessEquals(340));
  });

  test('the obscured insets are the parts of the window past the work '
      'area', () {
    const workArea = Rect.fromLTWH(0, 0, 1920, 1032);
    expect(
      WindowsChrome.obscuredInsets(
        const Rect.fromLTWH(100, 200, 800, 900),
        workArea,
      ),
      const EdgeInsets.only(bottom: 68),
    );
    expect(
      WindowsChrome.obscuredInsets(
        const Rect.fromLTWH(-20, 100, 600, 400),
        workArea,
      ),
      const EdgeInsets.only(left: 20),
    );
    expect(
      WindowsChrome.obscuredInsets(
        const Rect.fromLTWH(100, 100, 600, 400),
        workArea,
      ),
      EdgeInsets.zero,
    );
  });
}
