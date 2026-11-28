// Renders the welcome page as it is today and the redesign prototypes to
// PNG files under build/mockups/, for review only.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/intro/intro_page.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'splash_variants.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    const dir = 'assets/fonts/google_sans_flex';
    await _font('GoogleSansFlex', [
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        '$dir/GoogleSansFlex-$weight.ttf',
    ]);
    await _font('MaterialIcons', [
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    ]);
  });

  const phone = Size(412, 915);
  const desktop = Size(1280, 800);

  Widget page(String variant, bool agreed, bool wide) => switch (variant) {
    'a' => VariantA(agreed: agreed, wide: wide),
    'b' => VariantB(agreed: agreed, wide: wide),
    'c' => VariantC(agreed: agreed, wide: wide),
    _ => IntroPage(
      isLoading: false,
      loggingInToHomeserver: null,
      hasPresetHomeserver: false,
      welcomeText: null,
      login: () {},
    ),
  };

  for (final variant in ['today', 'a', 'b', 'c']) {
    for (final brightness in Brightness.values) {
      for (final (name, size, agreed) in [
        ('phone', phone, false),
        ('phone_agreed', phone, true),
        ('desktop', desktop, false),
      ]) {
        testWidgets('$variant ${brightness.name} $name', (tester) async {
          debugDisableShadows = false;
          IntroPage.morphed = true;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          final wide = size == desktop;
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: Builder(
                builder: (context) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  theme: FluffyThemes.buildTheme(context, brightness),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: wide
                          ? EdgeInsets.zero
                          : const EdgeInsets.only(top: 28, bottom: 16),
                    ),
                    child: child!,
                  ),
                  home: page(variant, agreed, wide),
                ),
              ),
            ),
          );
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 16));
            if (find.byType(Scaffold).evaluate().isNotEmpty) break;
          }
          if (variant == 'today' && agreed) {
            await tester.tap(find.byKey(const Key('terms_agree_checkbox')));
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: wide ? 1 : 2);
            final data = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/mockups/${variant}_${brightness.name}_$name.png',
            )..createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
          });
          debugDisableShadows = true;
        });
      }
    }
  }
}
