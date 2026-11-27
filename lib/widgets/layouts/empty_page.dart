// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The pane beside the chat list when no chat is open: the Seam glyph, faint
/// on the surface. While the client has not finished its first sync (when
/// the chat list shows its loading rows) the glyph sews, as a
/// [SeamStitchLoader] in the glyph's colour; when the sync is done it finishes its pass and
/// crossfades to the still glyph.
class EmptyPage extends StatefulWidget {
  static const double _width = 400;
  const EmptyPage({super.key});

  @override
  State<EmptyPage> createState() => _EmptyPageState();
}

class _EmptyPageState extends State<EmptyPage> {
  Client? _client;
  StreamSubscription? _syncSub;
  bool _loading = false;

  /// Set once the loader has been shown, so it stays to finish its pass.
  bool _sewing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = Matrix.of(context).client;
    if (client == _client) return;
    _client = client;
    _syncSub?.cancel();
    _syncSub = client.onSyncStatus.stream.listen((_) => _update());
    _update(rebuild: false);
  }

  void _update({bool rebuild = true}) {
    final loading = _client?.prevBatch == null;
    if (loading == _loading) return;
    _loading = loading;
    if (loading) _sewing = true;
    if (rebuild && mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = min(MediaQuery.sizeOf(context).width, EmptyPage._width) / 2;
    final theme = Theme.of(context);
    final glyph = Image.asset(
      'assets/seam/seam_glyph.png',
      color: theme.colorScheme.surfaceContainerHigh,
      width: width,
      height: width,
      filterQuality: FilterQuality.medium,
    );
    return Scaffold(
      // Add invisible appbar to make status bar on Android tablets bright.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        alignment: Alignment.center,
        child: _sewing
            ? SeamStitchLoader(
                size: width,
                color: theme.colorScheme.surfaceContainerHigh,
                loading: _loading,
                settled: glyph,
              )
            : glyph,
      ),
    );
  }
}
