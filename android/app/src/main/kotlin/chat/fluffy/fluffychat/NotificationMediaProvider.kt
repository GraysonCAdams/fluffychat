// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import androidx.core.content.FileProvider

/**
 * Serves the pictures that message notifications show (see
 * `lib/utils/notification_media.dart`). A subclass of its own, so the
 * manifest merger does not clash with another plugin's plain `FileProvider`.
 */
class NotificationMediaProvider : FileProvider()
