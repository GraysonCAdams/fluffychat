// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeBuilder extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ThemeMode themeMode,
    Color? primaryColor,
  )
  builder;

  final String themeModeSettingsKey;
  final String primaryColorSettingsKey;

  /// Set to true when the user picked the system's dynamic colour. Without
  /// it, and with no colour of their own, the app uses Seam Cobalt.
  final String useSystemColorSettingsKey;

  /// The preferences main() has already loaded, so the saved theme mode and
  /// color are known for the very first frame.
  final SharedPreferences store;

  /// The system's dynamic primary color, resolved before runApp by
  /// loadDynamicPrimaryColor(). Used when the user picked the system color.
  final Color? dynamicPrimaryColor;

  const ThemeBuilder({
    required this.builder,
    required this.store,
    this.dynamicPrimaryColor,
    this.themeModeSettingsKey = 'theme_mode',
    this.primaryColorSettingsKey = 'primary_color',
    this.useSystemColorSettingsKey = 'primary_color_from_system',
    super.key,
  });

  @override
  State<ThemeBuilder> createState() => ThemeController();
}

class ThemeController extends State<ThemeBuilder> {
  ThemeMode? _themeMode;
  Color? _primaryColor;
  bool _useSystemColor = false;

  ThemeMode get themeMode => _themeMode ?? ThemeMode.system;

  /// The color the user picked, or null for the default or the system color.
  Color? get primaryColor => _primaryColor;

  /// Whether the user picked the system's dynamic color.
  bool get useSystemColor => _useSystemColor;

  static ThemeController of(BuildContext context) =>
      Provider.of<ThemeController>(context, listen: false);

  // Reading synchronously before the first build means MaterialApp starts
  // with the saved theme. Applying it a frame later would make MaterialApp
  // animate from the default theme, rebuilding the whole app every frame.
  void _loadData() {
    final preferences = widget.store;

    final rawThemeMode = preferences.getString(widget.themeModeSettingsKey);
    final rawColor = preferences.getInt(widget.primaryColorSettingsKey);

    _themeMode = ThemeMode.values.singleWhereOrNull(
      (value) => value.name == rawThemeMode,
    );
    _primaryColor = rawColor == null ? null : Color(rawColor);
    _useSystemColor =
        rawColor == null &&
        (preferences.getBool(widget.useSystemColorSettingsKey) ?? false);
  }

  Future<void> setThemeMode(ThemeMode newThemeMode) async {
    final preferences = widget.store;
    await preferences.setString(widget.themeModeSettingsKey, newThemeMode.name);
    setState(() {
      _themeMode = newThemeMode;
    });
  }

  /// Picks [newPrimaryColor], or the system's dynamic color when it is null.
  Future<void> setPrimaryColor(Color? newPrimaryColor) async {
    final preferences = widget.store;
    if (newPrimaryColor == null) {
      await preferences.remove(widget.primaryColorSettingsKey);
      await preferences.setBool(widget.useSystemColorSettingsKey, true);
    } else {
      await preferences.setInt(
        widget.primaryColorSettingsKey,
        newPrimaryColor.hexValue,
      );
      await preferences.remove(widget.useSystemColorSettingsKey);
    }
    setState(() {
      _primaryColor = newPrimaryColor;
      _useSystemColor = newPrimaryColor == null;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => this,
      child: widget.builder(
        context,
        themeMode,
        // Null falls back to AppSettings.colorSchemeSeedInt in buildTheme.
        primaryColor ?? (_useSystemColor ? widget.dynamicPrimaryColor : null),
      ),
    );
  }
}
