// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/windows_startup_entry.dart';
import 'package:flutter_test/flutter_test.dart';

const _seam = r'C:\src\fluffychat-search\build\fluffychat.exe';

String _entry(String command) =>
    '\r\nHKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\r\n'
    '    FluffyChat    REG_SZ    $command\r\n\r\n';

void main() {
  test('a login entry that starts this executable is its own', () {
    expect(runEntryStartsExecutable(_entry('"$_seam" --hidden'), _seam), isTrue);
    expect(
      runEntryStartsExecutable(_entry('"${_seam.toUpperCase()}" --hidden'), _seam),
      isTrue,
    );
  });

  test('the entry of another install is not', () {
    expect(
      runEntryStartsExecutable(
        _entry(r'"C:\Users\gray\AppData\Local\Programs\FluffyChat\fluffychat.exe"'),
        _seam,
      ),
      isFalse,
    );
    expect(runEntryStartsExecutable('', _seam), isFalse);
  });

  group('retiring the old login entry', () {
    late List<String> calls;
    Future<ProcessResult> Function(List<String>) runner(String command) =>
        (args) async {
          calls.add(args.join(' '));
          return ProcessResult(0, 0, args.first == 'query' ? _entry(command) : '', '');
        };

    setUp(() => calls = []);

    test('removes the one this executable made', () async {
      await retireOldRunEntry(_seam, run: runner('"$_seam" --hidden'));
      expect(calls.where((c) => c.startsWith('delete')), hasLength(1));
      expect(calls.last, contains('/v $retiredRunValueName'));
    });

    test('leaves an installed FluffyChat its own', () async {
      await retireOldRunEntry(
        _seam,
        run: runner(r'"C:\Users\gray\AppData\Local\Programs\FluffyChat\fluffychat.exe"'),
      );
      expect(calls.where((c) => c.startsWith('delete')), isEmpty);
    });

    test('has nothing to do without one', () async {
      await retireOldRunEntry(
        _seam,
        run: (args) async {
          calls.add(args.join(' '));
          return ProcessResult(0, 1, '', 'not found');
        },
      );
      expect(calls, hasLength(1));
    });

    test('never throws', () async {
      await retireOldRunEntry(
        _seam,
        run: (_) async => throw const ProcessException('reg', []),
      );
    });
  });
}
