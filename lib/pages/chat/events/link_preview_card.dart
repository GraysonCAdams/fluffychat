// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/link_preview.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The link preview cards under a text message. Previews the event carries
/// (`com.beeper.linkpreviews`, set by the bridges) are shown as they are;
/// otherwise the first link in the body is looked up on the homeserver, as
/// [shouldFetchServerPreview] and the link preview settings allow. Shows
/// nothing when there is no preview.
class LinkPreviews extends StatelessWidget {
  final Event event;
  final Color textColor;

  const LinkPreviews({super.key, required this.event, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final bridged = bridgeLinkPreviews(event);
    if (bridged != null) {
      if (bridged.isEmpty) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final preview in bridged)
            LinkPreviewCard(
              preview: preview,
              client: event.room.client,
              textColor: textColor,
            ),
        ],
      );
    }

    if (!shouldFetchServerPreview(
      event,
      enabled: AppSettings.linkPreviews.value,
      inEncryptedRooms: AppSettings.linkPreviewsInEncryptedRooms.value,
    )) {
      return const SizedBox.shrink();
    }
    final link = firstLinkIn(event.body);
    if (link == null) return const SizedBox.shrink();

    return FutureBuilder<LinkPreviewData?>(
      future: serverLinkPreview(event.room.client, link),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null) return const SizedBox.shrink();
        return LinkPreviewCard(
          preview: preview,
          client: event.room.client,
          textColor: textColor,
        );
      },
    );
  }
}

class LinkPreviewCard extends StatelessWidget {
  final LinkPreviewData preview;
  final Client client;
  final Color textColor;

  static const double maxWidth = 320;

  const LinkPreviewCard({
    super.key,
    required this.preview,
    required this.client,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = preview.image;
    final width = preview.imageWidth;
    final height = preview.imageHeight;
    // Wide banners keep their shape; tall or unknown images are cropped to
    // a 1.91:1 OpenGraph card so one portrait photo cannot fill the screen.
    final aspectRatio = width != null && height != null && height > 0
        ? (width / height).clamp(1.0, 2.5)
        : 1.91;
    final title = preview.title;
    final description = preview.description;
    final site = preview.siteName ?? preview.url.host;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: textColor.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () =>
                UrlLauncher(context, preview.url.toString()).launchUrl(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (image != null)
                  AspectRatio(
                    aspectRatio: aspectRatio,
                    child: MxcImage(
                      key: ValueKey(image),
                      uri: image,
                      client: client,
                      fit: BoxFit.cover,
                      width: maxWidth,
                      height: maxWidth / aspectRatio,
                      isThumbnail: true,
                      placeholder: (_) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: textColor,
                          ),
                        ),
                      if (description != null)
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withAlpha(200),
                          ),
                        ),
                      Text(
                        site,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: textColor.withAlpha(160),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
