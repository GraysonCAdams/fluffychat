// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_ignore_list_view.dart';

class SettingsIgnoreList extends StatefulWidget {
  final String? initialUserId;

  const SettingsIgnoreList({super.key, this.initialUserId});

  @override
  SettingsIgnoreListController createState() => SettingsIgnoreListController();
}

class SettingsIgnoreListController extends State<SettingsIgnoreList> {
  final TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialUserId = widget.initialUserId;
    if (initialUserId != null) {
      controller.text = initialUserId;
    }
  }

  String? errorText;

  void ignoreUser(BuildContext context) {
    final userId = controller.text.trim();
    if (userId.isEmpty) return;
    if (!userId.isValidMatrixIdStrict() || userId.sigil != '@') {
      setState(() {
        errorText = L10n.of(context).invalidInput;
      });
      return;
    }
    setState(() {
      errorText = null;
    });

    final client = Matrix.of(context).client;
    showFutureLoadingDialog(
      context: context,
      future: () => client.ignoreUser(userId),
    );
    setState(() {});
    controller.clear();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Syncs that change the ignore list. Created once: a StreamBuilder handed
  /// a stream made in build subscribes again on every rebuild of the page.
  late final Stream<SyncUpdate> ignoreListUpdates = Matrix.of(context)
      .client
      .onSync
      .stream
      .where(
        (syncUpdate) =>
            syncUpdate.accountData?.any(
              (accountData) => accountData.type == 'm.ignored_user_list',
            ) ??
            false,
      );

  @override
  Widget build(BuildContext context) => SettingsIgnoreListView(this);
}
