// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The dev control server over real HTTP against the real engine: injected
// input, a GPU screenshot and the engine's frame timings, none of which a
// widget test has. It pumps its own small app and never opens Seam's data.
//
// On Windows beside a running Seam:
//   set SEAM_SKIP_INSTANCE_LOCK=1
//   flutter test integration_test/dev_control_test.dart -d windows

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/utils/dev_control/dev_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/utils/dev_control_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dev control drives the app over HTTP', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    // Injected events come in as device events, which the live test binding
    // drops unless told otherwise.
    binding.shouldPropagateDevicePointerEvents = true;
    addTearDown(() => binding.shouldPropagateDevicePointerEvents = false);
    HttpOverrides.global = null;

    final events = <String>[];
    var location = '/rooms';
    await tester.pumpWidget(DevControlFixture(events: events));
    await tester.pumpAndSettle();

    final dir = await Directory.systemTemp.createTemp('devctl');
    final server = await DevControlServer.start(
      control: DevControl(go: (l) => location = l, location: () => location),
      tokenFile: File('${dir.path}/devctl.json'),
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    });

    Future<HttpClientResponse> send(
      String method,
      String route, [
      Map<String, Object?>? body,
    ]) async {
      final request = await client.open(
        method,
        '127.0.0.1',
        server.port,
        route,
      );
      request.headers.set('authorization', 'Bearer ${server.token}');
      if (body != null) request.write(jsonEncode(body));
      return request.close();
    }

    Future<Map<String, Object?>> json(
      String method,
      String route, [
      Map<String, Object?>? body,
    ]) async {
      final response = await send(method, route, body);
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 200, reason: '$method $route: $text');
      return jsonDecode(text) as Map<String, Object?>;
    }

    final info = await json('GET', '/info');
    // ignore: avoid_print
    print('devctl info: ${jsonEncode(info)}');

    await json('POST', '/tap', {'key': 'counter'});
    await json('POST', '/wait', {'text': 'Count: 1'});
    expect(events, contains('tap'));

    await json('POST', '/type', {
      'key': 'field',
      'value': 'hi',
      'submit': true,
    });
    expect(events, contains('submitted:hi'));

    await json('POST', '/key', {'keys': 'ctrl+k'});
    expect(events, contains('ctrl+k'));

    await json('POST', '/longpress', {'key': 'pad'});
    await json('POST', '/rightclick', {'key': 'pad'});
    expect(events, containsAll(['longpress', 'rightclick']));

    final sem = await json('GET', '/semantics?tooltip=Settings');
    expect(sem['count'], 1);
    await json('POST', '/tap', {'tooltip': 'Settings'});
    expect(events, contains('settings'));
    await json('POST', '/semantics/release');

    await json('POST', '/scroll', {'key': 'list', 'dy': 400, 'steps': 4});
    await json('POST', '/wait', {'text': 'Item 10'});

    // A screenshot at the view's physical size.
    final shot = await send('GET', '/screenshot');
    expect(shot.statusCode, 200);
    final png = await shot.fold<List<int>>([], (a, b) => a..addAll(b));
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
    final frame = await codec.getNextFrame();
    final view = (info['views'] as List).first as Map;
    final dpr = view['devicePixelRatio'] as num;
    expect(frame.image.width, closeTo((view['width'] as num) * dpr, 1));
    frame.image.dispose();

    // Frame timings while something animates: the engine's own numbers.
    await json('POST', '/frames/mark', {'name': 'spin'});
    await json('POST', '/tap', {'key': 'spin'});
    await Future<void>.delayed(const Duration(seconds: 2));
    await json('POST', '/frames/mark', {'name': 'spin:end'});
    final frames = await json('GET', '/frames?since=spin&until=spin:end');
    // ignore: avoid_print
    print('devctl frames: ${jsonEncode(frames)}');
    expect(frames['frames'] as int, greaterThan(30));
    expect((frames['buildMs'] as Map)['max'], isNotNull);
    final skew = (await json('GET', '/info'))['clockSkewUs'] as int;
    // Marks and frame times read the same monotonic clock.
    expect(skew.abs(), lessThan(5 * 1000 * 1000));

    final logs = await json('GET', '/logs?lines=5');
    expect(logs['lines'], isA<List>());

    // Unauthorised requests are refused.
    final request = await client.get('127.0.0.1', server.port, '/info');
    final refused = await request.close();
    await refused.drain<void>();
    expect(refused.statusCode, 401);
  });
}
