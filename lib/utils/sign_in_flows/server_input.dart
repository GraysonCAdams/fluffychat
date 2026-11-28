// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// What was typed into the "Server or Matrix ID" field of the server step:
/// a server name (`example.org`), a full address (`https://example.org`,
/// `http://localhost:8008`) or a Matrix ID (`@you:example.org`).
class ServerInput {
  /// The address to look the server up at. Well-known discovery still runs
  /// on it, so a Matrix ID's domain finds a server that lives elsewhere.
  final Uri homeserver;

  /// The localpart of a typed Matrix ID, to fill in on the password step.
  final String? username;

  const ServerInput(this.homeserver, {this.username});

  /// The server as people write it: host, and port if there is one.
  String get label => homeserver.hasPort
      ? '${homeserver.host}:${homeserver.port}'
      : homeserver.host;

  String? get matrixId {
    final username = this.username;
    return username == null ? null : '@$username:$label';
  }

  /// Null until [text] could name a server.
  static ServerInput? parse(String text) {
    text = text.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    String? username;
    if (text.startsWith('@')) {
      final colon = text.indexOf(':');
      if (colon < 2 || colon == text.length - 1) return null;
      username = text.substring(1, colon);
      text = text.substring(colon + 1);
    }
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return null;
    }
    final host = uri.host;
    final looksLikeHost =
        host == 'localhost' ||
        (host.contains('.') &&
            !host.startsWith('.') &&
            !host.endsWith('.') &&
            !host.contains('..'));
    if (!looksLikeHost) return null;
    return ServerInput(
      Uri(scheme: uri.scheme, host: host, port: uri.hasPort ? uri.port : null),
      username: username,
    );
  }
}
