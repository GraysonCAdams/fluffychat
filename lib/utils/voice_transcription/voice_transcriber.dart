// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

export 'voice_transcriber_stub.dart'
    if (dart.library.ffi) 'voice_transcriber_io.dart';
