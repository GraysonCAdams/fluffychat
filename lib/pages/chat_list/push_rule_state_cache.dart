// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

/// [Room.pushRuleState] without parsing the whole push rule set per call.
///
/// The SDK getter runs `PushRuleSet.fromJson` over the account's global push
/// rules every time it is read, and the chat list reads it once per visible
/// tile on every rebuild. The parsed set is kept here against the identity of
/// the `m.push_rules` account data event: the SDK stores a new event object
/// whenever that account data changes, so a different object means the
/// rules changed and are parsed again.
extension CachedPushRuleState on Room {
  static BasicEvent? _parsedFrom;
  static PushRuleSet? _parsed;

  static PushRuleSet? _globalPushRules(Client client) {
    final event = client.accountData[EventTypes.PushRules];
    if (event == null) return null;
    if (identical(event, _parsedFrom)) return _parsed;
    final global = event.content.tryGetMap<String, Object?>('global');
    PushRuleSet? parsed;
    if (global != null) {
      // Same fallback as the SDK's client.globalPushRules: malformed rules
      // count as an empty set rather than as no rules at all.
      try {
        parsed = PushRuleSet.fromJson(global);
      } catch (e, s) {
        Logs().v('Malformed PushRuleSet', e, s);
        parsed = PushRuleSet.fromJson({});
      }
    }
    _parsedFrom = event;
    _parsed = parsed;
    return parsed;
  }

  /// True when a rule's actions are empty once the SDK has dropped the first
  /// "dont_notify" and the first "coalesce", which the spec says to ignore.
  /// List.remove only drops the first match, so this copies that exactly.
  static bool _hasNoActions(PushRule rule) {
    final actions = List.of(rule.actions)
      ..remove('dont_notify')
      ..remove('coalesce');
    return actions.isEmpty;
  }

  /// Equal to [Room.pushRuleState] for the current account data. Override
  /// rules are checked before room rules, and only the first rule whose id is
  /// this room's id counts in each list.
  PushRuleState get cachedPushRuleState {
    final globalPushRules = _globalPushRules(client);
    if (globalPushRules == null) return PushRuleState.notify;

    final overrideRule = globalPushRules.override?.firstWhereOrNull(
      (rule) => rule.ruleId == id,
    );
    if (overrideRule != null && _hasNoActions(overrideRule)) {
      return PushRuleState.dontNotify;
    }

    final roomRule = globalPushRules.room?.firstWhereOrNull(
      (rule) => rule.ruleId == id,
    );
    if (roomRule != null && _hasNoActions(roomRule)) {
      return PushRuleState.mentionsOnly;
    }

    return PushRuleState.notify;
  }
}
