// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/key_verification/scanned_qr.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

/// The camera, scanning another device's verification QR code (Android and
/// iOS). Pops with the code's payload, or null when closed.
class KeyVerificationScanner extends StatefulWidget {
  const KeyVerificationScanner({super.key});

  @override
  State<KeyVerificationScanner> createState() => _KeyVerificationScannerState();
}

class _KeyVerificationScannerState extends State<KeyVerificationScanner> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'verification QR');
  StreamSubscription<Barcode>? _scans;
  bool _wrongCode = false;

  @override
  void dispose() {
    _scans?.cancel();
    super.dispose();
  }

  void _onCreated(QRViewController controller) {
    // The scanner can start paused on Android (as in QrScannerModal).
    if (PlatformInfos.isAndroid) controller.pauseCamera();
    controller.resumeCamera();
    _scans = controller.scannedDataStream.listen((scan) {
      final payload = matrixQrPayload(text: scan.code, rawBytes: scan.rawBytes);
      if (payload == null) {
        if (!_wrongCode && mounted) setState(() => _wrongCode = true);
        return;
      }
      _scans?.cancel();
      if (mounted) Navigator.of(context).pop<Uint8List>(payload);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: CloseButton(onPressed: Navigator.of(context).pop),
        title: Text(l10n.scanCodeTitle),
      ),
      body: Stack(
        children: [
          QRView(
            key: _qrKey,
            onQRViewCreated: _onCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Colors.white,
              borderRadius: 28,
              borderLength: 40,
              borderWidth: 4,
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _wrongCode ? l10n.notAVerificationCode : l10n.pointCameraAtCode,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
