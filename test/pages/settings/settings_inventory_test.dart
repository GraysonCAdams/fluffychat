// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The feature inventory of the settings pages: every setting, link and
// action each page offers, found by what the user sees (labels, tooltips,
// controls) and by what a tap does (a stored value, a route, a dialog),
// never by how the page is laid out.

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:fluffychat/pages/settings_chat/settings_swipe_actions.dart';
import 'package:fluffychat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:fluffychat/pages/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/pages/settings_matrix_features/settings_matrix_features.dart';
import 'package:fluffychat/pages/settings_merged_contacts/settings_merged_contacts.dart';
import 'package:fluffychat/pages/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/pages/settings_password/settings_password.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/pages/settings_style/settings_style.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../chat_list/chat_list_fakes.dart';
import 'settings_fakes.dart';

void main() {
  late FakeSettingsClient client;
  late GoRouter router;
  late PushCounter pushes;
  late L10n l10n;

  setUpAll(() async => l10n = await lookupL10n(const Locale('en')));

  setUp(() async {
    client = await setUpFakeSettings('settings inventory');
  });

  /// Opens the page at [location] on a surface tall enough to lay out all
  /// of it, so nothing has to be scrolled to.
  Future<void> open(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(500, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pushes = PushCounter();
    router = fakeSettingsRouter(location, observer: pushes);
    await pumpFakeSettings(tester, client, router);
  }

  String location() => router.routeInformationProvider.value.uri.path;

  void expectTexts(Iterable<String> texts) {
    for (final text in texts) {
      expect(find.text(text), findsWidgets, reason: 'label "$text"');
    }
  }

  /// The row or button showing [label] reacts to a tap.
  void expectTappable(String label) {
    final inks = find.ancestor(
      of: find.text(label).last,
      matching: find.byWidgetPredicate(
        (widget) => widget is InkResponse && widget.onTap != null,
      ),
    );
    expect(inks, findsWidgets, reason: '"$label" can be tapped');
  }

  /// Tapping each label flips the setting stored for it, and again flips
  /// it back.
  Future<void> expectToggles(
    WidgetTester tester,
    Map<String, AppSettings<bool?>> toggles,
  ) async {
    for (final MapEntry(key: label, value: setting) in toggles.entries) {
      // Nothing is stored for a setting never changed.
      bool read() => setting.value ?? setting.defaultValue ?? false;
      final before = read();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(read(), !before, reason: '"$label" toggles ${setting.key}');
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(read(), before, reason: '"$label" toggles back');
    }
  }

  /// Tapping each label goes to its page.
  Future<void> expectLinks(
    WidgetTester tester,
    String from,
    Map<String, String> links,
  ) async {
    for (final MapEntry(key: label, value: path) in links.entries) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(location(), path, reason: '"$label" opens $path');
      router.go(from);
      await tester.pumpAndSettle();
    }
  }

  /// Tapping each label puts a dialog, sheet or page over the settings
  /// page.
  Future<void> expectOpens(WidgetTester tester, Iterable<String> labels) async {
    for (final label in labels) {
      final before = pushes.pushes;
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(pushes.pushes, before + 1, reason: '"$label" opens something');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
    }
  }

  void expectSwitches(int count) =>
      expect(find.byType(Switch), findsNWidgets(count), reason: 'switches');

  testWidgets('settings home', (tester) async {
    await open(tester, '/rooms/settings');
    expect(find.byType(Settings), findsOneWidget);
    expectTexts([
      l10n.settings,
      FakeSettingsClient.displayName,
      MatrixFeatures.forClient(client).userLabel(client.userID!),
      l10n.chatBackup,
      l10n.manageAccount,
      l10n.changeTheme,
      l10n.notifications,
      l10n.chat,
      l10n.devices,
      l10n.security,
      l10n.aboutHomeserver('x'),
      l10n.addAccount,
      l10n.about,
      l10n.logout,
    ]);
    // The profile: change the avatar, rename, share the ID.
    expect(find.byTooltip(l10n.changeYourAvatar), findsOneWidget);
    expectTappable(MatrixFeatures.forClient(client).userLabel(client.userID!));
    // The account page opens in the browser.
    expectTappable(l10n.manageAccount);
    expect(find.byIcon(Icons.open_in_new_outlined), findsOneWidget);
    // Chat backup is the one switch.
    expectSwitches(1);
    await expectLinks(tester, '/rooms/settings', {
      l10n.changeTheme: '/rooms/settings/style',
      l10n.notifications: '/rooms/settings/notifications',
      l10n.chat: '/rooms/settings/chat',
      l10n.devices: '/rooms/settings/devices',
      l10n.security: '/rooms/settings/security',
      l10n.aboutHomeserver('x'): '/rooms/settings/homeserver',
      l10n.addAccount: '/rooms/settings/addaccount',
    });
    await expectOpens(tester, [
      FakeSettingsClient.displayName,
      l10n.chatBackup,
      l10n.logout,
    ]);
    // About reads the app version from the platform before its dialog
    // opens.
    await tester.tap(find.text(l10n.about).last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    // Back leaves settings for the chat list.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(location(), '/rooms');
    await finishFakeSettings(tester, client);
  });

  testWidgets('settings home links the privacy policy when one is set', (
    tester,
  ) async {
    await AppSettings.privacyPolicy.setItem('https://x/privacy');
    addTearDown(() => AppSettings.store.remove(AppSettings.privacyPolicy.key));
    await open(tester, '/rooms/settings');
    expectTexts([l10n.privacy]);
    expectTappable(l10n.privacy);
    await finishFakeSettings(tester, client);
  });

  testWidgets('chat settings', (tester) async {
    await MatrixFeatures.forClient(
      client,
    ).setMode(MatrixFeaturesMode.alwaysShow);
    addFakeSpace(client, '!hidden:x', 'Signal', const []);
    await AppSettings.railHiddenSpaces.setItem(['!hidden:x']);
    await AppSettings.doubleTapToReact.setItem(true);
    await open(tester, '/rooms/settings/chat');
    expect(find.byType(SettingsChat), findsOneWidget);
    expectTexts([
      l10n.chat,
      l10n.formattedMessagesDescription,
      l10n.hideRedactedMessagesBody,
      l10n.openSpacesAsChatListDescription,
      l10n.suggestContactsFromChatsDescription,
      l10n.recordVoiceMessagesDescription,
      l10n.doubleTapToReactDescription,
      l10n.doubleTapReaction,
      AppSettings.doubleTapReaction.value,
      l10n.swipeActions,
      swipeActionsSummary(l10n),
      l10n.hiddenFromRail,
      'Signal',
      l10n.mergedContacts,
      l10n.mergedContactsDescription,
      l10n.matrixFeatures,
      l10n.matrixFeaturesDescription,
      l10n.customEmojisAndStickers,
      l10n.customEmojisAndStickersBody,
    ]);
    final toggles = <String, AppSettings<bool?>>{
      l10n.formattedMessages: AppSettings.renderHtml,
      l10n.hideRedactedMessages: AppSettings.hideRedactedEvents,
      l10n.hideRoomsInSpaces: AppSettings.hideRoomsInSpaces,
      l10n.openSpacesAsChatList: AppSettings.openSpacesAsChatList,
      l10n.suggestContactsFromChats: AppSettings.suggestContactsFromChats,
      l10n.hideInvalidOrUnknownMessageFormats: AppSettings.hideUnknownEvents,
      if (PlatformInfos.isWindows) l10n.closeToTray: AppSettings.closeToTray,
      if (PlatformInfos.isMobile)
        l10n.autoplayImages: AppSettings.autoplayImages,
      l10n.sendOnEnter: AppSettings.sendOnEnter,
      l10n.recordVoiceMessages: AppSettings.voiceMessages,
      l10n.swipeRightToLeftToReply: AppSettings.swipeRightToLeftToReply,
      l10n.showThumbnailsInTimeline: AppSettings.showThumbnailsInTimeline,
    };
    // Launch at startup writes to the system when toggled, so it is only
    // looked for.
    if (PlatformInfos.isWindows) expectTexts([l10n.launchAtStartup]);
    expectSwitches(toggles.length + 1 + (PlatformInfos.isWindows ? 1 : 0));
    await expectToggles(tester, toggles);
    await expectLinks(tester, '/rooms/settings/chat', {
      l10n.swipeActions: '/rooms/settings/chat/swipe_actions',
      l10n.mergedContacts: '/rooms/settings/chat/merged_contacts',
      l10n.matrixFeatures: '/rooms/settings/chat/matrix_features',
      l10n.customEmojisAndStickers: '/rooms/settings/chat/emotes',
    });
    // The reaction picker and the sheet that puts networks back on the
    // rail.
    await expectOpens(tester, [l10n.doubleTapReaction, l10n.hiddenFromRail]);
    // Turning double tap off takes its reaction row away.
    await tester.tap(find.text(l10n.doubleTapToReact));
    await tester.pumpAndSettle();
    expect(AppSettings.doubleTapToReact.value, isFalse);
    expect(find.text(l10n.doubleTapReaction), findsNothing);
    await finishFakeSettings(tester, client);
  });

  testWidgets('swipe actions', (tester) async {
    await open(tester, '/rooms/settings/chat/swipe_actions');
    expect(find.byType(SettingsSwipeActions), findsOneWidget);
    expectTexts([
      l10n.swipeActions,
      l10n.swipeOnChatsDescription,
      l10n.swipeActionsHeading,
      l10n.swipeRight,
      l10n.swipeLeft,
      l10n.swipeActionsFootnote,
    ]);
    expectSwitches(1);
    await expectOpens(tester, [l10n.swipeRight, l10n.swipeLeft]);
    await expectToggles(tester, {l10n.swipeOnChats: AppSettings.chatListSwipe});
    await finishFakeSettings(tester, client);
  });

  testWidgets('merged contacts', (tester) async {
    await open(tester, '/rooms/settings/chat/merged_contacts');
    expect(find.byType(SettingsMergedContacts), findsOneWidget);
    expectTexts([
      l10n.mergedContacts,
      l10n.mergedContactsDescription,
      l10n.suggestMergesDescription,
      l10n.phoneNumberRegion,
      l10n.phoneRegionNorthAmerica,
      l10n.mergeSuggestions,
      l10n.noMergeSuggestions,
      l10n.noMergedContacts,
    ]);
    expectSwitches(1);
    await expectToggles(tester, {
      l10n.suggestMerges: AppSettings.mergedContactSuggestions,
    });
    await expectOpens(tester, [l10n.phoneNumberRegion]);
    await finishFakeSettings(tester, client);
  });

  testWidgets('matrix features', (tester) async {
    await open(tester, '/rooms/settings/chat/matrix_features');
    expect(find.byType(SettingsMatrixFeatures), findsOneWidget);
    final features = MatrixFeatures.forClient(client);
    expectTexts([
      l10n.matrixFeatures,
      l10n.matrixFeaturesDescription,
      l10n.matrixFeaturesAuto,
      l10n.matrixFeaturesAlwaysShow,
      l10n.matrixFeaturesAlwaysHide,
      l10n.matrixFeaturesFooter,
      for (final feature in MatrixFeature.values) ...[
        SettingsMatrixFeatures.featureTitle(l10n, feature),
        SettingsMatrixFeatures.stateLine(l10n, features, feature),
      ],
    ]);
    expect(find.byType(SegmentedButton<MatrixFeaturesMode>), findsOneWidget);
    for (final feature in MatrixFeature.values) {
      expect(
        find.byKey(ValueKey('matrix_feature_${feature.name}')),
        findsOneWidget,
      );
    }
    await expectOpens(tester, [
      for (final feature in MatrixFeature.values)
        SettingsMatrixFeatures.featureTitle(l10n, feature),
    ]);
    await tester.tap(find.text(l10n.matrixFeaturesAlwaysShow));
    await tester.pumpAndSettle();
    expect(features.mode, MatrixFeaturesMode.alwaysShow);
    await finishFakeSettings(tester, client);
  });

  testWidgets('style', (tester) async {
    final room = addFakeChat(client, '!im:x', 'Anne', partner: '@im_anne:x');
    addFakeBridge(room, bot: '@imessagebot:x', network: 'iMessage');
    await open(tester, '/rooms/settings/style');
    expect(find.byType(SettingsStyle), findsOneWidget);
    expectTexts([
      l10n.changeTheme,
      l10n.lightTheme,
      l10n.darkTheme,
      l10n.systemTheme,
      l10n.setColorTheme,
      l10n.networkBubbleColorsTitle,
      l10n.chatListNetworkBadgesDescription,
      l10n.networkBubbleColorsDescription,
      l10n.messagesStyle,
      l10n.setWallpaper,
      l10n.fontSize,
      '× ${AppSettings.fontSizeFactor.value}',
    ]);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    // The app colour swatches: Seam Cobalt and the Material primaries, each
    // named by its hex value.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && (widget.message ?? '').startsWith('#'),
      ),
      findsNWidgets(Colors.primaries.length + 1),
    );
    // The font size slider.
    expect(find.byType(Slider), findsOneWidget);
    expectTappable(l10n.setWallpaper);
    expectSwitches(2);
    await expectToggles(tester, {
      l10n.chatListNetworkBadges: AppSettings.chatListNetworkBadges,
    });
    // One colour per network shows a row of swatches for each network.
    final perNetwork = AppSettings.networkBubbleColors.value;
    if (!perNetwork) {
      await tester.tap(find.text(l10n.networkBubbleColors));
      await tester.pumpAndSettle();
    }
    expect(AppSettings.networkBubbleColors.value, isTrue);
    expect(find.byTooltip(l10n.networkDefaultColor), findsOneWidget);
    // Switching the theme mode stores it.
    await tester.tap(find.text(l10n.darkTheme));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<ThemeMode>>(
            find.byType(SegmentedButton<ThemeMode>),
          )
          .selected,
      {ThemeMode.dark},
    );
    await finishFakeSettings(tester, client);
  });

  testWidgets('notifications', (tester) async {
    await open(tester, '/rooms/settings/notifications');
    expect(find.byType(SettingsNotifications), findsOneWidget);
    final rules = [for (final ids in fakePushRules.values) ...ids];
    expectTexts([
      l10n.notifications,
      l10n.buildDoesNotSupportFirebase,
      l10n.devices,
      'network.seam.app',
      'https://push.x/_matrix/push/v1/notify',
    ]);
    // Each push rule has its switch and its "more" link to the details.
    expectSwitches(rules.length);
    expect(find.text(l10n.more, findRichText: true), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.child is Text,
      ),
      findsNWidgets(rules.length),
    );
    // With the master rule off, the other rules can be switched.
    final enabled = tester
        .widgetList<Switch>(find.byType(Switch))
        .where((s) => s.onChanged != null);
    expect(enabled.length, rules.length);
    // A pusher opens its details.
    await expectOpens(tester, ['network.seam.app']);
    await finishFakeSettings(tester, client);
  });

  testWidgets('security', (tester) async {
    await open(tester, '/rooms/settings/security');
    expect(find.byType(SettingsSecurity), findsOneWidget);
    expectTexts([
      l10n.security,
      l10n.privacy,
      l10n.sendTypingNotificationsDescription,
      l10n.sendReadReceiptsDescription,
      l10n.shareCrashReportsDescription,
      l10n.blockedUsers,
      l10n.thereAreCountUsersBlocked(1),
      l10n.shareKeysWith,
      l10n.shareKeysWithDescription,
      l10n.deviceIdentityKey,
      l10n.changePassword,
      l10n.dehydrate,
      l10n.deleteAccount,
    ]);
    expect(find.byType(DropdownButton<ShareKeysWith>), findsOneWidget);
    expectSwitches(3);
    await expectToggles(tester, {
      l10n.sendTypingNotifications: AppSettings.sendTypingNotifications,
      l10n.sendReadReceipts: AppSettings.sendPublicReadReceipts,
      l10n.shareCrashReports: AppSettings.autoSendErrorReports,
    });
    await expectLinks(tester, '/rooms/settings/security', {
      l10n.blockedUsers: '/rooms/settings/security/ignorelist',
      l10n.changePassword: '/rooms/settings/security/password',
    });
    await expectOpens(tester, [l10n.dehydrate, l10n.deleteAccount]);
    await finishFakeSettings(tester, client);
  });

  testWidgets('change password', (tester) async {
    await open(tester, '/rooms/settings/security/password');
    expect(find.byType(SettingsPassword), findsOneWidget);
    expectTexts([
      l10n.changePassword,
      l10n.pleaseEnterYourCurrentPassword,
      l10n.newPassword,
      l10n.repeatPassword,
      l10n.passwordRecoverySettings,
    ]);
    expect(find.byType(TextField), findsNWidgets(3));
    // The title and the button.
    expect(find.text(l10n.changePassword), findsNWidgets(2));
    await expectLinks(tester, '/rooms/settings/security/password', {
      l10n.passwordRecoverySettings: '/rooms/settings/security/3pid',
    });
    await finishFakeSettings(tester, client);
  });

  testWidgets('password recovery', (tester) async {
    await open(tester, '/rooms/settings/security/3pid');
    expect(find.byType(Settings3Pid), findsOneWidget);
    expectTexts([
      l10n.passwordRecovery,
      l10n.withTheseAddressesRecoveryDescription,
      'gray@example.org',
    ]);
    expect(find.byTooltip(l10n.addEmail), findsOneWidget);
    expect(find.byTooltip(l10n.delete), findsOneWidget);
    await finishFakeSettings(tester, client);
  });

  testWidgets('blocked users', (tester) async {
    await open(tester, '/rooms/settings/security/ignorelist');
    expect(find.byType(SettingsIgnoreList), findsOneWidget);
    expectTexts([
      l10n.blockedUsers,
      l10n.blockUsername,
      l10n.blockListDescription,
      fakeIgnoredUser,
    ]);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip(l10n.block), findsOneWidget);
    expect(find.byTooltip(l10n.delete), findsOneWidget);
    await finishFakeSettings(tester, client);
  });

  testWidgets('devices', (tester) async {
    await open(tester, '/rooms/settings/devices');
    expect(find.byType(DevicesSettings), findsOneWidget);
    expectTexts([
      l10n.devices,
      l10n.thisDevice,
      'Seam Android',
      'Seam Windows',
      l10n.removeAllOtherDevices,
    ]);
    expectTappable(l10n.removeAllOtherDevices);
    // A device opens its actions: rename, verify, block, remove.
    await expectOpens(tester, ['Seam Android', 'Seam Windows']);
    await finishFakeSettings(tester, client);
  });

  testWidgets('homeserver', (tester) async {
    await open(tester, '/rooms/settings/homeserver');
    expect(find.byType(SettingsHomeserver), findsOneWidget);
    expectTexts([
      l10n.aboutHomeserver('x'),
      l10n.serverInformation,
      l10n.supportPage,
      'https://x/support',
      l10n.contactServerAdmin,
      'admin@x',
      l10n.clientWellKnownInformation,
      l10n.baseUrl,
      l10n.identityServer,
    ]);
    await finishFakeSettings(tester, client);
  });
}
