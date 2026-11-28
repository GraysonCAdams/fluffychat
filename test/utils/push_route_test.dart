// SPDX-FileCopyrightText: 2026 Grayson Adams
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/background_push.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which way an Android phone gets its pushes, and when the user hears that
/// it gets none: UnifiedPush first, FCM through Seam's gateway in the Play
/// build, and a notice only in a build without FCM.
void main() {
  const gateway = 'https://seam-push.312.dev/_matrix/push/v1/notify';

  group('push route', () {
    test('an installed distributor wins, even in the FCM build', () {
      for (final firebaseLinked in [true, false]) {
        expect(
          BackgroundPush.androidPushRoute(
            hasDistributor: true,
            firebaseLinked: firebaseLinked,
            gatewayUrl: gateway,
          ),
          AndroidPushRoute.unifiedPush,
        );
      }
    });

    test('with no distributor the FCM build uses FCM', () {
      expect(
        BackgroundPush.androidPushRoute(
          hasDistributor: false,
          firebaseLinked: true,
          gatewayUrl: gateway,
        ),
        AndroidPushRoute.firebase,
      );
    });

    test('with no distributor the build without FCM has no push', () {
      expect(
        BackgroundPush.androidPushRoute(
          hasDistributor: false,
          firebaseLinked: false,
          gatewayUrl: gateway,
        ),
        AndroidPushRoute.none,
      );
    });

    test('FCM needs a gateway to send through', () {
      expect(
        BackgroundPush.androidPushRoute(
          hasDistributor: false,
          firebaseLinked: true,
          gatewayUrl: '',
        ),
        AndroidPushRoute.none,
      );
    });
  });

  group('no push notice', () {
    test('the FCM build never shows it', () {
      for (final dismissed in [true, false]) {
        expect(
          BackgroundPush.warnsNoPush(
            firebaseLinked: true,
            dismissed: dismissed,
          ),
          isFalse,
        );
      }
    });

    test('the build without FCM shows it until dismissed', () {
      expect(
        BackgroundPush.warnsNoPush(firebaseLinked: false, dismissed: false),
        isTrue,
      );
      expect(
        BackgroundPush.warnsNoPush(firebaseLinked: false, dismissed: true),
        isFalse,
      );
    });
  });
}
