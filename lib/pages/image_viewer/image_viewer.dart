// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/matrix_sdk_extensions/event_extension.dart';

class ImageViewer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  /// Where [event]'s video starts, when it was already playing in its chat
  /// message. Other videos paged to start at the beginning.
  final Duration? videoStartPosition;

  const ImageViewer(
    this.event, {
    required this.outerContext,
    this.timeline,
    this.videoStartPosition,
    super.key,
  });

  @override
  ImageViewerController createState() => ImageViewerController();
}

/// The pictures and videos of [timeline] the viewer pages through, oldest
/// first: each message once, as the chat shows it with its latest edit
/// applied, beside the message it came from. A bridge can send a picture
/// as an edit of a placeholder text, so a message counts by its edited
/// content, and the edits themselves are not pages of their own.
List<({Event shown, Event original})> viewerGallery(Timeline timeline) {
  const types = {MessageTypes.Image, MessageTypes.Sticker};
  return [
    for (final original in timeline.events.reversed)
      if (original.relationshipType != RelationshipTypes.edit)
        if (original.getDisplayEvent(timeline) case final shown
            when types.contains(shown.messageType) ||
                (PlatformInfos.supportsVideoPlayer &&
                    shown.messageType == MessageTypes.Video))
          (shown: shown, original: original),
  ];
}

class ImageViewerController extends State<ImageViewer> {
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final timeline = widget.timeline;
    final gallery = timeline == null
        ? [(shown: widget.event, original: widget.event)]
        : viewerGallery(timeline);
    allEvents = [for (final entry in gallery) entry.shown];
    var index = gallery.indexWhere(
      (entry) =>
          entry.shown.eventId == widget.event.eventId ||
          entry.original.eventId == widget.event.eventId,
    );
    if (index < 0) index = 0;
    pageController = PageController(initialPage: index);
  }

  late final PageController pageController;

  late final List<Event> allEvents;

  void onKeyEvent(KeyEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (canGoBack) prevImage();
        break;
      case LogicalKeyboardKey.arrowRight:
        if (canGoNext) nextImage();
        break;
    }
  }

  Future<void> prevImage() async {
    await pageController.previousPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> nextImage() async {
    await pageController.nextPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  int get _index => pageController.page?.toInt() ?? 0;

  Event get currentEvent => allEvents[_index];

  bool get canGoNext => _index < allEvents.length - 1;

  bool get canGoBack => _index > 0;

  /// Forward this image to another room: the viewer closes and the compose
  /// screen asks who to, with the image staged in its composer.
  void forwardAction() {
    final router = GoRouter.of(context);
    final content = currentEvent.content.copy();
    Navigator.of(context).pop();
    router.push(
      '/rooms/newprivatechat',
      extra: SharedDraft([ContentShareItem(content)]),
    );
  }

  /// Save this file with a system call.
  void saveFileAction(BuildContext context) => currentEvent.saveFile(context);

  /// Save this file with a system call.
  void shareFileAction(BuildContext context) => currentEvent.shareFile(context);

  static const maxScaleFactor = 1.5;

  /// Go back if user swiped it away
  void onInteractionEnds(ScaleEndDetails endDetails) {
    if (PlatformInfos.usesTouchscreen == false) {
      if (endDetails.velocity.pixelsPerSecond.dy >
          MediaQuery.sizeOf(context).height * maxScaleFactor) {
        Navigator.of(context, rootNavigator: false).pop();
      }
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageViewerView(this);
}
