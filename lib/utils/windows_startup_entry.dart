// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:matrix/matrix.dart';

/// The name of Seam's per-user login entry under
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
const seamRunValueName = 'Seam';

/// The name builds of Seam before it had its own identity used for that
/// entry, the same one an installed FluffyChat would use.
const retiredRunValueName = 'FluffyChat';

const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

/// Whether `reg query` output for a Run value shows a command that starts
/// [executable], so the entry is this app's and not another install's.
bool runEntryStartsExecutable(String regQueryOutput, String executable) {
  final match = RegExp(
    r'REG_(?:EXPAND_)?SZ\s+(.*?)\s*$',
    multiLine: true,
  ).firstMatch(regQueryOutput);
  final command = match?.group(1)?.replaceAll('"', '').toLowerCase();
  return command != null && command.startsWith(executable.toLowerCase());
}

/// Removes the login entry an earlier Seam build wrote under
/// [retiredRunValueName], but only when it starts this executable; an
/// installed FluffyChat keeps its own. Never throws.
Future<void> retireOldRunEntry(
  String executable, {
  Future<ProcessResult> Function(List<String> arguments) run = _reg,
}) async {
  try {
    final query = await run(['query', _runKey, '/v', retiredRunValueName]);
    if (query.exitCode != 0) return;
    if (!runEntryStartsExecutable('${query.stdout}', executable)) return;
    await run(['delete', _runKey, '/v', retiredRunValueName, '/f']);
  } catch (e, s) {
    Logs().w('Unable to remove the old login entry', e, s);
  }
}

Future<ProcessResult> _reg(List<String> arguments) =>
    Process.run('reg', arguments);
