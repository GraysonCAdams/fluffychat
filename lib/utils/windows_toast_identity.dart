// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as path;

/// The AppUserModelIDs Seam posted toasts under before
/// [AppConfig.seamApplicationId]. Windows keeps the name and icon it first
/// saw for an ID, so toasts under these kept the name "FluffyChat" and no
/// icon whatever was registered later.
const retiredToastIds = ['im.fluffychat.app'];

/// Test registrations of the toast icon, left by trying icons out.
const _iconExperimentIds = [
  'im.fluffychat.icontest',
  'im.fluffychat.icontest3',
  'im.fluffychat.icontest5',
];

const _aumidKey = r'HKCU\Software\Classes\AppUserModelId';
const _settingsKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings';

/// Runs `reg.exe` (or a stand-in) with [arguments].
typedef RegistryRunner = Future<ProcessResult> Function(List<String> arguments);

Future<ProcessResult> _reg(List<String> arguments) =>
    Process.run('reg', arguments);

/// Whether a toast registration with these values was written by Seam, as
/// opposed to another app that happens to use the same ID, such as an
/// installed FluffyChat.
bool isSeamToastRegistration({String? displayName, String? iconUri}) =>
    displayName == 'Seam' ||
    (iconUri?.toLowerCase().contains('seam_app_icon') ?? false);

String? _valueOf(String regQuery, String name) {
  final match = RegExp(
    '^\\s*$name\\s+REG_\\w+\\s+(.*?)\\s*\$',
    multiLine: true,
  ).firstMatch(regQuery);
  return match?.group(1);
}

/// Removes the toast registrations Seam wrote under [retiredToastIds] and
/// the icon experiments, so Windows has one registration to show. A
/// registration under a retired ID that is not Seam's is left alone: an
/// installed FluffyChat may own it. Failures are logged, never thrown.
Future<void> retireOldToastIdentities({RegistryRunner run = _reg}) async {
  try {
    for (final id in retiredToastIds) {
      final query = await run(['query', '$_aumidKey\\$id']);
      if (query.exitCode != 0) continue;
      final text = '${query.stdout}';
      if (!isSeamToastRegistration(
        displayName: _valueOf(text, 'DisplayName'),
        iconUri: _valueOf(text, 'IconUri'),
      )) {
        continue;
      }
      await run(['delete', '$_aumidKey\\$id', '/f']);
    }
    for (final id in _iconExperimentIds) {
      for (final key in [_aumidKey, _settingsKey]) {
        final target = '$key\\$id';
        if ((await run(['query', target])).exitCode == 0) {
          await run(['delete', target, '/f']);
        }
      }
    }
  } catch (e, s) {
    Logs().w('Unable to clean up old toast registrations', e, s);
  }
}

/// The icon Windows shows in a toast's header, a path that stays valid
/// when the app is updated or moved: [bundledIcon] copied into [directory]
/// (the Windows toast registry holds this path) under its own file name.
/// Falls back to [bundledIcon] itself when the copy cannot be made.
String stableToastIconPath({
  required String bundledIcon,
  required Directory directory,
}) {
  try {
    final target = File(path.join(directory.path, path.basename(bundledIcon)));
    final source = File(bundledIcon);
    if (!target.existsSync() ||
        !listEquals(target.readAsBytesSync(), source.readAsBytesSync())) {
      directory.createSync(recursive: true);
      source.copySync(target.path);
    }
    return target.path;
  } catch (e, s) {
    Logs().w('Unable to keep a copy of the toast icon', e, s);
    return bundledIcon;
  }
}

/// The glyph a toast shows on a light or a dark Windows theme: the duotone
/// Seam glyph as in the tray, white on dark, cobalt on light. A toast of an
/// unpackaged app has one registered icon, so the app swaps it with the
/// theme (see [refreshToastIcon]); the theme is in the file name so a
/// registration cache keyed by path cannot serve the other theme's glyph.
String toastIconAsset({required bool lightTheme}) =>
    lightTheme ? 'toast_icon_light.png' : 'toast_icon_dark.png';

/// Whether `reg query` output for `SystemUsesLightTheme` (the Windows mode
/// the taskbar, Start and toasts follow) says light; null when it says
/// nothing.
bool? parseLightTheme(String regQueryOutput) {
  final match = RegExp(
    r'SystemUsesLightTheme\s+REG_DWORD\s+0x([0-9a-fA-F]+)',
  ).firstMatch(regQueryOutput);
  final value = int.tryParse(match?.group(1) ?? '', radix: 16);
  return value == null ? null : value != 0;
}

const _personalizeKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';

/// Runs `reg.exe` (or a stand-in) and waits for it.
typedef RegistryRunnerSync = ProcessResult Function(List<String> arguments);

ProcessResult _regSync(List<String> arguments) =>
    Process.runSync('reg', arguments);

/// Whether Windows is in light mode; dark when it cannot be read, as
/// Windows is unless set otherwise.
bool systemUsesLightTheme({RegistryRunnerSync run = _regSync}) {
  try {
    final result = run(['query', _personalizeKey, '/v', 'SystemUsesLightTheme']);
    return result.exitCode == 0 && (parseLightTheme('${result.stdout}') ?? false);
  } catch (e, s) {
    Logs().w('Unable to read the Windows theme', e, s);
    return false;
  }
}

/// The theme the registered toast icon is for.
bool? _registeredLightTheme;

/// The toast icon for the current Windows theme: the glyph of
/// [toastIconAsset] shipped with the app, kept under `%LOCALAPPDATA%\Seam`.
String windowsToastIcon({bool? lightTheme, Directory? directory}) {
  final light = lightTheme ?? systemUsesLightTheme();
  _registeredLightTheme = light;
  final bundled = path.join(
    File(Platform.resolvedExecutable).parent.path,
    'data',
    'flutter_assets',
    'assets',
    'seam',
    toastIconAsset(lightTheme: light),
  );
  final base = Platform.environment['LOCALAPPDATA'];
  if (base == null && directory == null) return bundled;
  return stableToastIconPath(
    bundledIcon: bundled,
    directory: directory ?? Directory(path.join(base!, 'Seam')),
  );
}

/// Points the toast icon at the glyph for the current Windows theme if the
/// theme changed since it was registered. Called before a toast goes out,
/// so a switch between light and dark shows in the next toast whether or not
/// the app restarted. Never throws.
Future<void> refreshToastIcon({
  bool? lightTheme,
  Directory? directory,
  RegistryRunner run = _reg,
}) async {
  try {
    final light = lightTheme ?? systemUsesLightTheme();
    if (light == _registeredLightTheme) return;
    final icon = windowsToastIcon(lightTheme: light, directory: directory);
    await run([
      'add',
      '$_aumidKey\\${AppConfig.seamApplicationId}',
      '/v',
      'IconUri',
      '/t',
      'REG_SZ',
      '/d',
      icon,
      '/f',
    ]);
  } catch (e, s) {
    Logs().w('Unable to change the toast icon for the Windows theme', e, s);
  }
}
