// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, implementation_imports, deprecated_member_use

/// Shared pieces of the parity goldens: the fixtures, the fonts, the device
/// theme, a fake client that answers media and profile requests, and the
/// app shell each screen is pumped into. See README.md in this folder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The folder of this file, for reading fixtures and fonts. `flutter test`
/// runs with the package root as the working directory.
const parityDir = 'test/parity';

/// The own account in every fixture.
const ownUserId = '@robin:home.example.org';
const homeserver = 'home.example.org';

/// What a fixture's `picture: true` becomes: a picture that loads as a
/// flat neutral disc, never a real image.
final flatPicture = Uri.parse('mxc://$homeserver/flat');

/// A 1 x 1 PNG of #353535, served for every media request.
final _flatPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMwNTUFAAFCAKDV2dZLAAAAAElFTkSuQmCC',
);

/// A picture of [width] x [height] pixels for a message's photo, so it
/// keeps the photo's shape: a PNG in the same #353535 as [_flatPng].
Uint8List _solidPng(int width, int height) {
  final rows = BytesBuilder();
  final row = Uint8List(1 + width * 3);
  for (var x = 0; x < width; x++) {
    row.setAll(1 + x * 3, const [0x35, 0x35, 0x35]);
  }
  for (var y = 0; y < height; y++) {
    rows.add(row);
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // truecolour
  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_pngChunk('IHDR', header.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', ZLibCodec().encode(rows.takeBytes())))
    ..add(_pngChunk('IEND', const []));
  return png.takeBytes();
}

Uint8List _pngChunk(String type, List<int> data) {
  final typed = [...ascii.encode(type), ...data];
  final chunk = ByteData(12 + data.length)..setUint32(0, data.length);
  final bytes = chunk.buffer.asUint8List()..setAll(4, typed);
  chunk.setUint32(8 + data.length, _crc32(typed));
  return bytes;
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// One fixture file from `fixtures/`, as the site exports it.
class ParityFixture {
  final String screen;
  final int widthPx;
  final int heightPx;
  final double devicePixelRatio;
  final double statusBar;
  final double navBar;

  /// Bubble colours the device picked, by bridge ID.
  final Map<String, Color> networkColors;

  /// Network names by bridge ID.
  final Map<String, String> networkNames;

  /// `scene.screen`, read by each screen's builder.
  final Map<String, Object?> screenData;

  /// `scene.overlay`: a menu or sheet open over the screen, if any.
  final Map<String, Object?>? overlay;

  ParityFixture._(
    this.screen,
    this.widthPx,
    this.heightPx,
    this.devicePixelRatio,
    this.statusBar,
    this.navBar,
    this.networkColors,
    this.networkNames,
    this.screenData,
    this.overlay,
  );

  static ParityFixture load(String screen) {
    final json =
        jsonDecode(File('$parityDir/fixtures/$screen.json').readAsStringSync())
            as Map<String, Object?>;
    final viewport = json['viewport'] as Map<String, Object?>;
    final scene = json['scene'] as Map<String, Object?>;
    final device = scene['device'] as Map<String, Object?>;
    final networks = json['networks'] as Map<String, Object?>;
    final colors = (device['networkColors'] as Map<String, Object?>?) ?? {};
    return ParityFixture._(
      json['screen'] as String,
      viewport['widthPx'] as int,
      viewport['heightPx'] as int,
      (viewport['devicePixelRatio'] as num).toDouble(),
      (device['statusBar'] as num).toDouble(),
      (device['navBar'] as num).toDouble(),
      {
        for (final MapEntry(:key, :value) in colors.entries)
          key: _hexColor(value as String),
      },
      {
        for (final MapEntry(:key, :value) in networks.entries)
          key: (value as Map<String, Object?>)['name'] as String,
      },
      scene['screen'] as Map<String, Object?>,
      scene['overlay'] as Map<String, Object?>?,
    );
  }

  static Color _hexColor(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// Loads the app's own font, Google Sans Flex (the theme names it for all
/// text; four weights from the app's assets), Roboto Mono Bold (avatar
/// initials) and the Material icons. Without this every glyph renders as a
/// box of the test font.
Future<void> loadParityFonts() async {
  await (FontLoader(
    'RobotoMono',
  )..addFont(_fontFile('RobotoMono-Bold.ttf'))).load();

  // Google Sans Flex is declared in the app's pubspec and the icon font
  // ships with the Flutter SDK; both are in the test asset bundle.
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, Object?>>()) {
    final name = family['family'];
    if (name != appFontFamily && name != 'MaterialIcons') continue;
    final loader = FontLoader(name as String);
    for (final font in (family['fonts'] as List).cast<Map>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// The font family the app's theme sets for all of its text.
const appFontFamily = 'GoogleSansFlex';

Future<ByteData> _fontFile(String name) async =>
    ByteData.sublistView(File('$parityDir/fonts/$name').readAsBytesSync());

/// The reference phone's dynamic colour: Android picked a seed of HCT hue
/// 268.4. The rainbow scheme the app builds reads only the seed's hue.
final Color deviceSeed = Color(Hct.from(268.4, 48, 50).toInt());

/// Settings as on the reference phone, before any widget reads them. The
/// app keeps the store it first opened, so each screen clears that one.
Future<SharedPreferences> setUpParitySettings(ParityFixture fixture) async {
  SharedPreferences.setMockInitialValues({});
  final store = await AppSettings.init(loadWebConfigFile: false);
  await store.clear();
  await AppSettings.checkForUpdates.setItem(false);
  await AppSettings.mergedContactSuggestions.setItem(false);
  await AppSettings.mergedContactsPhoneRegion.setItem('US');
  await AppSettings.sendOnEnter.setItem(false);
  await AppSettings.chatListNetworkBadges.setItem(
    fixture.screenData['badges'] as bool? ?? true,
  );
  await AppSettings.networkBubbleColorOverrides.setItem(
    jsonEncode({
      for (final MapEntry(:key, :value) in fixture.networkColors.entries)
        key: value.toARGB32(),
    }),
  );
  return store;
}

/// A client that looks logged in and synced without a server: media
/// requests get a flat grey picture, the own profile is "Robin" with a
/// picture, and everything else is not found.
class ParityClient extends Client {
  ParityClient(super.clientName, {required super.database})
    : super(httpClient: MockClient(_answer));

  static Future<http.Response> _answer(http.Request request) async {
    final path = request.url.path;
    if (const bool.fromEnvironment('PARITY_LOG')) {
      // ignore: avoid_print
      print('parity http ${request.method} ${request.url}');
    }
    if (path.endsWith('/versions')) {
      return _json({
        'versions': ['v1.11'],
      });
    }
    if (path.contains('/media/')) {
      final demo = RegExp(r'demo-([a-z0-9-]+)').firstMatch(path);
      if (demo != null) {
        return http.Response.bytes(
          File('$parityDir/images/${demo.group(1)}.png').readAsBytesSync(),
          200,
          headers: {'content-type': 'image/png'},
        );
      }
      final size = RegExp(r'flat-(\d+)x(\d+)').firstMatch(path);
      return http.Response.bytes(
        size == null
            ? _flatPng
            : _solidPng(int.parse(size.group(1)!), int.parse(size.group(2)!)),
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    if (path.endsWith('/search') && !path.contains('user_directory')) {
      // The next page is still on its way, as when the phone was captured
      // mid-search.
      if (request.url.queryParameters.containsKey('next_batch')) {
        return Completer<http.Response>().future;
      }
      return _json({
        'search_categories': {
          'room_events': {
            'results': searchHits,
            'count': searchHits.length,
            if (searchStillLoading) 'next_batch': 'more',
            'highlights': <String>[],
          },
        },
      });
    }
    if (path.endsWith('/user_directory/search')) {
      return _json({'results': <Object>[], 'limited': false});
    }
    if (path.endsWith('/publicRooms')) {
      return _json({'chunk': <Object>[], 'total_room_count_estimate': 0});
    }
    if (request.method == 'PUT' && path.contains('/send/')) {
      return _json({'event_id': '\$sent-${path.split('/').last}'});
    }
    if (path.contains('/profile/')) {
      return _json({'displayname': 'Robin', 'avatar_url': '$flatPicture'});
    }
    return _json({'errcode': 'M_NOT_FOUND', 'error': 'parity'}, 404);
  }

  /// What the homeserver's message search answers, as `/search` results.
  static List<Map<String, Object?>> searchHits = [];

  /// Whether the message search is still fetching more when the screen is
  /// captured.
  static bool searchStillLoading = false;

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  @override
  String? get userID => ownUserId;

  @override
  String? get prevBatch => 'synced';

  @override
  bool isLogged() => true;

  @override
  Future<void> setAccountData(
    String userId,
    String type,
    Map<String, Object?> body,
  ) async {
    accountData[type] = BasicEvent(type: type, content: body);
  }

  /// A fresh client with an empty in-memory database.
  static Future<ParityClient> create(String name) async {
    sqfliteFfiInit();
    final client = ParityClient(
      name,
      database: await MatrixSdkDatabase.init(
        name,
        // In the test's own isolate, so database calls finish inside the
        // test's fake time, as a sync from the fake server needs.
        database: await databaseFactoryFfiNoIsolate.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    client.homeserver = Uri.parse('https://$homeserver');
    // Calls that need a login send this; the fake server accepts anything.
    client.bearerToken = 'parity';
    searchHits = [];
    searchStillLoading = false;
    // Looks synced to the chat list header, which otherwise spins.
    client.onSync.add(SyncUpdate(nextBatch: 'synced'));
    return client;
  }
}

/// A room that keeps changes local and opens a timeline of the events
/// given to it, instead of asking a server.
class ParityRoom extends Room {
  ParityRoom({
    required super.id,
    required super.client,
    super.notificationCount,
  });

  /// Oldest first.
  final List<Event> events = [];

  @override
  Future<Timeline> getTimeline({
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function(int insertID)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async => Timeline(
    room: this,
    chunk: TimelineChunk(events: events.reversed.toList()),
    onUpdate: onUpdate,
    onChange: onChange,
    onInsert: onInsert,
    onRemove: onRemove,
    onNewEvent: onNewEvent,
  );

  @override
  Future<void> setReadMarker(
    String? eventId, {
    String? mRead,
    bool? public,
  }) async {}

  @override
  Future<void> postReceipt(
    String eventId, {
    ReceiptType type = ReceiptType.mRead,
  }) async {}

  @override
  Future<void> markUnread(bool unread) async {}

  @override
  Future<void> setTyping(bool isTyping, {int? timeout}) async {}

  @override
  Future<void> leave({bool waitForSync = false}) async {}
}

/// Stands in for the app's Matrix widget with one client.
class ParityMatrix extends MatrixState {
  final Client fakeClient;
  final SharedPreferences prefs;

  ParityMatrix(this.fakeClient, this.prefs);

  @override
  Client get client => fakeClient;

  @override
  SharedPreferences get store => prefs;

  @override
  bool get hasComplexBundles => false;

  @override
  bool get isMultiAccount => false;

  @override
  int getClientIndexByMatrixId(String matrixId) =>
      matrixId == fakeClient.userID ? 0 : -1;

  @override
  void setActiveClient(Client? cl) {}

  @override
  Map<String?, List<Client?>> get accountBundles => {
    null: [fakeClient],
  };

  @override
  List<Client?>? get currentBundle => [fakeClient];
}

final _captureKey = GlobalKey();

/// Method and event channels of the plugins the screens call on Android.
/// Each answers every call with nothing, as when the plugin has no data.
const _androidPluginChannels = [
  'managed_configurations_method',
  'managed_configurations_event',
  'receive_sharing_intent/messages',
  'receive_sharing_intent/events-media',
  'receive_sharing_intent/events-text',
  'im.fluffychat.flutter_shortcuts_new',
  'flutter_callkit_incoming',
  'flutter_callkit_incoming_events',
];

/// Marks how far a screen got, for finding where one hangs.
void parityStep(String step) {
  if (const bool.fromEnvironment('PARITY_LOG')) {
    // ignore: avoid_print
    print('parity step $step');
  }
}

/// Sizes the test view like the fixture's phone: its physical pixels, its
/// density and the system bars as padding.
void setUpParityView(WidgetTester tester, ParityFixture fixture) {
  final view = tester.view;
  view.physicalSize = Size(
    fixture.widthPx.toDouble(),
    fixture.heightPx.toDouble(),
  );
  view.devicePixelRatio = fixture.devicePixelRatio;
  final padding = FakeViewPadding(
    top: fixture.statusBar * fixture.devicePixelRatio,
    bottom: fixture.navBar * fixture.devicePixelRatio,
  );
  view.padding = padding;
  view.viewPadding = padding;
  tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
  // Android has a spell checker, which the composer asks for.
  tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = true;
  // The reference is an Android phone: the app picks its phone layout and
  // reads the 24-hour setting from the system there.
  PlatformInfos.debugOperatingSystem = 'android';
  addTearDown(() => PlatformInfos.debugOperatingSystem = null);
  tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
  tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
  // Pictures start out unloaded on every screen. A picture another screen
  // already loaded is drawn without the fade in, a hair differently at the
  // edges, which would make a golden depend on the screens run before it.
  MxcImage.clearCache('');
  // Plugins the app starts on Android, which have no native side here.
  for (final channel in _androidPluginChannels) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (call) async => null,
    );
  }
  addTearDown(view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// Pumps the app shell (theme, localizations, the Matrix provider) with
/// [routes] and [initialLocation] into the view.
Future<GoRouter> pumpParityApp(
  WidgetTester tester, {
  required Client client,
  required SharedPreferences prefs,
  required List<RouteBase> routes,
  required String initialLocation,
}) async {
  final router = GoRouter(initialLocation: initialLocation, routes: routes);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: Provider<MatrixState>.value(
        value: ParityMatrix(client, prefs),
        child: Builder(
          builder: (context) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.dark,
            theme: FluffyThemes.buildTheme(
              context,
              Brightness.light,
              deviceSeed,
            ),
            darkTheme: FluffyThemes.buildTheme(
              context,
              Brightness.dark,
              deviceSeed,
            ),
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            routerConfig: router,
            // The phone's clock is set to 24 hours. Flutter tests do not
            // pass that setting from the test view to the app.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          ),
        ),
      ),
    ),
  );
  return router;
}

/// Lets pictures load and decode, which needs real async work, then
/// settles the frames.
Future<void> settleParity(WidgetTester tester) async {
  parityStep('settle');
  for (var i = 0; i < 10; i++) {
    parityStep('settle $i');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
  parityStep('precache');
  for (final element in find.byType(Image).evaluate()) {
    final image = element.widget as Image;
    await tester.runAsync(() => precacheImage(image.image, element));
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  parityStep('settled');
}

/// Captures the whole view at the fixture's density, so the PNG has the
/// phone's physical size, and compares it with `goldens/<screen>.png`, or
/// writes that file under `--update-goldens`. Flutter's own golden matcher
/// captures at one pixel per logical pixel, which would not match the
/// phone's capture.
Future<void> expectParityGolden(
  WidgetTester tester,
  ParityFixture fixture,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final golden = Uri.parse('goldens/${fixture.screen}.png');
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: fixture.devicePixelRatio);
    final size = (image.width, image.height);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    final bytes = png.buffer.asUint8List();
    if (autoUpdateGoldenFiles) {
      await goldenFileComparator.update(golden, bytes);
      return (size, true);
    }
    return (size, await goldenFileComparator.compare(bytes, golden));
  });
  final (size, matches) = result!;
  expect(size, (fixture.widthPx, fixture.heightPx));
  expect(matches, isTrue, reason: '${fixture.screen} differs from $golden');
}

/// A crop of the view as straight RGBA bytes, row by row: [regions] in
/// logical pixels, drawn at [pixelRatio] and stacked top to bottom (each
/// as wide as the widest).
typedef RgbaImage = ({int width, int height, Uint8List bytes});

Future<RgbaImage> captureParityRegions(
  WidgetTester tester,
  List<Rect> regions,
  double pixelRatio,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final layer = boundary.debugLayer! as OffsetLayer;
  final parts = <RgbaImage>[];
  for (final region in regions) {
    final part = await tester.runAsync(() async {
      final image = await layer.toImage(region, pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = (
        width: image.width,
        height: image.height,
        bytes: data!.buffer.asUint8List(),
      );
      image.dispose();
      return result;
    });
    parts.add(part!);
  }
  return stackRgba(parts, vertical: true);
}

/// [images] side by side, or one under the other when [vertical], on a
/// transparent background where they differ in size.
RgbaImage stackRgba(List<RgbaImage> images, {required bool vertical}) {
  var width = 0;
  var height = 0;
  for (final image in images) {
    if (vertical) {
      width = image.width > width ? image.width : width;
      height += image.height;
    } else {
      width += image.width;
      height = image.height > height ? image.height : height;
    }
  }
  final bytes = Uint8List(width * height * 4);
  var x0 = 0;
  var y0 = 0;
  for (final image in images) {
    for (var y = 0; y < image.height; y++) {
      bytes.setRange(
        ((y0 + y) * width + x0) * 4,
        ((y0 + y) * width + x0 + image.width) * 4,
        image.bytes,
        y * image.width * 4,
      );
    }
    if (vertical) {
      y0 += image.height;
    } else {
      x0 += image.width;
    }
  }
  return (width: width, height: height, bytes: bytes);
}

/// [image] as a PNG file.
Uint8List encodeRgbaPng(RgbaImage image) {
  final rows = BytesBuilder();
  for (var y = 0; y < image.height; y++) {
    rows.addByte(0); // no filter
    rows.add(
      Uint8List.sublistView(
        image.bytes,
        y * image.width * 4,
        (y + 1) * image.width * 4,
      ),
    );
  }
  final header = ByteData(13)
    ..setUint32(0, image.width)
    ..setUint32(4, image.height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // truecolour with alpha
  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_pngChunk('IHDR', header.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', ZLibCodec().encode(rows.takeBytes())))
    ..add(_pngChunk('IEND', const []));
  return png.takeBytes();
}

/// Adds the bridge's space for [bridgeId], named after the network, the
/// way a bridge sets one up.
Room addNetworkSpace(
  Client client,
  String bridgeId,
  String name,
  List<String> children,
) {
  final space = Room(id: '!space-$bridgeId:$homeserver', client: client);
  void state(String type, Map<String, Object?> content, [String key = '']) =>
      space.setState(
        StrippedStateEvent(
          type: type,
          content: content,
          senderId: '@${bridgeId}bot:$homeserver',
          stateKey: key,
        ),
      );
  state(EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
  state(EventTypes.RoomName, {'name': name});
  for (final child in children) {
    state(EventTypes.SpaceChild, {
      'via': [homeserver],
    }, child);
  }
  client.rooms.add(space);
  return space;
}

/// Sets a state event on [room] as a sync would.
void setRoomState(
  Room room,
  String type,
  Map<String, Object?> content, {
  String stateKey = '',
  String? sender,
}) => room.setState(
  StrippedStateEvent(
    type: type,
    content: content,
    senderId: sender ?? ownUserId,
    stateKey: stateKey,
  ),
);

/// Marks [roomId] as a direct chat with [partner] in the account data.
void markDirect(Client client, String partner, String roomId) {
  final direct = Map<String, Object?>.from(
    client.accountData['m.direct']?.content ?? {},
  );
  direct[partner] = [...?(direct[partner] as List?), roomId];
  client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: direct,
  );
  // Known presence, so avatars do not read it from the database.
  client.presences[partner] = CachedPresence.neverSeen(partner);
}

/// Marks [room] as read up to its last event, as the phone had it.
void markRead(Room room) {
  final last = room.lastEvent;
  if (last == null) return;
  // Read a little after it arrived.
  room.receiptState.global.latestOwnReceipt = LatestReceiptStateData(
    last.eventId,
    last.originServerTs.millisecondsSinceEpoch + 1000,
  );
}

/// A lower-case ID part made from [name].
String slug(String name) {
  final s = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
  return s.isEmpty ? 'x' : s;
}
