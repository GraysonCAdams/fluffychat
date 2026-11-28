// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/utils/dev_control/finder.dart';
import 'package:fluffychat/utils/dev_control/frame_recorder.dart';
import 'package:fluffychat/utils/dev_control/input_injector.dart';
import 'package:fluffychat/utils/logcat_mirror.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

/// What a request answers: JSON, or the bytes of an image.
class DevControlResponse {
  final int status;
  final Object? json;
  final Uint8List? bytes;
  final String contentType;

  const DevControlResponse.json(this.json, {this.status = 200})
    : bytes = null,
      contentType = 'application/json';

  const DevControlResponse.png(Uint8List this.bytes)
    : status = 200,
      json = null,
      contentType = 'image/png';

  Map<String, Object?> get body => json as Map<String, Object?>;
}

/// The last lines the app logged, with a running sequence number, so a
/// client can ask for what came after the line it saw last.
class LogRecorder {
  final int capacity;
  LogRecorder({this.capacity = 2000});

  final Queue<(int, DateTime, LogEvent)> _lines = Queue();
  int _seq = 0;
  LogCallback? _previous;
  bool _installed = false;

  void start() {
    if (_installed) return;
    _installed = true;
    _previous = Logs().onLog;
    Logs().onLog = (event) {
      _previous?.call(event);
      add(event);
    };
  }

  void add(LogEvent event) {
    _lines.add((++_seq, DateTime.now(), event));
    while (_lines.length > capacity) {
      _lines.removeFirst();
    }
  }

  List<Map<String, Object?>> tail({
    int lines = 100,
    int since = 0,
    Level level = Level.verbose,
  }) {
    final matching = _lines
        .where((l) => l.$1 > since && l.$3.level.index <= level.index)
        .toList();
    return [
      for (final (seq, time, event) in matching.skip(
        math.max(0, matching.length - lines),
      ))
        {
          'seq': seq,
          'time': time.toIso8601String(),
          'level': event.level.name,
          // The scrubbing that keeps tokens out of logcat.
          'text': LogcatMirror.scrub(event.toFormattedString()),
        },
    ];
  }
}

/// The dev control requests (docs/dev-control.md), apart from HTTP so tests
/// can call [handle] directly.
class DevControl {
  /// Opens a route in the app's main router.
  final void Function(String location)? go;

  /// The main router's current location.
  final String? Function()? location;

  final Finder finder = Finder();
  final InputInjector input = InputInjector();
  final FrameRecorder frames = FrameRecorder();
  final LogRecorder logs = LogRecorder();

  /// How long `/frames` waits by default for the engine's next batch of
  /// timings, which comes about once a second.
  Duration framesWait;

  /// Waits for the next frame. A test that cannot pump frames, such as one
  /// inside `runAsync`, swaps it.
  Future<void> Function() nextFrame = InputInjector.nextFrame;

  /// Input requests run one at a time, so two clients cannot interleave
  /// their presses.
  final Lock _inputLock = Lock();

  DevControl({
    this.go,
    this.location,
    this.framesWait = const Duration(milliseconds: 1100),
  });

  bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void start() {
    frames.start();
    logs.start();
  }

  void stop() {
    frames.stop();
    finder.releaseSemantics();
    input.leave();
  }

  /// Answers [method] [route] with [params] (query parameters and a JSON
  /// body, merged).
  Future<DevControlResponse> handle(
    String method,
    String route,
    Map<String, Object?> params,
  ) async {
    try {
      final handler = _routes['$method $route'];
      if (handler == null) {
        return DevControlResponse.json({
          'error': 'No such request: $method $route',
          'requests': _routes.keys.toList(),
        }, status: 404);
      }
      return await handler(params);
    } on ArgumentError catch (e) {
      return DevControlResponse.json({'error': '${e.message}'}, status: 400);
    } on FormatException catch (e) {
      return DevControlResponse.json({'error': e.message}, status: 400);
    } on StateError catch (e) {
      return DevControlResponse.json({'error': e.message}, status: 404);
    } catch (e, s) {
      Logs().w('Dev control request $method $route failed', e, s);
      return DevControlResponse.json({'error': '$e'}, status: 500);
    }
  }

  late final Map<
    String,
    Future<DevControlResponse> Function(Map<String, Object?>)
  >
  _routes = {
    'GET /info': (_) async => _ok(info()),
    'GET /widgets': _widgets,
    'GET /semantics': _semantics,
    'POST /semantics/release': (_) async {
      finder.releaseSemantics();
      return _ok({});
    },
    'POST /wait': _wait,
    'POST /tap': (p) => _pointer(p, 'tap'),
    'POST /longpress': (p) => _pointer(p, 'longpress'),
    'POST /rightclick': (p) => _pointer(p, 'rightclick'),
    'POST /hover': (p) => _pointer(p, 'hover'),
    'POST /scroll': (p) => _pointer(p, 'scroll'),
    'POST /drag': (p) => _pointer(p, 'drag'),
    'POST /type': _type,
    'POST /key': _key,
    'POST /go': _go,
    'GET /route': (_) async => _ok({'location': location?.call()}),
    'GET /screenshot': _screenshot,
    'POST /frames/mark': _mark,
    'GET /frames': _frames,
    'POST /frames/clear': (_) async {
      frames.clear();
      return _ok({});
    },
    'GET /logs': _logs,
  };

  static DevControlResponse _ok(Map<String, Object?> body) =>
      DevControlResponse.json({'ok': true, ...body});

  static int _int(Map<String, Object?> p, String k, int fallback) =>
      p[k] == null ? fallback : num.parse('${p[k]}').round();

  static double _double(Map<String, Object?> p, String k, double fallback) =>
      p[k] == null ? fallback : double.parse('${p[k]}');

  static bool _bool(Map<String, Object?> p, String k) =>
      p[k] == true || p[k] == 'true' || p[k] == '1';

  double get _refreshRate {
    final display = Finder.viewFor(null).flutterView.display;
    final rate = display.refreshRate;
    return rate > 0 ? rate : 60;
  }

  Map<String, Object?> info() => {
    'pid': pid,
    'platform': kIsWeb ? 'web' : Platform.operatingSystem,
    'mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'location': location?.call(),
    'refreshRate': _refreshRate,
    'semantics': finder.semanticsHeld,
    'framesRecorded': frames.frames.length,
    'clockSkewUs': frames.clockSkewUs,
    'views': [
      for (final v in Finder.views)
        {
          'id': v.flutterView.viewId,
          'width': v.size.width,
          'height': v.size.height,
          'devicePixelRatio': v.flutterView.devicePixelRatio,
        },
    ],
  };

  Future<DevControlResponse> _widgets(Map<String, Object?> p) async {
    final spec = TargetSpec.from(p);
    if (!spec.byWidget) {
      throw ArgumentError('Name key, text, textContains or type');
    }
    final found = finder.widgets(spec, limit: _int(p, 'limit', 50));
    return _ok({
      'count': found.length,
      'widgets': [for (final f in found) f.toJson()],
    });
  }

  Future<DevControlResponse> _semantics(Map<String, Object?> p) async {
    await finder.holdSemantics(nextFrame);
    final found = finder.semantics(
      TargetSpec.from(p),
      limit: _int(p, 'limit', 500),
    );
    return _ok({
      'count': found.length,
      'nodes': [for (final f in found) Finder.semanticsJson(f)],
    });
  }

  Future<DevControlResponse> _wait(Map<String, Object?> p) async {
    final spec = TargetSpec.from(p);
    final timeout = Duration(milliseconds: _int(p, 'timeoutMs', 5000));
    final gone = _bool(p, 'gone');
    const poll = Duration(milliseconds: 100);
    // Time is counted in polls rather than read from a clock, so the wait
    // also runs under a test's fake time.
    var waited = Duration.zero;
    while (true) {
      Found? found;
      try {
        found = await finder.resolve(spec, nextFrame);
      } on StateError {
        found = null;
      }
      if (gone ? found == null : found != null) {
        return _ok({
          'waitedMs': waited.inMilliseconds,
          if (found != null) 'target': found.toJson(),
        });
      }
      if (waited >= timeout) {
        throw StateError(
          'Timed out after ${timeout.inMilliseconds} ms waiting for $spec'
          '${gone ? ' to go' : ''}',
        );
      }
      await input.wait(poll);
      waited += poll;
    }
  }

  Future<DevControlResponse> _pointer(Map<String, Object?> p, String action) =>
      _inputLock.synchronized(() async {
        final spec = TargetSpec.from(p);
        if (spec.isEmpty && action == 'hover' && _bool(p, 'leave')) {
          input.leave();
          await nextFrame();
          return _ok({'left': true});
        }
        final target = await finder.resolve(spec, nextFrame);
        final at = target.center;
        final view = target.viewId;
        final kind = pointerKind(p['kind'], desktop: _desktop);
        switch (action) {
          case 'tap':
            await input.tap(
              at,
              viewId: view,
              kind: kind,
              count: _int(p, 'count', 1),
              hold: Duration(milliseconds: _int(p, 'holdMs', 40)),
            );
          case 'longpress':
            await input.tap(
              at,
              viewId: view,
              kind: kind,
              hold: Duration(
                milliseconds: _int(
                  p,
                  'holdMs',
                  kLongPressTimeout.inMilliseconds + 200,
                ),
              ),
            );
          case 'rightclick':
            await input.tap(at, viewId: view, buttons: kSecondaryButton);
          case 'hover':
            input.hover(at, viewId: view);
          case 'scroll':
            await input.scroll(
              at,
              Offset(_double(p, 'dx', 0), _double(p, 'dy', 0)),
              viewId: view,
              steps: _int(p, 'steps', 1),
              interval: Duration(milliseconds: _int(p, 'intervalMs', 16)),
            );
          case 'drag':
            await input.drag(
              at,
              Offset(_double(p, 'dx', 0), _double(p, 'dy', 0)),
              viewId: view,
              kind: p['kind'] == null ? PointerDeviceKind.touch : kind,
              duration: Duration(milliseconds: _int(p, 'durationMs', 300)),
            );
        }
        await nextFrame();
        return _ok({'action': action, 'target': target.toJson()});
      });

  Future<DevControlResponse> _type(Map<String, Object?> p) =>
      _inputLock.synchronized(() async {
        // The text to type is `value`, so `text` stays free to name a field
        // to type into, which is tapped first to focus it.
        final spec = TargetSpec.from(p);
        if (!spec.isEmpty) {
          final target = await finder.resolve(spec, nextFrame);
          await input.tap(target.center, viewId: target.viewId);
          await nextFrame();
        }
        final text = p['value']?.toString() ?? '';
        if (!InputInjector.typeText(text, replace: _bool(p, 'replace'))) {
          throw StateError('No text field has focus');
        }
        if (_bool(p, 'submit')) InputInjector.submit();
        await nextFrame();
        final field = InputInjector.focusedEditable();
        return _ok({'text': field?.textEditingValue.text});
      });

  Future<DevControlResponse> _key(Map<String, Object?> p) =>
      _inputLock.synchronized(() async {
        final raw = p['keys'];
        final combos = raw is List
            ? [for (final k in raw) '$k']
            : '${raw ?? ''}'.split(RegExp(r'\s+')).where((k) => k.isNotEmpty);
        if (combos.isEmpty) throw ArgumentError('Name keys, e.g. "ctrl+k"');
        final handled = <bool>[];
        for (final combo in combos) {
          handled.add(input.pressKeys(combo));
          await nextFrame();
        }
        return _ok({'handled': handled});
      });

  Future<DevControlResponse> _go(Map<String, Object?> p) async {
    final go = this.go;
    if (go == null) throw StateError('This app has no router to drive');
    final roomId = p['roomId']?.toString();
    final to = roomId != null ? '/rooms/$roomId' : p['location']?.toString();
    if (to == null || to.isEmpty) {
      throw ArgumentError('Name location or roomId');
    }
    go(to);
    await nextFrame();
    return _ok({'location': location?.call()});
  }

  Future<DevControlResponse> _screenshot(Map<String, Object?> p) async {
    final spec = TargetSpec.from(p);
    final scale = _double(p, 'scale', 1);
    Rect? crop;
    RenderView view;
    if (spec.isEmpty) {
      view = Finder.viewFor(spec.view);
    } else {
      final target = await finder.resolve(spec, nextFrame);
      view = Finder.viewFor(target.viewId);
      crop = target.rect;
    }
    await nextFrame();
    // The root layer is what the engine composites; reading it outside
    // paint is what flutter_test's captureImage does too.
    // ignore: invalid_use_of_protected_member
    final layer = view.layer;
    if (layer is! OffsetLayer) {
      throw StateError('View ${view.flutterView.viewId} has not painted yet');
    }
    final dpr = view.flutterView.devicePixelRatio;
    final full = Offset.zero & (view.size * dpr);
    final bounds = crop == null
        ? full
        : Rect.fromLTRB(
            crop.left * dpr,
            crop.top * dpr,
            crop.right * dpr,
            crop.bottom * dpr,
          ).intersect(full);
    final image = await layer.toImage(bounds, pixelRatio: scale);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return DevControlResponse.png(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  Future<DevControlResponse> _mark(Map<String, Object?> p) async {
    final name = p['name']?.toString() ?? 'start';
    frames.mark(name);
    return _ok({'mark': name, 'framesRecorded': frames.frames.length});
  }

  Future<DevControlResponse> _frames(Map<String, Object?> p) async {
    final since = p['since']?.toString();
    final until = p['until']?.toString();
    for (final name in [since, until].nonNulls) {
      if (!frames.hasMark(name)) throw StateError('No mark "$name"');
    }
    final wait = _int(p, 'wait', framesWait.inMilliseconds);
    if (wait > 0) await input.wait(Duration(milliseconds: wait));
    final rate = _refreshRate;
    return _ok({
      'since': since,
      'until': until,
      'refreshRate': rate,
      'semantics': finder.semanticsHeld,
      'mode': info()['mode'],
      ...FrameRecorder.summarise(
        frames.between(since: since, until: until),
        budgetMs: 1000 / rate,
        detail: _bool(p, 'detail'),
      ),
    });
  }

  Future<DevControlResponse> _logs(Map<String, Object?> p) async {
    final levelName = p['level']?.toString() ?? 'verbose';
    final level = Level.values.firstWhere(
      (l) => l.name == levelName,
      orElse: () => throw ArgumentError('Unknown level "$levelName"'),
    );
    final lines = logs.tail(
      lines: _int(p, 'lines', 100),
      since: _int(p, 'since', 0),
      level: level,
    );
    return _ok({'lines': lines});
  }
}

/// [DevControl] over HTTP on 127.0.0.1, behind a token.
///
/// Every request carries the token as `Authorization: Bearer <token>`. A
/// request with an `Origin` header (a web page) is refused whatever it
/// carries.
class DevControlServer {
  final DevControl control;
  final HttpServer _server;
  final String token;

  /// Where the port and token were written, for clients to read.
  final File? tokenFile;

  DevControlServer._(this.control, this._server, this.token, this.tokenFile);

  int get port => _server.port;

  /// Listens on [port], or on any free port when that one is taken, and
  /// writes the port and token to [tokenFile].
  static Future<DevControlServer> start({
    required DevControl control,
    int port = 0,
    File? tokenFile,
    String? token,
  }) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    final secret = token ?? _newToken();
    final self = DevControlServer._(control, server, secret, tokenFile);
    control.start();
    server.listen(self._serve);
    if (tokenFile != null) {
      await tokenFile.parent.create(recursive: true);
      await tokenFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'url': 'http://127.0.0.1:${server.port}',
          'port': server.port,
          'token': secret,
          'pid': pid,
          'platform': Platform.operatingSystem,
          'startedAt': DateTime.now().toIso8601String(),
        }),
      );
    }
    return self;
  }

  static String _newToken() {
    final random = math.Random.secure();
    return [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  Future<void> close() async {
    control.stop();
    await _server.close(force: true);
  }

  bool _authorised(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final given = header != null && header.startsWith('Bearer ')
        ? header.substring(7).trim()
        : '';
    if (given.length != token.length) return false;
    var diff = 0;
    for (var i = 0; i < token.length; i++) {
      diff |= given.codeUnitAt(i) ^ token.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      DevControlResponse result;
      if (request.headers.value('origin') != null) {
        result = const DevControlResponse.json({
          'error': 'Requests from web pages are refused',
        }, status: 403);
      } else if (!_authorised(request)) {
        result = const DevControlResponse.json({
          'error': 'Missing or wrong token (Authorization: Bearer <token>)',
        }, status: 401);
      } else {
        final params = <String, Object?>{...request.uri.queryParameters};
        if (request.method == 'POST') {
          final body = await utf8.decodeStream(request);
          if (body.trim().isNotEmpty) {
            final decoded = jsonDecode(body);
            if (decoded is! Map) {
              throw const FormatException('The body must be a JSON object');
            }
            params.addAll(decoded.cast<String, Object?>());
          }
        }
        result = await control.handle(request.method, request.uri.path, params);
      }
      response.statusCode = result.status;
      response.headers.contentType = ContentType.parse(result.contentType);
      if (result.bytes != null) {
        response.add(result.bytes!);
      } else {
        response.write(jsonEncode(result.json));
      }
    } catch (e) {
      response.statusCode = 400;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': '$e'}));
    } finally {
      await response.close();
    }
  }
}

/// Where the running app writes its port and token: `%LOCALAPPDATA%\Seam`
/// on Windows; the app's external files folder on Android, which `adb`
/// can read; the app support folder elsewhere.
Future<File> devControlTokenFile() async {
  const name = 'devctl.json';
  if (Platform.isWindows) {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base != null) return File(path.join(base, 'Seam', name));
  }
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) return File(path.join(external.path, name));
  }
  return File(path.join((await getApplicationSupportDirectory()).path, name));
}

/// Starts the dev control server for the app. Only called when
/// kDevControlEnabled is set (dev_control_flag.dart).
Future<void> startDevControl({
  required int port,
  void Function(String location)? go,
  String? Function()? location,
}) async {
  try {
    final file = await devControlTokenFile();
    final server = await DevControlServer.start(
      control: DevControl(go: go, location: location),
      port: port,
      tokenFile: file,
    );
    Logs().i(
      'Dev control listening on 127.0.0.1:${server.port}, token in ${file.path}',
    );
  } catch (e, s) {
    Logs().e('Dev control did not start', e, s);
  }
}
