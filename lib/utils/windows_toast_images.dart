// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The images of a message toast: the chat's [avatar] in the app logo slot
/// (cropped round when [roundAvatar]), and under the text, at its own
/// proportions, the [media] picture of a photo or video message.
///
/// The picture is inline rather than a `hero`: a hero is cropped to a wide
/// banner, which cuts a portrait photo.
List<WindowsImage> windowsToastImages({
  required Uri avatar,
  required String title,
  required bool roundAvatar,
  Uri? media,
  required String mediaAltText,
}) => [
  WindowsImage(
    avatar,
    altText: title,
    placement: WindowsImagePlacement.appLogoOverride,
    crop: roundAvatar ? WindowsImageCrop.circle : null,
  ),
  if (media != null) WindowsImage(media, altText: mediaAltText),
];
