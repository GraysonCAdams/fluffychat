// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/key_verification/key_verification_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed_data/typed_buffers.dart';

import '../utils/message_search/search_test_client.dart';

/// A verification request held in one state, recording what was asked of
/// it.
class _Request extends Fake implements KeyVerification {
  @override
  final Client client;
  @override
  final String userId;
  @override
  KeyVerificationState state;
  @override
  String? deviceId;
  @override
  List<String> sasTypes = const ['emoji', 'decimal'];
  @override
  List<String> possibleMethods = const [];
  @override
  QRCode? qrCode;
  @override
  String? canceledCode;
  @override
  void Function()? onUpdate;

  final List<String> calls = [];

  _Request(this.client, this.userId, this.state, {this.deviceId});

  @override
  List<KeyVerificationEmoji> get sasEmojis => [
    for (final n in [0, 9, 18, 27, 36, 45, 54]) KeyVerificationEmoji(n),
  ];
  @override
  List<int> get sasNumbers => [4821, 1937, 6650];

  @override
  Future<void> acceptSas() async => calls.add('acceptSas');
  @override
  Future<void> rejectSas() async => calls.add('rejectSas');
  @override
  Future<void> cancel([String code = 'm.unknown', bool quiet = false]) async =>
      calls.add('cancel $code');
  @override
  Future<void> continueVerification(
    String type, {
    List<String>? methods,
    Uint8List? qrDataRawBytes,
  }) async => calls.add('continue $type');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late L10n l10n;
  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    l10n = await L10n.delegate.load(const Locale('en'));
  });
  setUp(() async => client = await createSearchTestClient());
  tearDown(() => client.dispose(closeDatabase: true));

  Future<void> pump(WidgetTester tester, _Request request) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: KeyVerificationDialog(request: request),
      ),
    );
    for (var i = 0; i < 40 && find.byType(Scaffold).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    // Lets the profile lookup for another person time out against the
    // fake server.
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('own device: seven emoji, four over three, then they match', (
    tester,
  ) async {
    final request = _Request(
      client,
      client.userID!,
      KeyVerificationState.askSas,
      deviceId: 'PIXEL10',
    );
    await pump(tester, request);
    expect(find.text(l10n.doTheseMatch), findsOneWidget);
    final tiles = request.sasEmojis.map((e) => find.text(e.emoji)).toList();
    for (final tile in tiles) {
      expect(tile, findsOneWidget);
    }
    final firstRow = tester.getCenter(tiles[0]).dy;
    expect(tester.getCenter(tiles[3]).dy, firstRow);
    expect(tester.getCenter(tiles[4]).dy, greaterThan(firstRow));
    await tester.tap(find.text(l10n.theyMatch));
    expect(request.calls, ['acceptSas']);
  });

  testWidgets('numbers when the other side has no emoji', (tester) async {
    final request = _Request(
      client,
      '@alex:matrix.org',
      KeyVerificationState.askSas,
    )..sasTypes = const ['decimal'];
    await pump(tester, request);
    expect(find.text('4821'), findsOneWidget);
    expect(find.text(l10n.compareNumbersBody), findsOneWidget);
  });

  testWidgets('a QR code to scan, or emoji instead', (tester) async {
    final request =
        _Request(client, client.userID!, KeyVerificationState.askChoice)
          ..possibleMethods = const [EventTypes.QRShow, EventTypes.Sas]
          ..qrCode = QRCode(
            'secret',
            Uint8Buffer()..addAll('MATRIX'.codeUnits + List.filled(80, 7)),
          );
    await pump(tester, request);
    expect(find.byType(PrettyQrView), findsOneWidget);
    expect(
      find.text(l10n.scanTheirCode),
      findsNothing,
      reason: 'no camera to scan with on this host',
    );
    await tester.tap(find.text(l10n.compareEmojiInstead));
    expect(request.calls, ['continue ${EventTypes.Sas}']);
  });

  testWidgets('a mismatch says nothing was shared', (tester) async {
    final request = _Request(
      client,
      '@alex:matrix.org',
      KeyVerificationState.error,
    )..canceledCode = 'm.mismatched_sas';
    await pump(tester, request);
    expect(find.text(l10n.verificationStoppedTitle), findsOneWidget);
    expect(find.text(l10n.verificationMismatchBody), findsOneWidget);
  });

  testWidgets('a request from another own device asks if it is you', (
    tester,
  ) async {
    final request = _Request(
      client,
      client.userID!,
      KeyVerificationState.askAccept,
      deviceId: 'WIN',
    );
    await pump(tester, request);
    expect(find.text(l10n.isThisYouSigningIn), findsOneWidget);
    expect(find.text(l10n.yesItsMe), findsOneWidget);
  });
}
