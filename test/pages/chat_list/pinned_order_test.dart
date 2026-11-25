// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/pinned_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sortPins', () {
    test('puts ordered pins first, lowest first, then the rest as given', () {
      final orders = {'a': null, 'b': 0.75, 'c': null, 'd': 0.25, 'e': 0.75};
      expect(sortPins(orders.keys.toList(), (pin) => orders[pin]), [
        'd',
        'b',
        'e',
        'a',
        'c',
      ]);
    });
  });

  group('pinOrdersAfterMove', () {
    test('gives the moved pin the midpoint of its new neighbours', () {
      expect(pinOrdersAfterMove([0.25, 0.5, 0.75], 2, 1), {1: 0.375});
    });

    test('uses 0 and 1 at the ends of the row', () {
      expect(pinOrdersAfterMove([0.25, 0.5, 0.75], 1, 0), {0: 0.125});
      expect(pinOrdersAfterMove([0.25, 0.5, 0.75], 0, 2), {2: 0.875});
    });

    test('numbers every pin evenly when the neighbours leave no room', () {
      expect(pinOrdersAfterMove([0.5, 0.5, 0.75], 2, 1), {
        0: 0.25,
        1: 0.5,
        2: 0.75,
      });
      // An order past 1, as another client might write.
      expect(pinOrdersAfterMove([0.2, 1.5], 0, 1), {0: 1 / 3, 1: 2 / 3});
    });

    test('orders the unordered pins that end up before the moved one', () {
      expect(pinOrdersAfterMove([0.5, null, null, null], 3, 2), {
        1: 0.5 + 0.5 / 3,
        2: 0.5 + 0.5 / 3 * 2,
      });
    });

    test('a pin moved before every unordered pin gets an order alone', () {
      expect(pinOrdersAfterMove([null, null, null], 2, 0), {0: 0.5});
      expect(pinOrdersAfterMove([0.5, null, null], 2, 1), {1: 0.75});
    });
  });
}
