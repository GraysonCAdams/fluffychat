// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// Web build stand-in for `spell_check_ffi.dart`; browsers check spelling in
/// their own text fields.
SpellCheckConfiguration? messageSpellCheckConfiguration() => null;
