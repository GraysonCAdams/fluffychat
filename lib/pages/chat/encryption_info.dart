// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class EncryptionInfo extends StatefulWidget {
  final Room room;

  const EncryptionInfo({super.key, required this.room});

  @override
  State<EncryptionInfo> createState() => _EncryptionInfoState();
}

class _EncryptionInfoState extends State<EncryptionInfo> {
  Room get room => widget.room;

  /// Members of the room as last fetched. Fetching can hit the database and
  /// the network, so it only happens on open and when a sync reports a
  /// membership or encryption change, never on a plain rebuild.
  List<User>? _participants;
  bool _loadingParticipants = false;
  bool _reloadParticipants = false;

  int _unverifiedDevices = 0;

  /// Counting walks every member's device signatures in memory. A rebuild of
  /// the timeline recounts at most this often, so a device verified on
  /// another screen still shows up without paying for it on every frame.
  static const _recountInterval = Duration(seconds: 1);
  DateTime? _lastCount;

  StreamSubscription<SyncUpdate>? _syncSubscription;

  late final TapGestureRecognizer _checkRecognizer = TapGestureRecognizer()
    ..onTap = () => context.go('/rooms/${room.id}/encryption');

  @override
  void initState() {
    super.initState();
    _subscribe();
    _loadParticipants();
  }

  @override
  void didUpdateWidget(covariant EncryptionInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != room.id || oldWidget.room.client != room.client) {
      _syncSubscription?.cancel();
      _subscribe();
      _participants = null;
      _loadParticipants();
      return;
    }
    final lastCount = _lastCount;
    if (lastCount == null ||
        DateTime.now().difference(lastCount) >= _recountInterval) {
      _recount(notify: false);
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _checkRecognizer.dispose();
    super.dispose();
  }

  void _subscribe() {
    _syncSubscription = room.client.onSync.stream.listen(_onSync);
  }

  void _onSync(SyncUpdate sync) {
    final roomUpdate = sync.rooms?.join?[room.id];
    final membershipChanged =
        [...?roomUpdate?.state, ...?roomUpdate?.timeline?.events].any(
          (event) =>
              event.type == EventTypes.RoomMember ||
              event.type == EventTypes.Encryption,
        );
    if (membershipChanged) {
      _loadParticipants();
      return;
    }
    // Device list changes and to-device traffic (verification, key sharing)
    // can flip a device's trust without touching the member list.
    final devicesChanged =
        (sync.deviceLists?.changed?.isNotEmpty ?? false) ||
        (sync.deviceLists?.left?.isNotEmpty ?? false) ||
        (sync.toDevice?.isNotEmpty ?? false);
    if (devicesChanged) _recount();
  }

  Future<void> _loadParticipants() async {
    if (!room.encrypted) {
      _recount();
      return;
    }
    if (_loadingParticipants) {
      _reloadParticipants = true;
      return;
    }
    _loadingParticipants = true;
    try {
      do {
        _reloadParticipants = false;
        final participants = await room.requestParticipants();
        if (!mounted) return;
        _participants = participants;
      } while (_reloadParticipants);
    } catch (e, s) {
      Logs().d('Unable to load participants for encryption info', e, s);
    } finally {
      _loadingParticipants = false;
    }
    _recount();
  }

  void _recount({bool notify = true}) {
    if (!mounted) return;
    _lastCount = DateTime.now();
    final participants = _participants;
    var count = 0;
    // An unencrypted room loads no members; once encryption is switched on
    // the sync carrying that state event triggers the load.
    if (room.encrypted && participants != null) {
      count = participants
          .map((user) => room.client.userDeviceKeys[user.id])
          .nonNulls
          .expand((devicesKeysList) => devicesKeysList.deviceKeys.values)
          .where(
            (device) =>
                !device.verified &&
                !device.blocked &&
                !device.hasValidSignatureChain(
                  verifiedByTheirMasterKey: true,
                ) &&
                device.encryptToDevice,
          )
          .length;
    }
    if (count == _unverifiedDevices) return;
    if (notify) {
      setState(() => _unverifiedDevices = count);
    } else {
      // Called from didUpdateWidget, which is followed by a build anyway.
      _unverifiedDevices = count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: Builder(
        builder: (context) {
          final unverifiedDevices = _unverifiedDevices;
          if (unverifiedDevices == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: theme.colorScheme.surface.withAlpha(128),
                  borderRadius: BorderRadius.circular(
                    AppConfig.borderRadius / 3,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            child: Icon(Icons.lock_person_outlined, size: 13),
                          ),
                          TextSpan(text: ' '),
                          TextSpan(
                            text: L10n.of(
                              context,
                            ).countUnverifiedDevices(unverifiedDevices),
                          ),
                          TextSpan(text: ' '),
                          TextSpan(
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: theme.colorScheme.primary,
                            ),
                            recognizer: _checkRecognizer,
                            text: 'Check',
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
