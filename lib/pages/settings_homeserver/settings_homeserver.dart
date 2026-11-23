// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_homeserver_view.dart';

class SettingsHomeserver extends StatefulWidget {
  const SettingsHomeserver({super.key});

  @override
  SettingsHomeserverController createState() => SettingsHomeserverController();
}

class SettingsHomeserverController extends State<SettingsHomeserver> {
  Future<({String name, String version, Uri federationBaseUrl})>
  fetchServerInfo() async {
    final client = Matrix.of(context).client;
    final domain = client.userID!.domain!;
    final httpClient = client.httpClient;
    var federationBaseUrl = Uri(host: domain, port: 8448, scheme: 'https');
    try {
      final serverWellKnownResult = await httpClient.get(
        Uri.https(domain, '/.well-known/matrix/server'),
      );
      final serverWellKnown = jsonDecode(serverWellKnownResult.body);
      federationBaseUrl = Uri.https(serverWellKnown['m.server']);
    } catch (e, s) {
      Logs().w(
        'Unable to fetch federation base uri. Use $federationBaseUrl',
        e,
        s,
      );
    }

    final serverVersionResult = await http.get(
      federationBaseUrl.resolveUri(Uri(path: '/_matrix/federation/v1/version')),
    );
    final {
      'server': {'name': String name, 'version': String version},
    } = Map<String, Map<String, dynamic>>.from(
      jsonDecode(serverVersionResult.body),
    );

    return (name: name, version: version, federationBaseUrl: federationBaseUrl);
  }

  Client? _futuresClient;
  late Future<GetWellknownSupportResponse> _wellknownSupport;
  late Future<({String name, String version, Uri federationBaseUrl})>
  _serverInfo;
  late Future<DiscoveryInformation> _wellknown;

  /// Starts the requests the page shows, once per client. Started from
  /// build, every rebuild of the page would send them again and reset the
  /// FutureBuilders to their loading state.
  void _ensureFutures() {
    final client = Matrix.of(context).client;
    if (identical(client, _futuresClient)) return;
    _futuresClient = client;
    _wellknownSupport = client.getWellknownSupport();
    _serverInfo = fetchServerInfo();
    _wellknown = client.getWellknown();
  }

  Future<GetWellknownSupportResponse> get wellknownSupportFuture {
    _ensureFutures();
    return _wellknownSupport;
  }

  Future<({String name, String version, Uri federationBaseUrl})>
  get serverInfoFuture {
    _ensureFutures();
    return _serverInfo;
  }

  Future<DiscoveryInformation> get wellknownFuture {
    _ensureFutures();
    return _wellknown;
  }

  @override
  Widget build(BuildContext context) => SettingsHomeserverView(this);
}
