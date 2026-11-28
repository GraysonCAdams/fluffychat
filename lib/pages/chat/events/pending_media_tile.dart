// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/chat/events/media_sending_indicator.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/utils/pending_media.dart';
import 'package:material_ui/material_ui.dart';

/// The shape a photo or video the bridge has announced takes before it
/// arrives: its own when the bridge's data gives it ([PendingMedia.aspectRatio]),
/// else 4:3, sized the way the media's own bubble will be.
Size pendingMediaTileSize(PendingMedia media) {
  final ratio = media.aspectRatio ?? 4 / 3;
  return media.kind == PendingMediaKind.video
      ? videoBubbleSize(ratio)
      : imageBubbleSize(ratio);
}

/// The tile shown for a photo or video the Google Messages bridge has not
/// delivered yet ([PendingMedia]), in place of its "Waiting for attachment"
/// notice.
///
/// While pending it shows the media's low-resolution preview, blurred,
/// when the bridge sent one that decodes, else a plain surface with a photo
/// or video glyph (the blurred preview already reads as the picture, so it
/// carries no glyph); the progress ring the user's own uploads show
/// ([MediaProgressDisc]) sits in the bottom-right corner. When the
/// attachment failed to transfer, the glyph turns to its broken form in
/// the error colour and a line under the tile says so.
class PendingMediaTile extends StatelessWidget {
  final PendingMedia media;
  final BorderRadius borderRadius;

  const PendingMediaTile({
    required this.media,
    required this.borderRadius,
    super.key,
  });

  /// The blur over the preview. The bridge's previews are about 60 pixels
  /// across and drawn several times larger, so this has to be strong
  /// enough to hide their blocks.
  static const double previewBlurSigma = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final size = pendingMediaTileSize(media);
    final failed = media.state == PendingMediaState.failed;

    final surface = ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          switch ((media.kind, failed)) {
            (PendingMediaKind.video, false) => Icons.videocam_outlined,
            (PendingMediaKind.video, true) => Icons.videocam_off_outlined,
            (PendingMediaKind.image, false) => Icons.image_outlined,
            (PendingMediaKind.image, true) => Icons.broken_image_outlined,
            (PendingMediaKind.file, false) => Icons.insert_drive_file_outlined,
            (PendingMediaKind.file, true) => Icons.error_outline,
          },
          size: 32,
          color: failed ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );

    final preview = media.preview;
    // The plain tile stays underneath, so a preview still decoding, or one
    // that does not decode at all, leaves it showing.
    final background = preview == null || failed
        ? surface
        : Stack(
            fit: StackFit.expand,
            children: [
              surface,
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: previewBlurSigma,
                    sigmaY: previewBlurSigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: Image.memory(
                    preview,
                    width: size.width,
                    height: size.height,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          );

    final label = failed
        ? switch (media.kind) {
            PendingMediaKind.image => l10n.photoDidNotArrive,
            PendingMediaKind.video => l10n.videoDidNotArrive,
            PendingMediaKind.file => l10n.attachmentDidNotArrive,
          }
        : l10n.waitingForAttachment;

    return Semantics(
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            clipBehavior: Clip.hardEdge,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: BorderSide(color: theme.dividerColor),
            ),
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  background,
                  if (!failed)
                    const Positioned(
                      right: MediaSendingIndicator.inset,
                      bottom: MediaSendingIndicator.inset,
                      child: MediaProgressDisc(),
                    ),
                ],
              ),
            ),
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Swaps a pending media tile for the media the bridge's edit brings, with
/// the tile cross-fading out and the bubble growing or shrinking from the
/// tile's shape to the media's, on Seam's standard motion
/// ([FluffyThemes.animationDuration], [FluffyThemes.animationCurve]).
class PendingMediaSwitcher extends StatelessWidget {
  final Widget child;

  /// Whether [child] is the pending tile; the switch from true to false
  /// plays the swap.
  final bool pending;

  const PendingMediaSwitcher({
    required this.child,
    required this.pending,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : FluffyThemes.animationDuration;
    return AnimatedSize(
      duration: duration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: FluffyThemes.animationCurve,
        switchOutCurve: FluffyThemes.animationCurve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(pending ? 'pending' : 'media'),
          child: child,
        ),
      ),
    );
  }
}
