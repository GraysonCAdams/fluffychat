// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Heads a section of the chat list search, such as Chats or Messages: a
/// Material list subheader in title small and the primary colour, 16 in from
/// the edge to line up with the rows' avatars. Sections are set apart by
/// the space above the heading, not by lines.
class SearchTitle extends StatelessWidget {
  final String title;

  /// Shown at the end of the heading, such as progress while the section
  /// loads.
  final Widget? trailing;

  const SearchTitle({required this.title, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SizedBox(
          height: 20,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
