// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/utils/windows_shell.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

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
/// time and above a strip of thumbnails and the actions. On a phone a tap
/// shows or hides those and a drag down puts the picture back; on the
/// desktop they hide while the mouse rests, and the viewer covers the whole
/// window, title bar included.
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

  /// Whether the viewer takes its desktop layout, for tests; the platform
  /// decides when null.
  @visibleForTesting
  static bool? debugDesktopLayout;

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
    if (desktopLayout) {
      _restartIdleTimer();
      if (PlatformInfos.isWindows) {
        // After this frame: the title bar rebuilds when told.
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => WindowsChrome.covers.value++,
        );
        _coversTitleBar = true;
      }
    }
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

  /// Whether the viewer takes its desktop layout: the bars over the picture,
  /// hiding while the mouse rests, and the actions in the top bar.
  bool get desktopLayout =>
      ImageViewer.debugDesktopLayout ?? PlatformInfos.isDesktop;

  /// Whether the strip of the chat's media shows, on the desktop.
  bool filmstripVisible = true;

  /// How far the picture shown is zoomed, against it fitted to the window.
  double zoomScale = 1;

  /// Whether the window is in full screen mode, which the viewer turned on.
  bool fullScreen = false;

  bool _coversTitleBar = false;

  /// The players of the videos paged to, by event ID, for the desktop's
  /// controls.
  final _videos = <String, VideoPlayerController>{};

  final _zoomKeys = <String, GlobalKey<ZoomableMediaState>>{};

  /// How long the mouse rests before the desktop's bars hide.
  static const idleDelay = Duration(milliseconds: 2500);

  Timer? _idleTimer;
  bool _pointerOnChrome = false;

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
    if (!desktopLayout) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        togglePlay();
      case LogicalKeyboardKey.keyF:
        toggleFilmstrip();
      case LogicalKeyboardKey.f11:
        toggleFullScreen();
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        zoomFit();
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        zoomIn();
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        zoomOut();
    }
    onPointerActivity();
  }

  /// Shows the desktop's bars, and hides them again once the mouse has
  /// rested for [idleDelay] off them.
  void onPointerActivity() {
    if (!chromeVisible) setState(() => chromeVisible = true);
    _restartIdleTimer();
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDelay, () {
      if (!mounted || _pointerOnChrome) return;
      setState(() => chromeVisible = false);
    });
  }

  /// Keeps the bars up while the mouse is on them.
  void onPointerOnChrome(bool on) {
    _pointerOnChrome = on;
    onPointerActivity();
  }

  /// The player of the video shown, once it is ready.
  VideoPlayerController? get currentVideo => _videos[currentEvent.eventId];

  /// Keeps the player of [event]'s video for the controls, or drops it when
  /// [controller] is null.
  void onVideoController(Event event, VideoPlayerController? controller) {
    if (controller == null) {
      // The page went with its player; nothing shows it any more.
      _videos.remove(event.eventId);
      return;
    }
    setState(() => _videos[event.eventId] = controller);
  }

  void togglePlay() {
    final video = currentVideo;
    if (video == null) return;
    video.value.isPlaying ? video.pause() : video.play();
  }

  void toggleFilmstrip() =>
      setState(() => filmstripVisible = !filmstripVisible);

  Future<void> toggleFullScreen() async {
    if (!PlatformInfos.isWindows) return;
    final on = !fullScreen;
    await WindowFullScreen.set(on);
    if (mounted) setState(() => fullScreen = on);
  }

  /// The zoom of the picture on page [index], which [zoomIn], [zoomOut] and
  /// [zoomFit] work through.
  GlobalKey<ZoomableMediaState> zoomKey(Event event) =>
      _zoomKeys.putIfAbsent(event.eventId, GlobalKey.new);

  ZoomableMediaState? get _zoom =>
      _zoomKeys[currentEvent.eventId]?.currentState;

  /// How far a zoom step goes.
  static const zoomStep = 1.25;

  void zoomIn() => _zoom?.zoomBy(zoomStep);

  void zoomOut() => _zoom?.zoomBy(1 / zoomStep);

  void zoomFit() => _zoom?.fit();

  void onScaleChanged(Event event, double scale) {
    if (event.eventId != currentEvent.eventId || scale == zoomScale) return;
    setState(() => zoomScale = scale);
  }

  void close() => Navigator.of(context).pop();

  void toggleChrome() => setState(() => chromeVisible = !chromeVisible);

  void onPageChanged(int index) {
    // Pauses the video paged away from; the one paged to plays.
    _videos[currentEvent.eventId]?.pause();
    setState(() {
      currentIndex = index;
      zoomed = false;
      zoomScale = 1;
    });
    _videos[currentEvent.eventId]?.play();
  }

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
    _idleTimer?.cancel();
    if (fullScreen) WindowFullScreen.set(false);
    if (_coversTitleBar) {
      // After this frame: the tree is locked while it disposes.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => WindowsChrome.covers.value--,
      );
    }
    _dragReturn.dispose();
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageViewerView(this);
}
