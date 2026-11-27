// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/matrix_sdk_extensions/event_extension.dart';

/// Opens the media viewer on [event] over a see-through page, so the
/// picture can fly in from its bubble and back. In a chat, the viewer can
/// answer the picture and find it in the chat.
Future<void> showImageViewer(
  BuildContext context,
  Event event, {
  Timeline? timeline,
  Duration? videoStartPosition,
}) {
  final chat = context.findAncestorStateOfType<ChatController>();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: FluffyThemes.animationDuration,
      reverseTransitionDuration: FluffyThemes.animationDuration,
      pageBuilder: (_, _, _) => ImageViewer(
        event,
        timeline: timeline,
        outerContext: context,
        videoStartPosition: videoStartPosition,
        onReply: chat == null || !event.room.canSendDefaultMessages
            ? null
            : (event) => chat.replyAction(replyTo: event),
        onShowInChat: chat == null
            ? null
            : (event) => chat.scrollToEventId(event.eventId),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The full screen media viewer: one picture or video at a time, paged
/// through all of the chat's media, under a top bar naming the sender and
/// time and above a strip of thumbnails and the actions. A tap shows or
/// hides those; a drag down puts the picture back.
class ImageViewer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  /// Where [event]'s video starts, when it was already playing in its chat
  /// message. Other videos paged to start at the beginning.
  final Duration? videoStartPosition;

  /// Answers a message from the viewer, which closes first. Without it the
  /// viewer offers no reply.
  final void Function(Event event)? onReply;

  /// Shows a message in its chat, which closes the viewer first. Without it
  /// the viewer does not offer it.
  final void Function(Event event)? onShowInChat;

  const ImageViewer(
    this.event, {
    required this.outerContext,
    this.timeline,
    this.videoStartPosition,
    this.onReply,
    this.onShowInChat,
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

class ImageViewerController extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final timeline = widget.timeline;
    final gallery = timeline == null
        ? [(shown: widget.event, original: widget.event)]
        : viewerGallery(timeline);
    allEvents = [for (final entry in gallery) entry.shown];
    _originals = [for (final entry in gallery) entry.original];
    var index = gallery.indexWhere(
      (entry) =>
          entry.shown.eventId == widget.event.eventId ||
          entry.original.eventId == widget.event.eventId,
    );
    if (index < 0) index = 0;
    currentIndex = index;
    pageController = PageController(initialPage: index);
    _dragReturn =
        AnimationController(
          vsync: this,
          duration: FluffyThemes.animationDuration,
        )..addListener(
          () => setState(
            () => dragOffset = _dragReturnFrom * (1 - _dragReturn.value),
          ),
        );
  }

  late final PageController pageController;

  late final List<Event> allEvents;

  /// The message each page of [allEvents] came from, before edits.
  late final List<Event> _originals;

  /// The page shown.
  late int currentIndex;

  /// Whether the top bar, the thumbnails and the actions show.
  bool chromeVisible = true;

  /// Whether the picture shown is zoomed in, which keeps a drag panning it
  /// rather than paging or dismissing.
  bool zoomed = false;

  /// How far the picture has been dragged down (or up) to dismiss it.
  double dragOffset = 0;

  late final AnimationController _dragReturn;
  double _dragReturnFrom = 0;

  /// A drag this far, or a flick, closes the viewer.
  static const dismissDistance = 120.0;
  static const dismissVelocity = 900.0;

  /// How far the background has faded for the drag so far, from 0 to 1.
  double get dragProgress =>
      (dragOffset.abs() / (dismissDistance * 2.5)).clamp(0.0, 1.0);

  void onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (canGoBack) prevImage();
        break;
      case LogicalKeyboardKey.arrowRight:
        if (canGoNext) nextImage();
        break;
      case LogicalKeyboardKey.escape:
        close();
        break;
    }
  }

  void close() => Navigator.of(context).pop();

  void toggleChrome() => setState(() => chromeVisible = !chromeVisible);

  void onPageChanged(int index) => setState(() {
    currentIndex = index;
    zoomed = false;
  });

  void onZoomChanged(bool zoomed) {
    if (zoomed == this.zoomed) return;
    setState(() => this.zoomed = zoomed);
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (zoomed) return;
    _dragReturn.stop();
    setState(() => dragOffset += details.delta.dy);
  }

  void onDragEnd(DragEndDetails details) {
    if (zoomed) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (dragOffset.abs() > dismissDistance ||
        velocity.abs() > dismissVelocity) {
      close();
      return;
    }
    _dragReturnFrom = dragOffset;
    _dragReturn.forward(from: 0);
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

  /// Shows page [index], from the thumbnail strip.
  void jumpTo(int index) => pageController.animateToPage(
    index,
    duration: FluffyThemes.animationDuration,
    curve: FluffyThemes.animationCurve,
  );

  Event get currentEvent => allEvents[currentIndex];

  bool get canGoNext => currentIndex < allEvents.length - 1;

  bool get canGoBack => currentIndex > 0;

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

  /// Answers the message shown, in its chat.
  void replyAction() {
    final onReply = widget.onReply;
    if (onReply == null) return;
    final event = currentEvent;
    Navigator.of(context).pop();
    onReply(event);
  }

  /// Scrolls the chat to the message shown.
  void showInChatAction() {
    final onShowInChat = widget.onShowInChat;
    if (onShowInChat == null) return;
    final event = _originals[currentIndex];
    Navigator.of(context).pop();
    onShowInChat(event);
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
    _dragReturn.dispose();
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageViewerView(this);
}
