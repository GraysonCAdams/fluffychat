// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/windows_toast_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _registration(String name, String icon) =>
    '\r\nHKEY_CURRENT_USER\\Software\\Classes\\AppUserModelId\\x\r\n'
    '    DisplayName    REG_SZ    $name\r\n'
    '    IconUri    REG_SZ    $icon\r\n\r\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Seam toasts have an id of their own', () {
    expect(AppConfig.seamApplicationId, 'dev.threeonetwo.seam');
    for (final retired in retiredToastIds) {
      expect(AppConfig.seamApplicationId, isNot(retired));
    }
  });

  test('the toast identity registers under the Seam id', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    final settings = ClientManager.windowsNotificationSettings();
    expect(settings.appUserModelId, AppConfig.seamApplicationId);
    expect(settings.appName, 'Seam');
  });

  group('registrations Seam wrote under an earlier id', () {
    late List<String> calls;
    late Map<String, String> registry;

    Future<ProcessResult> run(List<String> args) async {
      calls.add(args.join(' '));
      final key = args[1];
      final value = registry[key];
      return switch (args.first) {
        'query' => ProcessResult(0, value == null ? 1 : 0, value ?? '', ''),
        _ => ProcessResult(0, 0, '', ''),
      };
    }

    setUp(() {
      calls = [];
      registry = {};
    });

    const old = r'HKCU\Software\Classes\AppUserModelId\im.fluffychat.app';

    test('are removed', () async {
      registry[old] = _registration('Seam', r'C:\b\seam_app_icon.png');
      await retireOldToastIdentities(run: run);
      expect(calls, contains('delete $old /f'));
    });

    test('are left when an installed FluffyChat owns them', () async {
      registry[old] = _registration('FluffyChat', r'C:\fc\app_icon.ico');
      await retireOldToastIdentities(run: run);
      expect(calls.where((c) => c.startsWith('delete')), isEmpty);
    });

    test('icon experiments go, from both keys', () async {
      const test3 = r'HKCU\Software\Classes\AppUserModelId\im.fluffychat.icontest3';
      const test3Settings =
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\im.fluffychat.icontest3';
      registry[test3] = _registration('x', 'y');
      registry[test3Settings] = '';
      await retireOldToastIdentities(run: run);
      expect(calls, contains('delete $test3 /f'));
      expect(calls, contains('delete $test3Settings /f'));
      expect(calls.where((c) => c.startsWith('delete')), hasLength(2));
    });

    test('a registry that cannot be read is not an error', () async {
      await retireOldToastIdentities(
        run: (_) async => throw const ProcessException('reg', []),
      );
    });
  });

  group('the toast icon', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('toast_icon'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('is a copy that outlives the build it came from', () {
      final bundled = File('${temp.path}/build/icon.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final dir = Directory('${temp.path}/local/Seam');
      final path = stableToastIconPath(
        bundledIcon: bundled.path,
        directory: dir,
      );
      expect(path, startsWith(dir.path));
      Directory('${temp.path}/build').deleteSync(recursive: true);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('follows a changed icon of the same size', () {
      final bundled = File('${temp.path}/icon.png')
        ..writeAsBytesSync([1, 2, 3]);
      final dir = Directory('${temp.path}/Seam');
      stableToastIconPath(bundledIcon: bundled.path, directory: dir);
      bundled.writeAsBytesSync([3, 2, 1]);
      final path = stableToastIconPath(
        bundledIcon: bundled.path,
        directory: dir,
      );
      expect(File(path).readAsBytesSync(), [3, 2, 1]);
    });

    test('is the bundled icon when no copy can be made', () {
      final bundled = File('${temp.path}/icon.png')
        ..writeAsBytesSync([1, 2, 3]);
      final blocker = File('${temp.path}/file')..writeAsBytesSync([0]);
      expect(
        stableToastIconPath(
          bundledIcon: bundled.path,
          directory: Directory('${blocker.path}/Seam'),
        ),
        bundled.path,
      );
    });
  });
}
