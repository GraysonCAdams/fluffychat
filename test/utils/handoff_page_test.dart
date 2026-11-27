// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/handoff_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('a handoff is taken once, and a cancelled one not at all', () {
    expect(PageHandoff.take(), isFalse);
    PageHandoff.expect();
    expect(PageHandoff.take(), isTrue);
    expect(PageHandoff.take(), isFalse);
    PageHandoff.expect();
    PageHandoff.cancel();
    expect(PageHandoff.take(), isFalse);
  });

  testWidgets('a handoff page enters at once and leaves as a page does', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // A route reads its transition from the theme once it is on a
    // navigator.
    Future<TransitionRoute> pushed(Page page) async {
      final route = page.createRoute(context) as TransitionRoute;
      Navigator.of(context).push(route);
      await tester.pumpAndSettle();
      return route;
    }

    final usual = await pushed(const MaterialPage(child: SizedBox()));
    final instant = await pushed(
      const HandoffPage(enterInstantly: true, child: SizedBox()),
    );
    final plain = await pushed(const HandoffPage(child: SizedBox()));
    expect(instant.transitionDuration, Duration.zero);
    expect(instant.reverseTransitionDuration, usual.reverseTransitionDuration);
    expect(plain.transitionDuration, usual.transitionDuration);
    expect(plain.reverseTransitionDuration, usual.reverseTransitionDuration);
  });
}
