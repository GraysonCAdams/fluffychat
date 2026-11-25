// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:matrix/matrix.dart';

// The order of the pinned row, kept as the `order` of each room's
// `m.favourite` tag (a number from 0 to 1, lowest first), so other Matrix
// clients and devices see the same order. The SDK's room sort does not read
// it; the pinned row sorts by it itself.

/// The rooms that carry the pin of a listed chat: every pinned room of a
/// merged contact, else the room itself.
List<Room> pinnedRoomsOf(Room room, MergedContact? contact) => contact == null
    ? [room]
    : [
        for (final member in contact.rooms)
          if (member.isFavourite) member,
      ];

/// The order stored on the favourite tag of [room], if any.
double? storedPinOrder(Room room) => room.tags[TagType.favourite]?.order;

/// The lowest of [orders], ignoring missing ones. A merged contact has the
/// same order on all its pinned rooms, unless another client changed one.
double? lowestPinOrder(Iterable<double?> orders) {
  double? lowest;
  for (final order in orders) {
    if (order == null) continue;
    if (lowest == null || order < lowest) lowest = order;
  }
  return lowest;
}

/// [pins] in the order of the row: those with an order by that order, then
/// those without one in the order given (the client's, newest first).
/// Equal orders keep the order given.
List<T> sortPins<T>(List<T> pins, double? Function(T pin) orderOf) {
  final orders = [for (final pin in pins) orderOf(pin)];
  final indexes = List.generate(pins.length, (i) => i)
    ..sort((a, b) {
      final orderA = orders[a];
      final orderB = orders[b];
      if (orderA == null && orderB == null) return a.compareTo(b);
      if (orderA == null) return 1;
      if (orderB == null) return -1;
      final byOrder = orderA.compareTo(orderB);
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });
  return [for (final i in indexes) pins[i]];
}

/// The orders to store after the pin at [from] moves to [to], given the
/// current [orders] of the row in row order (see [sortPins]). [to] is the
/// pin's index once moved. The result maps indexes in the new row order to
/// their new order.
///
/// Usually only the moved pin changes, to the midpoint of its new
/// neighbours (0 and 1 stand in at the ends). Pins without an order that
/// end up before it get orders too, spread evenly, so they keep their place
/// ahead of it. When there is no room left between the neighbours, every
/// pin is numbered evenly from scratch.
Map<int, double> pinOrdersAfterMove(List<double?> orders, int from, int to) {
  final rest = List.of(orders)..removeAt(from);
  var ordered = rest.indexWhere((order) => order == null);
  if (ordered == -1) ordered = rest.length;

  if (to <= ordered) {
    final lower = to == 0 ? 0.0 : rest[to - 1]!;
    final upper = to < ordered ? rest[to]! : 1.0;
    final middle = (lower + upper) / 2;
    if (lower < middle && middle < upper) return {to: middle};
  } else {
    // The unordered pins from [ordered] up to the drop get orders after
    // the last ordered pin, then the moved pin after them.
    final lower = ordered == 0 ? 0.0 : rest[ordered - 1]!;
    final count = to - ordered + 1;
    final step = (1 - lower) / (count + 1);
    final spread = {
      for (var i = 0; i < count; i++) ordered + i: lower + step * (i + 1),
    };
    if (step > 0 &&
        lower < spread[ordered]! &&
        spread[ordered + count - 1]! < 1) {
      return spread;
    }
  }
  return {
    for (var i = 0; i < orders.length; i++) i: (i + 1) / (orders.length + 1),
  };
}
