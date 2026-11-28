// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The upload mark on a photo or video this device is sending: a white
/// circular progress indicator on a small dark disc in the media's
/// bottom-right corner, over the picture itself, which stays sharp and
/// undimmed. It follows Google Messages, which shows its ring there while
/// an attachment uploads.
///
/// The ring is indeterminate because `Room.sendFileEvent` reports no upload
/// progress. Google's ring carries a cancel glyph; this one has none,
/// because the SDK cannot stop an upload once it has started.
///
/// It appears only after [delay], so a quick upload never flashes it, and
/// scales in and out unless the platform asks for reduced motion. Place it
/// in a [Stack] over the media.
class MediaSendingIndicator extends StatefulWidget {
  final Event event;

  /// How long a send runs before the ring shows.
  final Duration delay;

  const MediaSendingIndicator({
    required this.event,
    this.delay = const Duration(milliseconds: 300),
    super.key,
  });

  /// The disc's diameter.
  static const double size = 36;

  /// Its inset from the media's bottom and right edges.
  static const double inset = 8;

  @override
  State<MediaSendingIndicator> createState() => _MediaSendingIndicatorState();
}

class _MediaSendingIndicatorState extends State<MediaSendingIndicator> {
  bool _delayPassed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _delayPassed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sending = widget.event.status == EventStatus.sending;
    final visible = sending && _delayPassed;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      right: MediaSendingIndicator.inset,
      bottom: MediaSendingIndicator.inset,
      child: IgnorePointer(
        child: AnimatedScale(
          scale: visible ? 1 : 0,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: visible ? Curves.easeOutBack : Curves.easeIn,
          child: Semantics(
            label: L10n.of(context).sending,
            child: const MediaProgressDisc(),
          ),
        ),
      ),
    );
  }
}

/// The ring [MediaSendingIndicator] shows: a white indeterminate circular
/// progress indicator on a [MediaSendingIndicator.size] dark disc, legible
/// on any picture. The pending tile of an incoming attachment shows it too.
class MediaProgressDisc extends StatelessWidget {
  const MediaProgressDisc({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: MediaSendingIndicator.size,
    height: MediaSendingIndicator.size,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black.withAlpha(110),
      shape: BoxShape.circle,
    ),
    child: const CircularProgressIndicator(
      strokeWidth: 2.5,
      color: Colors.white,
      backgroundColor: Colors.white24,
    ),
  );
}
