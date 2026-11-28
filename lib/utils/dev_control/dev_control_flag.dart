// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Whether this build carries the dev control server (docs/dev-control.md).
///
/// Only a build made with `--dart-define=SEAM_DEV_CONTROL=true` has it. The
/// value is a compile-time constant, so in every other build the call that
/// starts the server is dead code and the AOT compiler drops the server with
/// it; `tools/devctl/check_stripped.sh` checks a built binary for that.
const bool kDevControlEnabled = bool.fromEnvironment('SEAM_DEV_CONTROL');

/// The loopback port the server tries first, set with
/// `--dart-define=SEAM_DEV_CONTROL_PORT=<port>`. When it is taken the server
/// takes any free port; the token file names the one it got.
const int kDevControlPort = int.fromEnvironment(
  'SEAM_DEV_CONTROL_PORT',
  defaultValue: 47913,
);
