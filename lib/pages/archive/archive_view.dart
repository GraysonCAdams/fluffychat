// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/archive/archive.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ArchiveView extends StatelessWidget {
  final ArchiveController controller;

  const ArchiveView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).archive),
        actions: [
          if (controller.loaded && controller.archive.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextButton.icon(
                onPressed: controller.forgetAllAction,
                label: Text(L10n.of(context).clearArchive),
                icon: const Icon(Icons.cleaning_services_outlined),
              ),
            ),
        ],
        // The stored archive is on screen while the server is asked again.
        bottom: controller.loaded && controller.refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: MaxWidthBody(
        withScrolling: false,
        child: Builder(
          builder: (BuildContext context) {
            if (!controller.loaded && controller.error != null) {
              return Center(
                child: Text(
                  L10n.of(context).oopsSomethingWentWrong,
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!controller.loaded) {
              return const Center(
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              );
            } else {
              if (controller.archive.isEmpty) {
                return const Center(
                  child: Icon(Icons.archive_outlined, size: 80),
                );
              }
              return ListView.builder(
                itemCount: controller.archive.length,
                itemBuilder: (BuildContext context, int i) => ChatListItem(
                  controller.archive[i].room,
                  onForget: () => controller.forgetRoomAction(i),
                  onTap: () => context.go(
                    '/rooms/archive/${controller.archive[i].room.id}',
                    extra: controller.archive[i].timeline,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
