// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// `com.beeper.room_features` content from a real iMessage bridge room, cut
/// down to the `file` map.
const Map<String, Object?> iMessageFeatures = {
  'file': {
    'm.file': {
      'caption': 2,
      'max_size': 2097152000,
      'mime_types': {'*/*': 2},
    },
    'm.image': {
      'caption': 2,
      'mime_types': {
        'image/gif': 2,
        'image/png': 2,
        'image/heic': 2,
        'image/heif': 2,
        'image/jpeg': 2,
        'image/webp': 2,
      },
    },
    'm.video': {
      'caption': 2,
      'mime_types': {'video/mp4': 2, 'video/quicktime': 1},
    },
    'm.audio': {
      'mime_types': {'*/*': 2},
    },
  },
};

/// `com.beeper.room_features` content from a real Google Messages bridge
/// room, cut down to the `file` map.
const Map<String, Object?> googleMessagesFeatures = {
  'file': {
    'm.file': {
      'caption': 2,
      'max_size': 104857600,
      'mime_types': {'text/*': 2, 'application/*': 2},
    },
    'm.image': {
      'caption': 2,
      'mime_types': {
        'image/bmp': 2,
        'image/gif': 2,
        'image/png': 2,
        'image/jpeg': 2,
        'image/wbmp': 2,
        'image/webp': 2,
      },
    },
    'm.video': {
      'caption': 2,
      'mime_types': {'video/mp4': 2, 'video/3gpp': 2, 'video/webm': 2},
    },
  },
};

/// A made-up room that refuses captions on every media type, standing in for
/// the RCS rooms where the bridge answers "captions are not supported here".
const Map<String, Object?> noCaptionFeatures = {
  'file': {
    'm.file': {
      'caption': -2,
      'mime_types': {'*/*': 2},
    },
    'm.image': {
      'caption': -2,
      'mime_types': {'image/png': 2, 'image/jpeg': 2},
    },
    'm.video': {
      'caption': -2,
      'mime_types': {'video/mp4': 2},
    },
  },
};
