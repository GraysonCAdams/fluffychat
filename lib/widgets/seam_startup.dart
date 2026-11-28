// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The screen the app opens on while it loads: the stitch loader, white on
/// Seam Cobalt, where the Android 12+ system splash screen has the logo.
///
/// The system splash screen draws the launcher foreground at 288 dp, and
/// that artboard holds the icon's at two thirds, so the icon artboard is
/// [loaderSize] dp, centred in the window. The loader begins on the logo
/// pose, so taking over from the splash screen shows no change; then it
/// sews. When the app is ready the loader finishes its pass, settles on the
/// logo and the whole screen fades into the app, unless a page has asked
/// to take over from it ([handOff]).
class SeamStartup extends StatefulWidget {
  final Future<Widget> app;

  const SeamStartup({required this.app, super.key});

  static const Color cobalt = Color(0xFF1A5AD7);
  static const double loaderSize = 192;

  /// How long the app may take to load before the loader is put up. A start
  /// that is ready sooner goes straight from the system splash screen (or,
  /// on desktop, the empty window) to the app.
  static const Duration grace = Duration(milliseconds: 300);

  /// Runs [app] once it has loaded, with the loader in front of it if that
  /// takes longer than [grace].
  static Future<void> run(Future<Widget> app) async {
    final ready = await app
        .then<Widget?>((widget) => widget)
        .timeout(grace, onTimeout: () => null);
    runApp(ready ?? SeamStartup(app: app));
  }

  static bool _showing = false;
  static VoidCallback? _takeOver;

  /// For a page whose first frame matches the start screen's last one (the
  /// welcome page, which begins as a full screen of cobalt with the mark at
  /// the same size and place): calls [takeOver] once the start screen is
  /// out of the way, at once if it was never shown or has gone. While a
  /// page waits here, the start screen ends by vanishing instead of
  /// fading, so the page can carry the motion on.
  static void handOff(VoidCallback takeOver) {
    if (!_showing) {
      takeOver();
      return;
    }
    _takeOver = takeOver;
  }

  static void _release() {
    _showing = false;
    final takeOver = _takeOver;
    _takeOver = null;
    takeOver?.call();
  }

  @override
  State<SeamStartup> createState() => _SeamStartupState();
}

class _SeamStartupState extends State<SeamStartup> {
  Widget? _app;
  bool _landed = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    SeamStartup._showing = true;
    widget.app.then(
      (app) {
        if (mounted) setState(() => _app = app);
      },
      onError: (Object e, StackTrace s) =>
          Zone.current.handleUncaughtError(e, s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (app != null) KeyedSubtree(key: const ValueKey('app'), child: app),
          if (!_gone)
            AnimatedOpacity(
              key: const ValueKey('loader'),
              opacity: _landed ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              curve: Curves.ease,
              onEnd: () {
                setState(() => _gone = true);
                SeamStartup._release();
              },
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark,
                  systemNavigationBarIconBrightness: Brightness.light,
                ),
                child: MediaQuery.fromView(
                  view: View.of(context),
                  child: ColoredBox(
                    color: SeamStartup.cobalt,
                    child: Center(
                      child: SeamStitchLoader(
                        size: SeamStartup.loaderSize,
                        pale: SeamStitchPainter.periwinkle,
                        loading: app == null,
                        onLanded: () {
                          if (SeamStartup._takeOver != null) {
                            setState(() => _gone = true);
                            SeamStartup._release();
                            return;
                          }
                          setState(() => _landed = true);
                        },
                      ),
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
