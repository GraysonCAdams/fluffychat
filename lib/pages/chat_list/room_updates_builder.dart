// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/stream_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Rebuilds [builder] whenever a sync of [client] touches a room, at most once
/// per second, and whenever this widget itself is rebuilt.
///
/// The rate-limited stream is created once per client and kept in the State.
/// Handing a StreamBuilder a stream built inside `build` would subscribe a
/// fresh rate limiter on every parent rebuild, so the one-second throttle
/// would never hold.
class RoomUpdatesBuilder extends StatefulWidget {
  final Client client;
  final WidgetBuilder builder;

  const RoomUpdatesBuilder({
    required this.client,
    required this.builder,
    super.key,
  });

  @override
  State<RoomUpdatesBuilder> createState() => _RoomUpdatesBuilderState();
}

class _RoomUpdatesBuilderState extends State<RoomUpdatesBuilder> {
  StreamSubscription<bool>? _subscription;

  void _subscribe() {
    _subscription?.cancel();
    _subscription = widget.client.onSync.stream
        .where((s) => s.hasRoomUpdate)
        .rateLimit(const Duration(seconds: 1))
        .listen((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant RoomUpdatesBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
