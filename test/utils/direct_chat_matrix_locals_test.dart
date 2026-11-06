// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DirectChatMatrixLocals locals;

  setUpAll(() async {
    final l10n = await lookupL10n(const Locale('en'));
    locals = DirectChatMatrixLocals(l10n, 'Parla Hoelter');
  });

  test('media previews name the chat partner, not the sender fallback', () {
    for (final preview in [
      locals.sentAPicture('Gmessages 4.42'),
      locals.sentAVideo('Gmessages 4.42'),
      locals.sentAFile('Gmessages 4.42'),
      locals.sentAnAudio('Gmessages 4.42'),
      locals.sentASticker('Gmessages 4.42'),
    ]) {
      expect(preview, contains('Parla Hoelter'));
      expect(preview, isNot(contains('Gmessages')));
    }
  });

  test('other strings keep the sender name', () {
    expect(locals.acceptedTheInvitation('Alice'), contains('Alice'));
  });
}
