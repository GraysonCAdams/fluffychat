// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/utils/dev_control/dev_control.dart';
import 'package:fluffychat/utils/dev_control/dev_control_flag.dart';
import 'package:fluffychat/utils/dev_control/frame_recorder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dev_control_fixture.dart';

/// Runs a request while pumping frames and time until it answers, as the
/// handlers wait for frames and timers that only pumping produces here.
Future<Map<String, Object?>> call(
  WidgetTester tester,
  DevControl control,
  String method,
  String route, [
  Map<String, Object?> params = const {},
  int status = 200,
]) async {
  DevControlResponse? response;
  unawaited(
    control.handle(method, route, {...params}).then((r) => response = r),
  );
  for (var i = 0; i < 500 && response == null; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(response, isNotNull, reason: '$method $route never answered');
  expect(response!.status, status, reason: jsonEncode(response!.json));
  return response!.body;
}

void main() {
  test('is off unless the build defines SEAM_DEV_CONTROL', () {
    expect(kDevControlEnabled, isFalse);
    expect(kDevControlPort, 47913);
  });

  group('requests', () {
    late List<String> events;
    late DevControl control;
    var location = '/rooms';

    Future<void> pumpFixture(WidgetTester tester) async {
      events = [];
      control = DevControl(
        go: (l) => location = l,
        location: () => location,
        framesWait: Duration.zero,
      );
      await tester.pumpWidget(DevControlFixture(events: events));
    }

    tearDown(() => control.stop());

    testWidgets('finds widgets by key, text and type', (tester) async {
      await pumpFixture(tester);
      final byKey = await call(tester, control, 'GET', '/widgets', {
        'key': 'counter',
      });
      expect(byKey['count'], 1);
      final widget = (byKey['widgets'] as List).single as Map;
      final rect = tester.getRect(find.byKey(const ValueKey('counter')));
      expect((widget['rect'] as Map)['x'], closeTo(rect.left, 0.1));
      expect((widget['rect'] as Map)['w'], closeTo(rect.width, 0.1));
      expect(widget['hittable'], isTrue);

      final byText = await call(tester, control, 'GET', '/widgets', {
        'textContains': 'Item 1',
      });
      // Item 1 and Item 10 to 19 are on screen; the rest of the list is not
      // built.
      expect(byText['count'], greaterThanOrEqualTo(2));
      final byType = await call(tester, control, 'GET', '/widgets', {
        'type': 'TextField',
      });
      expect(byType['count'], 1);
    });

    testWidgets('taps by key, text and point', (tester) async {
      await pumpFixture(tester);
      await call(tester, control, 'POST', '/tap', {'key': 'counter'});
      await call(tester, control, 'POST', '/tap', {'text': 'Add one'});
      final center = tester.getCenter(find.byKey(const ValueKey('counter')));
      await call(tester, control, 'POST', '/tap', {
        'x': center.dx,
        'y': center.dy,
        'kind': 'touch',
      });
      expect(events.where((e) => e == 'tap'), hasLength(3));
      expect(find.text('Count: 3'), findsOneWidget);
    });

    testWidgets('long-presses, right-clicks and hovers', (tester) async {
      await pumpFixture(tester);
      await call(tester, control, 'POST', '/longpress', {'key': 'pad'});
      await call(tester, control, 'POST', '/rightclick', {'key': 'pad'});
      expect(events, containsAll(['longpress', 'rightclick']));

      Color box() =>
          (tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(const ValueKey('hoverbox')),
                      matching: find.byType(Container),
                    ),
                  )
                  .color)
              as Color;
      expect(box(), Colors.grey);
      await call(tester, control, 'POST', '/hover', {'key': 'hoverbox'});
      expect(box(), Colors.green);
      await call(tester, control, 'POST', '/hover', {'leave': true});
      expect(box(), Colors.grey);
    });

    testWidgets('types into a field and submits', (tester) async {
      await pumpFixture(tester);
      final typed = await call(tester, control, 'POST', '/type', {
        'key': 'field',
        'value': 'hello',
      });
      expect(typed['text'], 'hello');
      await call(tester, control, 'POST', '/type', {
        'value': ' world',
        'submit': true,
      });
      expect(events, contains('changed:hello world'));
      expect(events, contains('submitted:hello world'));
      // Submitting with the done action unfocuses the field, so this one
      // names it again.
      await call(tester, control, 'POST', '/type', {
        'key': 'field',
        'value': 'new',
        'replace': true,
      });
      expect(events.last, 'changed:new');

      // With nothing focused there is nowhere to type.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await call(tester, control, 'POST', '/type', {'value': 'x'}, 404);
    });

    testWidgets('presses key chords', (tester) async {
      await pumpFixture(tester);
      final pressed = await call(tester, control, 'POST', '/key', {
        'keys': 'ctrl+k',
      });
      expect(events, contains('ctrl+k'));
      expect(pressed['handled'], [true]);
      // The modifiers are released again.
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
      await call(tester, control, 'POST', '/key', {'keys': 'nosuchkey'}, 400);
    });

    testWidgets('scrolls with the wheel and by dragging', (tester) async {
      await pumpFixture(tester);
      final state = tester.state<DevControlFixtureState>(
        find.byType(DevControlFixture),
      );
      await call(tester, control, 'POST', '/scroll', {
        'key': 'list',
        'dy': 500,
        'steps': 5,
      });
      expect(state.list.offset, closeTo(500, 1));
      await call(tester, control, 'POST', '/drag', {
        'key': 'list',
        'dy': 200,
        'durationMs': 200,
      });
      expect(state.list.offset, lessThan(500));
    });

    testWidgets('finds and taps by semantics label and tooltip', (
      tester,
    ) async {
      await pumpFixture(tester);
      final nodes = await call(tester, control, 'GET', '/semantics', {
        'tooltip': 'Settings',
      });
      expect(nodes['count'], 1);
      final node = (nodes['nodes'] as List).single as Map;
      expect(node['actions'], contains('tap'));
      // The node's rect lines up with the widget's.
      final rect = tester.getRect(find.byType(IconButton));
      final r = node['rect'] as Map;
      expect(r['x'] as double, closeTo(rect.left, 4));
      expect(r['y'] as double, closeTo(rect.top, 4));
      await call(tester, control, 'POST', '/tap', {'tooltip': 'Settings'});
      expect(events, contains('settings'));
      expect(control.finder.semanticsHeld, isTrue);
      await call(tester, control, 'POST', '/semantics/release');
      expect(control.finder.semanticsHeld, isFalse);
    });

    testWidgets('waits for a widget', (tester) async {
      await pumpFixture(tester);
      final waited = await call(tester, control, 'POST', '/wait', {
        'text': 'Count: 0',
      });
      expect(waited['waitedMs'], isNotNull);
      await call(tester, control, 'POST', '/wait', {
        'text': 'Count: 9',
        'timeoutMs': 300,
      }, 404);
    });

    testWidgets('navigates and reports the route', (tester) async {
      await pumpFixture(tester);
      await call(tester, control, 'POST', '/go', {
        'roomId': '!abc:example.org',
      });
      expect(location, '/rooms/!abc:example.org');
      final route = await call(tester, control, 'GET', '/route');
      expect(route['location'], '/rooms/!abc:example.org');
    });

    testWidgets('answers unknown requests and targets with errors', (
      tester,
    ) async {
      await pumpFixture(tester);
      await call(tester, control, 'GET', '/nope', {}, 404);
      await call(tester, control, 'POST', '/tap', {'key': 'missing'}, 404);
      await call(tester, control, 'POST', '/tap', {}, 400);
    });

    testWidgets('takes a screenshot', (tester) async {
      await pumpFixture(tester);
      control.nextFrame = () async {};
      final response = await tester.runAsync(
        () => control.handle('GET', '/screenshot', {}),
      );
      expect(response!.contentType, 'image/png');
      // The PNG signature.
      expect(response.bytes!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    });
  });

  group('frame summaries', () {
    RecordedFrame frame(
      int n,
      int start, {
      int build = 4000,
      int raster = 3000,
    }) => RecordedFrame(
      number: n,
      vsyncStart: start,
      rasterFinish: start + build + raster,
      build: build,
      raster: raster,
      vsyncOverhead: 100,
      total: build + raster,
    );

    test('counts frames over budget and gaps after a mark', () {
      final recorder = FrameRecorder();
      recorder.addAll([frame(1, 0), frame(2, 16667)], now: 30000);
      recorder.mark('open', now: 20000);
      recorder.addAll([
        frame(3, 33333),
        frame(4, 50000, build: 20000),
        // Two vsyncs pass with no frame.
        frame(5, 100000, raster: 10000),
      ], now: 120000);
      final frames = recorder.between(since: 'open');
      expect(frames.map((f) => f.number), [3, 4, 5]);
      final summary = FrameRecorder.summarise(frames, budgetMs: 16.667);
      expect(summary['frames'], 3);
      expect(summary['overBudget'], 1);
      expect(summary['over16ms'], 1);
      expect(summary['over8ms'], 2);
      expect(summary['buildOverBudget'], 1);
      expect(summary['missedVsyncs'], 2);
      expect(summary['longestGapMs'], 50);
      expect((summary['buildMs'] as Map)['max'], 20);
      expect((summary['worst'] as List).first, containsPair('number', 4));
    });

    test('falls back to frame numbers when the clocks disagree', () {
      final recorder = FrameRecorder();
      recorder.addAll([frame(1, 0)], now: 60 * 1000 * 1000);
      recorder.mark('m', now: 10);
      recorder.addAll([frame(2, 5)], now: 60 * 1000 * 1000);
      expect(recorder.between(since: 'm').map((f) => f.number), [2]);
    });
  });

  group('HTTP', () {
    late Directory dir;
    late DevControlServer server;
    late HttpClient client;

    setUp(() async {
      // flutter_test answers every HttpClient request with 400 by default.
      HttpOverrides.global = null;
      dir = await Directory.systemTemp.createTemp('devctl');
      server = await DevControlServer.start(
        control: DevControl(),
        tokenFile: File('${dir.path}/devctl.json'),
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    });

    Future<(int, String)> get(
      String route, {
      String? token,
      String? origin,
    }) async {
      final request = await client.get('127.0.0.1', server.port, route);
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (origin != null) request.headers.set('origin', origin);
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    }

    test('writes its port and a fresh token to the token file', () async {
      final file = jsonDecode(
        await File('${dir.path}/devctl.json').readAsString(),
      );
      expect(file['port'], server.port);
      expect(file['token'], server.token);
      expect(server.token, hasLength(64));
      expect(file['pid'], pid);
    });

    test('refuses requests without the token or from a web page', () async {
      expect((await get('/route')).$1, 401);
      expect((await get('/route', token: 'wrong')).$1, 401);
      expect(
        (await get('/route', token: server.token, origin: 'https://x')).$1,
        403,
      );
      final (status, body) = await get('/route', token: server.token);
      expect(status, 200);
      expect(jsonDecode(body), containsPair('ok', true));
    });

    test('listens on loopback only', () async {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final address in interfaces.expand((i) => i.addresses)) {
        if (address.isLoopback) continue;
        await expectLater(
          Socket.connect(
            address,
            server.port,
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<SocketException>()),
        );
      }
    });
  });
}
