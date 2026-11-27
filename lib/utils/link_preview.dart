// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// One link preview card's worth of OpenGraph data, from either source a
/// message can have: the `com.beeper.linkpreviews` list a bridge or Beeper
/// client puts in the event content, or the homeserver's
/// `/_matrix/client/v1/media/preview_url`.
class LinkPreviewData {
  /// The link the card opens: `og:url`, else the URL found in the message.
  final Uri url;
  final String? title;
  final String? description;
  final String? siteName;

  /// An `mxc://` image. Null when there is none, or when it is an
  /// encrypted file (`beeper:image:encryption`), which this card does not
  /// decrypt.
  final Uri? image;
  final int? imageWidth;
  final int? imageHeight;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.image,
    this.imageWidth,
    this.imageHeight,
  });

  /// Reads OpenGraph keys ([og]) for the link [fallbackUrl]. Returns null
  /// when there is nothing to show beyond the link itself.
  static LinkPreviewData? fromOpenGraph(
    Map<String, Object?> og, {
    Uri? fallbackUrl,
  }) {
    String? text(String key) {
      final value = og[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    int? number(String key) {
      final value = og[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    final url =
        _httpUri(text('og:url')) ??
        _httpUri(text('matched_url')) ??
        fallbackUrl;
    if (url == null) return null;

    final imageUri = Uri.tryParse(text('og:image') ?? '');
    final image =
        imageUri != null &&
            imageUri.scheme == 'mxc' &&
            og['beeper:image:encryption'] == null
        ? imageUri
        : null;

    final title = text('og:title');
    final description = text('og:description');
    if (title == null && description == null && image == null) return null;

    return LinkPreviewData(
      url: url,
      title: title,
      description: description,
      siteName: text('og:site_name'),
      image: image,
      imageWidth: number('og:image:width'),
      imageHeight: number('og:image:height'),
    );
  }

  static Uri? _httpUri(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }
}

/// The `com.beeper.linkpreviews` key bridges (mautrix-imessage, -gmessages,
/// -telegram and others) attach to messages with links.
const beeperLinkPreviewsKey = 'com.beeper.linkpreviews';

/// The previews the event itself carries, or null when it has no
/// `com.beeper.linkpreviews` key. An empty list means the sender attached
/// none on purpose (Beeper's convention for "previews off"), and callers
/// must not fetch one from the server either.
List<LinkPreviewData>? bridgeLinkPreviews(Event event) {
  final raw = event.content[beeperLinkPreviewsKey];
  if (raw is! List) return null;
  return [
    for (final entry in raw)
      if (entry is Map)
        ?LinkPreviewData.fromOpenGraph(Map<String, Object?>.from(entry)),
  ];
}

final _linkPattern = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);

/// The first http(s) link in [body], without the punctuation a sentence
/// puts after it.
Uri? firstLinkIn(String body) {
  for (final match in _linkPattern.allMatches(body)) {
    var link = match.group(0)!;
    while (link.isNotEmpty && '.,;:!?)]}'.contains(link[link.length - 1])) {
      // Keep a closing bracket that pairs with one inside the link, as in
      // Wikipedia's `..._(disambiguation)`.
      final last = link[link.length - 1];
      if (last == ')' &&
          '('.allMatches(link).length >= ')'.allMatches(link).length) {
        break;
      }
      link = link.substring(0, link.length - 1);
    }
    final uri = Uri.tryParse(link);
    if (uri != null && uri.host.isNotEmpty) return uri;
  }
  return null;
}

/// Whether to ask the homeserver for a preview of a link in [event]. The
/// server fetches the page itself, so it learns the URL: in an encrypted
/// room that is only done when [inEncryptedRooms] allows it.
bool shouldFetchServerPreview(
  Event event, {
  required bool enabled,
  required bool inEncryptedRooms,
}) {
  if (!enabled) return false;
  if (event.redacted) return false;
  if (event.content.containsKey(beeperLinkPreviewsKey)) return false;
  if (event.room.encrypted && !inEncryptedRooms) return false;
  return true;
}

/// Answers for links already asked about, per account, so a scrolling
/// timeline asks the server once per URL. A failed lookup is kept as null
/// for the session: the server answers the same way until its own cache
/// expires.
final _serverPreviews = <String, Future<LinkPreviewData?>>{};

/// The homeserver's preview of [url], or null when it has none or the
/// request fails (preview_url disabled, the page unreachable, no
/// OpenGraph data). Never throws.
Future<LinkPreviewData?> serverLinkPreview(Client client, Uri url) =>
    _serverPreviews.putIfAbsent('${client.userID}|$url', () async {
      try {
        final preview = await client.getUrlPreview(url);
        return LinkPreviewData.fromOpenGraph({
          ...preview.additionalProperties,
          if (preview.ogImage != null) 'og:image': preview.ogImage.toString(),
        }, fallbackUrl: url);
      } catch (e) {
        Logs().v('No link preview from the server for $url', e);
        return null;
      }
    });

/// Forgets every cached server preview. For tests.
void clearServerLinkPreviewCache() => _serverPreviews.clear();
