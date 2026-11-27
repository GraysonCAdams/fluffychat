// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Future<void> pump(
    WidgetTester tester,
    List<Widget> children, {
    Size size = const Size(412, 900),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: SettingsPage(title: 'Page', children: children),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The filled box of the row showing [text].
  Rect rowRect(WidgetTester tester, String text) => tester.getRect(
    find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
  );

  testWidgets('a one-line row is 56 tall and a two-line row 72', (
    tester,
  ) async {
    await pump(tester, [
      SettingsGroup(
        children: [
          const SettingsTile(title: Text('One')),
          const SettingsTile(title: Text('Two'), subtitle: Text('Supporting')),
          SettingsSwitchTile(
            title: const Text('Switch'),
            value: true,
            onChanged: (_) {},
          ),
          SettingsSwitchTile(
            title: const Text('Switch two'),
            subtitle: const Text('Supporting'),
            value: false,
            onChanged: (_) {},
          ),
        ],
      ),
    ]);
    expect(rowRect(tester, 'One').height, SettingsMetrics.oneLineHeight);
    expect(rowRect(tester, 'Two').height, SettingsMetrics.twoLineHeight);
    expect(rowRect(tester, 'Switch').height, SettingsMetrics.oneLineHeight);
    expect(rowRect(tester, 'Switch two').height, SettingsMetrics.twoLineHeight);
  });

  testWidgets('a long description grows the row instead of clipping', (
    tester,
  ) async {
    await pump(tester, [
      SettingsGroup(
        children: [
          SettingsTile(
            title: const Text('Long'),
            subtitle: Text('Supporting text that wraps. ' * 8),
          ),
        ],
      ),
    ]);
    expect(
      rowRect(tester, 'Long').height,
      greaterThan(SettingsMetrics.twoLineHeight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows share their insets: 16 to the page, 16 to the content, '
      '12 between icon and text', (tester) async {
    await pump(tester, [
      const SettingsSectionHeader('Header'),
      SettingsGroup(
        children: [
          const SettingsTile(
            leading: Icon(Icons.forum_outlined),
            title: Text('With icon'),
            subtitle: Text('Supporting'),
            trailing: SettingsTile.chevron,
          ),
          const SettingsTile(title: Text('Without icon')),
          SettingsSwitchTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Switch'),
            value: true,
            onChanged: (_) {},
          ),
        ],
      ),
      const SettingsCaption('Caption'),
    ]);
    const width = 412.0;
    for (final label in ['With icon', 'Without icon', 'Switch']) {
      final row = rowRect(tester, label);
      expect(row.left, SettingsMetrics.pageMargin, reason: label);
      expect(row.right, width - SettingsMetrics.pageMargin, reason: label);
    }
    // Icons start 16 inside the row, are 24 square and sit 12 before the
    // text, on every row that has one.
    const iconLeft = SettingsMetrics.pageMargin + SettingsMetrics.rowInset;
    const textAfterIcon =
        iconLeft + SettingsMetrics.iconSize + SettingsMetrics.iconGap;
    for (final (icon, label) in [
      (Icons.forum_outlined, 'With icon'),
      (Icons.backup_outlined, 'Switch'),
    ]) {
      final rect = tester.getRect(find.byIcon(icon));
      expect(rect.left, iconLeft, reason: label);
      expect(rect.size, const Size.square(SettingsMetrics.iconSize));
      expect(tester.getRect(find.text(label)).left, textAfterIcon);
      // Centred on the row.
      expect(rect.center.dy, rowRect(tester, label).center.dy);
    }
    expect(tester.getRect(find.text('Supporting')).left, textAfterIcon);
    // Text without an icon lines up with the headers and captions.
    expect(
      tester.getRect(find.text('Without icon')).left,
      SettingsMetrics.textInset,
    );
    expect(tester.getRect(find.text('Header')).left, SettingsMetrics.textInset);
    expect(
      tester.getRect(find.text('Caption')).left,
      SettingsMetrics.textInset,
    );
    // Trailing controls end 16 inside the row.
    const trailingRight =
        width - SettingsMetrics.pageMargin - SettingsMetrics.rowInset;
    expect(
      tester.getRect(find.byIcon(Icons.chevron_right_outlined)).right,
      trailingRight,
    );
    expect(tester.getRect(find.byType(Switch)).right, trailingRight);
  });

  testWidgets('rows of a group sit 2 apart and one that builds nothing '
      'leaves no gap', (tester) async {
    await pump(tester, [
      const SettingsGroup(
        children: [
          SettingsTile(title: Text('First')),
          SizedBox.shrink(),
          SettingsTile(title: Text('Second')),
          SettingsGroupItem(child: SizedBox(height: 40, child: Text('Third'))),
        ],
      ),
    ]);
    final first = rowRect(tester, 'First');
    final second = rowRect(tester, 'Second');
    final third = rowRect(tester, 'Third');
    expect(second.top - first.bottom, SettingsMetrics.rowGap);
    expect(third.top - second.bottom, SettingsMetrics.rowGap);
    expect(third.height, 40);
  });

  testWidgets('a section header is titleSmall in the primary colour', (
    tester,
  ) async {
    await pump(tester, [
      const SettingsSectionHeader('Header', description: 'What it is for'),
    ]);
    final context = tester.element(find.text('Header'));
    final theme = Theme.of(context);
    final style = tester.widget<Text>(find.text('Header')).style!;
    expect(style.fontSize, theme.textTheme.titleSmall!.fontSize);
    expect(style.fontWeight, theme.textTheme.titleSmall!.fontWeight);
    expect(style.color, theme.colorScheme.primary);
    expect(
      tester.widget<Text>(find.text('What it is for')).style!.color,
      theme.colorScheme.onSurfaceVariant,
    );
    expect(
      tester.getSemantics(find.text('Header')),
      matchesSemantics(label: 'Header', isHeader: true),
    );
  });

  testWidgets('tapping a switch row anywhere toggles it', (tester) async {
    var value = false;
    await pump(tester, [
      StatefulBuilder(
        builder: (context, setState) => SettingsGroup(
          children: [
            SettingsSwitchTile(
              title: const Text('Switch'),
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
            const SettingsSwitchTile(
              title: Text('Disabled'),
              value: false,
              onChanged: null,
            ),
          ],
        ),
      ),
    ]);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(value, isFalse);
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
  });

  testWidgets('a stored setting row shows the default until it is changed', (
    tester,
  ) async {
    await pump(tester, [
      const SettingsGroup(
        children: [
          SettingsSwitchListTile.adaptive(
            title: 'Swipe',
            subtitle: 'On chats',
            setting: AppSettings.chatListSwipe,
          ),
        ],
      ),
    ]);
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      AppSettings.chatListSwipe.defaultValue,
    );
    expect(rowRect(tester, 'Swipe').height, SettingsMetrics.twoLineHeight);
    await tester.tap(find.text('Swipe'));
    await tester.pumpAndSettle();
    expect(AppSettings.chatListSwipe.value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('a selected row is filled with secondaryContainer', (
    tester,
  ) async {
    await pump(tester, [
      const SettingsGroup(
        children: [
          SettingsTile(title: Text('Open'), selected: true),
          SettingsTile(title: Text('Other')),
        ],
      ),
    ]);
    final scheme = Theme.of(tester.element(find.text('Open'))).colorScheme;
    Color? fill(String text) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Material))
              .first,
        )
        .color;
    expect(fill('Open'), scheme.secondaryContainer);
    expect(fill('Other'), scheme.surfaceContainer);
  });

  testWidgets('rows are one step above the card in column mode', (
    tester,
  ) async {
    late ThemeData card;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            card = FluffyThemes.cardPaneTheme(Theme.of(context));
            return Theme(
              data: card,
              child: const SettingsGroup(
                children: [SettingsTile(title: Text('Row'))],
              ),
            );
          },
        ),
      ),
    );
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(of: find.text('Row'), matching: find.byType(Material))
                .first,
          )
          .color,
      card.colorScheme.surfaceContainerHigh,
    );
  });

  testWidgets('content stops at 640 wide and stays centred in a wide pane', (
    tester,
  ) async {
    await pump(tester, [
      const SettingsGroup(children: [SettingsTile(title: Text('Row'))]),
    ], size: const Size(1200, 800));
    final row = rowRect(tester, 'Row');
    expect(
      row.width,
      SettingsMetrics.maxContentWidth - 2 * SettingsMetrics.pageMargin,
    );
    expect(row.center.dx, 600);
  });
}
