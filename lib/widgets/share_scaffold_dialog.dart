// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

abstract class ShareItem {}

class TextShareItem extends ShareItem {
  final String value;
  TextShareItem(this.value);
}

class ContentShareItem extends ShareItem {
  final Map<String, Object?> value;
  ContentShareItem(this.value);
}

class FileShareItem extends ShareItem {
  final XFile value;
  FileShareItem(this.value);
}

class ShareScaffoldDialog extends StatefulWidget {
  final List<ShareItem> items;

  const ShareScaffoldDialog({required this.items, super.key});

  @override
  State<ShareScaffoldDialog> createState() => _ShareScaffoldDialogState();
}

class _ShareScaffoldDialogState extends State<ShareScaffoldDialog> {
  final TextEditingController _filterController = TextEditingController();

  String? selectedRoomId;

  void _toggleRoom(String roomId) {
    setState(() {
      selectedRoomId = roomId;
    });
  }

  Future<void> _forwardAction() async {
    final roomId = selectedRoomId;
    if (roomId == null) {
      throw Exception(
        'Started forward action before room was selected. This should never happen.',
      );
    }
    if (widget.items.any((item) => item is! FileShareItem)) {
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).forwardCountMessages(widget.items.length),
        okLabel: L10n.of(context).forward,
        cancelLabel: L10n.of(context).cancel,
      );
      if (consent != OkCancelResult.ok) return;
    }
    if (!mounted) return;
    while (context.canPop()) {
      context.pop();
    }
    context.go('/rooms/$roomId', extra: widget.items);
  }

  final Map<String, (Room, bool, bool, _ShareRoomRow)> _rows = {};

  /// The row for [room], reused as the same widget instance while its
  /// selection and filter state stay the same. Selecting a chat or typing in
  /// the filter rebuilds this whole dialog, and a row handed back unchanged
  /// is skipped, so only the rows that look different are built again.
  _ShareRoomRow _row(Room room, bool selected, bool filteredOut) {
    final cached = _rows[room.id];
    if (cached != null &&
        identical(cached.$1, room) &&
        cached.$2 == selected &&
        cached.$3 == filteredOut) {
      return cached.$4;
    }
    final row = _ShareRoomRow(
      room: room,
      selected: selected,
      filteredOut: filteredOut,
      onChanged: () => _toggleRoom(room.id),
      key: ValueKey(room.id),
    );
    _rows[room.id] = (room, selected, filteredOut, row);
    return row;
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = Matrix.of(context).client.rooms
        .where(
          (room) =>
              room.canSendDefaultMessages &&
              !room.isSpace &&
              room.membership == Membership.join,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: CloseButton(onPressed: context.pop)),
        title: Text(L10n.of(context).share),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 72,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: TextField(
              controller: _filterController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                contentPadding: EdgeInsets.zero,
                hintText: L10n.of(context).search,
                hintStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.normal,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: IconButton(
                  onPressed: () {},
                  icon: Icon(
                    Icons.search_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              final displayname = room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              );
              final value = selectedRoomId == room.id;
              final filterOut = !displayname.toLowerCase().contains(filter);
              if (!value && filterOut) {
                return const SizedBox.shrink();
              }
              return _row(room, value, filterOut);
            },
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: selectedRoomId == null
            ? const SizedBox.shrink()
            : Material(
                elevation: 8,
                shadowColor: theme.appBarTheme.shadowColor,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: _forwardAction,
                      child: Text(L10n.of(context).forward),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ShareRoomRow extends StatefulWidget {
  final Room room;
  final bool selected;
  final bool filteredOut;
  final VoidCallback onChanged;

  const _ShareRoomRow({
    required this.room,
    required this.selected,
    required this.filteredOut,
    required this.onChanged,
    super.key,
  });

  @override
  State<_ShareRoomRow> createState() => _ShareRoomRowState();
}

class _ShareRoomRowState extends State<_ShareRoomRow> {
  /// Loads the members a nameless room is named after. Created once per
  /// room: a FutureBuilder given a new future on every build subscribes again
  /// and repeats the SDK call each time.
  late Future<List<User>> _heroUsers;

  @override
  void initState() {
    super.initState();
    _heroUsers = widget.room.loadHeroUsers();
  }

  @override
  void didUpdateWidget(covariant _ShareRoomRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.room, widget.room)) {
      _heroUsers = widget.room.loadHeroUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Opacity(
        opacity: widget.filteredOut ? 0.5 : 1,
        child: FutureBuilder(
          future: _heroUsers,
          builder: (context, _) => CheckboxListTile.adaptive(
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(90),
            ),
            controlAffinity: ListTileControlAffinity.trailing,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            secondary: Avatar(
              mxContent: room.avatar,
              name: displayname,
              size: Avatar.defaultSize * 0.75,
            ),
            title: Text(
              displayname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              room.directChatMatrixID ??
                  L10n.of(context).countParticipants(
                    (room.summary.mJoinedMemberCount ?? 0) +
                        (room.summary.mInvitedMemberCount ?? 0),
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: widget.selected,
            onChanged: (_) => widget.onChanged(),
          ),
        ),
      ),
    );
  }
}
