// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:matrix/matrix.dart';

/// The phone's address book for New Chat, Android only.
///
/// The entries stay on the device: New Chat only sends a number on to the
/// user's own bridges, and only for a person the user taps.
class PhoneContacts {
  PhoneContacts._();

  static Future<List<PhoneBookEntry>>? _loaded;

  /// Whether this platform has an address book New Chat reads.
  static bool get isSupported => PlatformInfos.isAndroid;

  /// Whether New Chat offers to read the address book: supported, not yet
  /// allowed, and the user has not said no.
  static Future<bool> shouldOffer() async {
    if (!isSupported || AppSettings.phoneContactsDeclined.value) return false;
    return !await isAllowed();
  }

  static Future<bool> isAllowed() async {
    if (!isSupported) return false;
    try {
      return await FlutterContacts.permissions.has(PermissionType.read);
    } catch (e, s) {
      Logs().w('Unable to check the contacts permission', e, s);
      return false;
    }
  }

  /// Asks for the contacts permission. A refusal is remembered so New Chat
  /// does not offer again.
  static Future<bool> request() async {
    if (!isSupported) return false;
    PermissionStatus status;
    try {
      status = await FlutterContacts.permissions.request(PermissionType.read);
    } catch (e, s) {
      Logs().w('Unable to request the contacts permission', e, s);
      status = PermissionStatus.denied;
    }
    final granted =
        status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
    if (!granted) await decline();
    return granted;
  }

  /// Remembers that the user does not want the address book in New Chat.
  static Future<void> decline() =>
      AppSettings.phoneContactsDeclined.setItem(true);

  /// The address book's people with a number or email, read once per app
  /// run. Empty when not allowed.
  static Future<List<PhoneBookEntry>> load() =>
      _loaded ??= _load().then((entries) {
        if (entries.isEmpty) _loaded = null;
        return entries;
      });

  static Future<List<PhoneBookEntry>> _load() async {
    if (!await isAllowed()) return const [];
    try {
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email},
      );
      return [
        for (final contact in contacts)
          if (contact.phones.isNotEmpty || contact.emails.isNotEmpty)
            PhoneBookEntry(
              name: contact.displayName ?? '',
              phones: [
                for (final phone in contact.phones)
                  phone.normalizedNumber ?? phone.number,
              ],
              emails: [for (final email in contact.emails) email.address],
            ),
      ];
    } catch (e, s) {
      Logs().w('Unable to read the phone contacts', e, s);
      return const [];
    }
  }
}
