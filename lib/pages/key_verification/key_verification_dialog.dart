// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/key_verification/key_verification_scanner.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/device_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// Device verification as full pages: confirming one of your own devices,
/// or verifying another person. One page per step of the [request]: accept
/// it, wait, scan or show a QR code or compare emoji (numbers when the
/// other side cannot show emoji), then verified or why it stopped.
///
/// [show] pushes it over the current page and completes with true once
/// the other side is verified.
class KeyVerificationDialog extends StatefulWidget {
  Future<bool?> show(BuildContext context) => Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (context) => this),
  );

  final KeyVerification request;

  const KeyVerificationDialog({super.key, required this.request});

  @override
  KeyVerificationPageState createState() => KeyVerificationPageState();
}

class KeyVerificationPageState extends State<KeyVerificationDialog> {
  void Function()? originalOnUpdate;
  List<dynamic>? sasEmoji;
  Profile? profile;
  final TextEditingController keyController = TextEditingController();
  Object? keyError;
  String? scanError;

  KeyVerification get request => widget.request;

  /// Whether this confirms one of the account's own devices rather than
  /// verifying another person.
  bool get ownDevice => request.userId == request.client.userID;

  @override
  void initState() {
    super.initState();
    originalOnUpdate = request.onUpdate;
    request.onUpdate = () {
      originalOnUpdate?.call();
      if (mounted) setState(() {});
    };
    if (!ownDevice) {
      request.client.getProfileFromUserId(request.userId).then((p) {
        if (mounted) setState(() => profile = p);
      });
    }
    rootBundle.loadString('assets/sas-emoji.json').then((e) {
      if (mounted) setState(() => sasEmoji = json.decode(e));
    });
  }

  @override
  void dispose() {
    request.onUpdate = originalOnUpdate;
    if (![
      KeyVerificationState.error,
      KeyVerificationState.done,
    ].contains(request.state)) {
      request.cancel('m.user');
    }
    keyController.dispose();
    super.dispose();
  }

  void _close([bool? verified]) => Navigator.of(context).pop(verified);

  /// The other side: a device name for your own devices, a name for people.
  String get otherName {
    if (ownDevice) {
      final deviceId = request.deviceId;
      final device = deviceId == null
          ? null
          : request.client.userDeviceKeys[request.userId]?.deviceKeys[deviceId];
      return device?.displayname ?? deviceId ?? request.userId;
    }
    return profile?.displayName ?? request.userId.localpart ?? request.userId;
  }

  Future<void> _unlock() async {
    setState(() => keyError = null);
    try {
      await request.openSSSS(keyOrPassphrase: keyController.text.trim());
    } catch (e) {
      if (mounted) setState(() => keyError = e);
    }
  }

  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute(builder: (_) => const KeyVerificationScanner()),
    );
    if (payload == null || !mounted) return;
    setState(() => scanError = null);
    await request.continueVerification(
      EventTypes.Reciprocate,
      qrDataRawBytes: payload,
    );
    if (mounted && request.state == KeyVerificationState.askChoice) {
      setState(() => scanError = L10n.of(context).notAVerificationCode);
    }
  }

  Widget _avatar() => ownDevice
      ? const OnboardingHeroIcon(Icons.devices_outlined)
      : Avatar(mxContent: profile?.avatarUrl, name: otherName, size: 72);

  Widget _waiting(String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final close = CloseButton(onPressed: _close);
    final name = otherName;

    switch (request.state) {
      case KeyVerificationState.askAccept:
        return OnboardingStep(
          leading: close,
          hero: ownDevice
              ? const OnboardingHeroIcon(Icons.phonelink_lock_outlined)
              : _avatar(),
          headline: ownDevice
              ? l10n.isThisYouSigningIn
              : l10n.wantsToVerifyYou(name),
          body: ownDevice
              ? '$name\n\n${l10n.onlyContinueIfYouSignedIn}'
              : l10n.verifyRequestBody,
          primary: FilledButton(
            onPressed: request.acceptVerification,
            child: Text(ownDevice ? l10n.yesItsMe : l10n.accept),
          ),
          secondary: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                await request.rejectVerification();
                _close(false);
              },
              child: Text(ownDevice ? l10n.noThatWasntMe : l10n.reject),
            ),
          ],
        );

      case KeyVerificationState.waitingAccept:
        return OnboardingStep(
          leading: close,
          hero: _avatar(),
          headline: ownDevice
              ? l10n.openSeamOnOtherDevice
              : l10n.verifyPersonTitle(name),
          body: ownDevice ? null : l10n.waitingForPersonBody(name),
          content: [_waiting(l10n.waitingForReply)],
          secondary: [TextButton(onPressed: _close, child: Text(l10n.cancel))],
        );

      case KeyVerificationState.askChoice:
        final qrCode = request.qrCode;
        final canShow =
            qrCode != null &&
            request.possibleMethods.contains(EventTypes.QRShow);
        final canScan =
            request.possibleMethods.contains(EventTypes.QRScan) &&
            PlatformInfos.isMobile;
        final canCompare = request.possibleMethods.contains(EventTypes.Sas);
        final scanError = this.scanError;
        return OnboardingStep(
          leading: close,
          headline: l10n.chooseHowToVerifyTitle,
          content: [
            if (scanError != null) ...[
              OnboardingNotice(
                icon: Icons.error_outline,
                tone: OnboardingTone.error,
                text: scanError,
              ),
              const SizedBox(height: 16),
            ],
            if (canShow) _QrCard(bytes: qrCode.qrDataRawBytes),
          ],
          primary: canScan
              ? FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.scanTheirCode),
                )
              : null,
          secondary: [
            if (canCompare)
              OutlinedButton(
                onPressed: () => request.continueVerification(EventTypes.Sas),
                child: Text(l10n.compareEmojiInstead),
              ),
          ],
        );

      case KeyVerificationState.showQRSuccess:
        return OnboardingStep(
          leading: close,
          centered: true,
          hero: const Padding(
            padding: EdgeInsets.only(top: 48),
            child: OnboardingHeroIcon(
              Icons.qr_code_2,
              tone: OnboardingTone.success,
              size: 96,
            ),
          ),
          headline: l10n.codeScannedTitle,
          body: l10n.codeScannedBody(name),
          content: [_waiting(l10n.waitingForOtherSide(name))],
        );

      case KeyVerificationState.confirmQRScan:
        return OnboardingStep(
          leading: close,
          hero: const OnboardingHeroIcon(Icons.qr_code_2),
          headline: l10n.didTheyScanTitle,
          body: l10n.didTheyScanBody(name),
          primary: FilledButton(
            onPressed: request.acceptQRScanConfirmation,
            child: Text(l10n.yesItWasScanned),
          ),
          secondary: [
            OutlinedButton(
              onPressed: () => request.cancel('m.user'),
              child: Text(l10n.cancel),
            ),
          ],
        );

      case KeyVerificationState.askSSSS:
        final keyError = this.keyError;
        return OnboardingStep(
          leading: close,
          headline: l10n.unlockToVerifyTitle,
          body: l10n.unlockToVerifyBody,
          content: [
            TextField(
              controller: keyController,
              obscureText: true,
              autocorrect: false,
              onSubmitted: (_) => _unlock(),
              decoration: InputDecoration(
                labelText: l10n.recoveryKeyOrPassphrase,
                errorText: keyError == null
                    ? null
                    : l10n.incorrectPassphraseOrKey,
              ),
            ),
          ],
          primary: FilledButton(onPressed: _unlock, child: Text(l10n.unlock)),
          secondary: [
            TextButton(
              onPressed: () => request.openSSSS(skip: true),
              child: Text(l10n.skip),
            ),
          ],
        );

      case KeyVerificationState.askSas:
      case KeyVerificationState.waitingSas:
        final waiting = request.state == KeyVerificationState.waitingSas;
        final emoji = request.sasTypes.contains('emoji');
        return OnboardingStep(
          leading: close,
          headline: l10n.doTheseMatch,
          body: !emoji
              ? l10n.compareNumbersBody
              : ownDevice
              ? l10n.compareEmojiOwnBody(name)
              : l10n.compareEmojiPersonBody(name),
          content: [
            if (emoji)
              SasEmojiGrid(emojis: request.sasEmojis, translations: sasEmoji)
            else
              SasNumbers(numbers: request.sasNumbers),
            if (waiting) ...[
              const SizedBox(height: 24),
              _waiting(l10n.waitingForOtherSide(name)),
            ],
          ],
          primary: waiting
              ? null
              : FilledButton(
                  onPressed: request.acceptSas,
                  child: Text(l10n.theyMatch),
                ),
          secondary: waiting
              ? [TextButton(onPressed: _close, child: Text(l10n.cancel))]
              : [
                  OutlinedButton(
                    onPressed: request.rejectSas,
                    child: Text(l10n.theyDontMatch),
                  ),
                ],
        );

      case KeyVerificationState.done:
        return OnboardingStep(
          centered: true,
          hero: const Padding(
            padding: EdgeInsets.only(top: 64),
            child: OnboardingHeroIcon(
              Icons.verified_user_rounded,
              tone: OnboardingTone.success,
              size: 96,
            ),
          ),
          headline: ownDevice
              ? l10n.thisDeviceIsConfirmed
              : l10n.personIsVerified(name),
          body: ownDevice
              ? l10n.otherDeviceConfirmedBody
              : l10n.personVerifiedBody(name),
          primary: FilledButton(
            onPressed: () => _close(true),
            child: Text(l10n.done),
          ),
        );

      case KeyVerificationState.error:
        final code = request.canceledCode ?? '';
        final (headline, body) = switch (code) {
          'm.mismatched_sas' || 'm.key_mismatch' || 'm.mismatched_commitment' =>
            (l10n.verificationStoppedTitle, l10n.verificationMismatchBody),
          'm.timeout' => (
            l10n.verificationTimeoutTitle,
            l10n.verificationTimeoutBody,
          ),
          'm.user' => (
            l10n.verificationStoppedTitle,
            l10n.verificationCancelledBody,
          ),
          _ => (
            l10n.verificationStoppedTitle,
            l10n.verificationErrorBody(code),
          ),
        };
        return OnboardingStep(
          leading: close,
          hero: const OnboardingHeroIcon(
            Icons.gpp_bad_outlined,
            tone: OnboardingTone.error,
          ),
          headline: headline,
          body: body,
          primary: FilledButton(
            onPressed: () => _close(false),
            child: Text(l10n.close),
          ),
        );
    }
  }
}

/// This device's verification QR code, for the other device to scan.
class _QrCard extends StatelessWidget {
  final List<int> bytes;
  const _QrCard({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 200,
              child: PrettyQrView(
                qrImage: QrImage(
                  QrCode.fromUint8List(
                    data: Uint8List.fromList(bytes),
                    errorCorrectLevel: QrErrorCorrectLevel.L,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            L10n.of(context).scanThisCodeBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// The seven emoji to compare, four over three, each with its name.
class SasEmojiGrid extends StatelessWidget {
  final List<KeyVerificationEmoji> emojis;

  /// assets/sas-emoji.json, for the names in the app's language.
  final List<dynamic>? translations;

  const SasEmojiGrid({required this.emojis, this.translations, super.key});

  String _name(BuildContext context, KeyVerificationEmoji emoji) {
    final translations = this.translations;
    if (translations == null) return emoji.name;
    final descriptions = Map<String, dynamic>.from(
      translations[emoji.number]['translated_descriptions'],
    );
    final locale = Localizations.localeOf(context);
    return descriptions['${locale.languageCode}_${locale.countryCode}']
            as String? ??
        descriptions[locale.languageCode] as String? ??
        emoji.name;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget tile(KeyVerificationEmoji emoji) => Container(
      width: 70,
      height: 92,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji.emoji, style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 6),
          Text(
            _name(context, emoji),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Column(
      spacing: 8,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [for (final emoji in emojis.take(4)) tile(emoji)],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [for (final emoji in emojis.skip(4)) tile(emoji)],
        ),
      ],
    );
  }
}

/// The three numbers to compare when emoji are not available.
class SasNumbers extends StatelessWidget {
  final List<int> numbers;
  const SasNumbers({required this.numbers, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final number in numbers)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
