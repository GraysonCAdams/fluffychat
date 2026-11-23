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

  /// The preferences main() has already loaded, so the saved theme mode and
  /// color are known for the very first frame.
  final SharedPreferences store;

  /// The system's dynamic primary color, resolved before runApp by
  /// loadDynamicPrimaryColor(). Used when the user has not picked a color.
  final Color? dynamicPrimaryColor;

  const ThemeBuilder({
    required this.builder,
    required this.store,
    this.dynamicPrimaryColor,
    this.themeModeSettingsKey = 'theme_mode',
    this.primaryColorSettingsKey = 'primary_color',
    super.key,
  });

  @override
  State<ThemeBuilder> createState() => ThemeController();
}

class ThemeController extends State<ThemeBuilder> {
  ThemeMode? _themeMode;
  Color? _primaryColor;

  ThemeMode get themeMode => _themeMode ?? ThemeMode.system;

  Color? get primaryColor => _primaryColor;

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
  }

  Future<void> setThemeMode(ThemeMode newThemeMode) async {
    final preferences = widget.store;
    await preferences.setString(widget.themeModeSettingsKey, newThemeMode.name);
    setState(() {
      _themeMode = newThemeMode;
    });
  }

  Future<void> setPrimaryColor(Color? newPrimaryColor) async {
    final preferences = widget.store;
    if (newPrimaryColor == null) {
      await preferences.remove(widget.primaryColorSettingsKey);
    } else {
      await preferences.setInt(
        widget.primaryColorSettingsKey,
        newPrimaryColor.hexValue,
      );
    }
    setState(() {
      _primaryColor = newPrimaryColor;
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
        primaryColor ?? widget.dynamicPrimaryColor,
      ),
    );
  }
}
