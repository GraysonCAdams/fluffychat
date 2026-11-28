// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The key a bridge sets, at the top level of an edit's content, on an edit
/// that only completes its message rather than changing what the sender
/// said: mautrix-gmessages, for one, sends a "Waiting for attachment"
/// notice and then an edit that swaps in the photo or video.
const dontRenderEditedKey = 'com.beeper.dont_render_edited';

/// Whether [edit] should earn its message the "(edited)" mark, which it does
/// unless it carries [dontRenderEditedKey] set to true.
bool editShowsEditedMark(Event edit) =>
    edit.content[dontRenderEditedKey] != true;

/// Whether a message with the edits [edits] shows the "(edited)" mark: when
/// at least one of them is not marked [dontRenderEditedKey].
bool showsEditedMark(Iterable<Event> edits) => edits.any(editShowsEditedMark);

extension EditedMarkExtension on Event {
  /// Whether this message shows the "(edited)" mark in [timeline]; see
  /// [showsEditedMark].
  bool showsEditedMarkIn(Timeline timeline) =>
      showsEditedMark(aggregatedEvents(timeline, RelationshipTypes.edit));
}
