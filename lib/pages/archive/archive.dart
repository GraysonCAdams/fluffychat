// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/archive/archive_cache.dart';
import 'package:fluffychat/pages/archive/archive_view.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class Archive extends StatefulWidget {
  const Archive({super.key});

  @override
  ArchiveController createState() => ArchiveController();
}

class ArchiveController extends State<Archive> {
  List<ArchivedRoom> archive = [];

  /// Whether [archive] holds anything yet, from the database or the server.
  bool loaded = false;

  /// Whether the server is still being asked for the current archive.
  bool refreshing = true;

  /// The error of the server request, shown only when nothing is stored.
  Object? error;

  late final Client _client = Matrix.of(context).client;

  /// Rooms forgotten on this page, kept out of a server answer that was
  /// already on its way.
  final Set<String> _forgotten = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = await ArchiveCache.read(_client);
    if (stored != null && mounted && !loaded) {
      setState(() {
        archive = stored;
        loaded = true;
      });
    }
    try {
      final fresh = await ArchiveCache.refresh(_client);
      if (!mounted) return;
      setState(() {
        archive = fresh
            .where((archived) => !_forgotten.contains(archived.room.id))
            .toList();
        loaded = true;
      });
      if (_forgotten.isNotEmpty) await ArchiveCache.store(_client, archive);
    } catch (e, s) {
      Logs().w('Could not load the archive', e, s);
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> forgetRoomAction(int i) async {
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        Logs().v('Forget room ${archive[i].room.getLocalizedDisplayname()}');
        await archive[i].room.forget();
        _forgotten.add(archive[i].room.id);
        archive.removeAt(i);
        await ArchiveCache.store(_client, archive);
      },
    );
    setState(() {});
  }

  Future<void> forgetAllAction() async {
    final archive = this.archive;
    if (archive.isEmpty) return;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSure,
          okLabel: L10n.of(context).yes,
          cancelLabel: L10n.of(context).cancel,
          message: L10n.of(context).clearArchive,
        ) !=
        OkCancelResult.ok) {
      return;
    }
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = archive.length;
        while (archive.isNotEmpty) {
          onProgress(1 - (archive.length / count));
          Logs().v(
            'Forget room ${archive.last.room.getLocalizedDisplayname()}',
          );
          await archive.last.room.forget();
          _forgotten.add(archive.last.room.id);
          archive.removeLast();
        }
        await ArchiveCache.store(_client, archive);
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ArchiveView(this);
}
