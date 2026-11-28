// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Design mockup, not product code: three arrangements of the actions offered
// on a detected address, phone number or date in a message. Renders one
// contact sheet per brightness to build/mockups/data_detectors_v2:
//
//   flutter test test/mockups/data_detectors_v2_test.dart
//
// The app icons are placeholders (a coloured disc with a glyph). At runtime
// Android supplies each action's icon and title through
// TextClassification.getActions().

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _seed = Color(0xFF1A5AD7);
const _frameW = 412.0;
const _frameH = 620.0;
const _gap = 24.0;
final _out = Directory('build/mockups/data_detectors_v2');

/// One action row, chip or tile. [app] set means the action comes from
/// Android and carries an app icon; otherwise it is Seam's own.
class _Action {
  const _Action(this.title, this.icon, {this.app});
  final String title;
  final IconData icon;
  final Color? app;
}

const _maps = Color(0xFF34A853);
const _blue = Color(0xFF1A73E8);
const _red = Color(0xFFEA4335);

class _Case {
  const _Case({
    required this.label,
    required this.sender,
    required this.before,
    required this.span,
    required this.after,
    required this.own,
    required this.kind,
    required this.system,
    required this.seam,
    this.windows = false,
  });
  final String label;
  final String sender;
  final String before;
  final String span;
  final String after;
  final bool own;

  /// The entity type, as the bottom sheet header names it.
  final String kind;
  final List<_Action> system;
  final List<_Action> seam;
  final bool windows;

  List<_Action> get all => [...system, ...seam];
}

const _address = _Case(
  label: 'Address',
  sender: 'Drew Andersen',
  before: 'Come by whenever. ',
  span: '3456 Chelsea Park Lane Apt D, Peachtree Corners GA 30092',
  after: '',
  own: false,
  kind: 'Address',
  system: [_Action('Map', Icons.place, app: _maps)],
  seam: [_Action('Copy', Icons.content_copy_outlined)],
);

const _phone = _Case(
  label: 'Phone number',
  sender: 'Drew Andersen',
  before: 'Works. Call me at ',
  span: '(404) 555-0123',
  after: ' when you are close',
  own: true,
  kind: 'Phone number',
  system: [
    _Action('Call', Icons.call, app: _blue),
    _Action('Add', Icons.person, app: _blue),
    _Action('Message', Icons.chat_bubble, app: _blue),
  ],
  seam: [
    _Action('Message in Seam', Icons.forum_outlined),
    _Action('Copy', Icons.content_copy_outlined),
  ],
);

const _date = _Case(
  label: 'Date and time',
  sender: 'Drew Andersen',
  before: 'Dinner ',
  span: 'Friday at 7pm',
  after: '? Nov 28 works too',
  own: false,
  kind: 'Fri, Nov 28, 7:00 PM',
  system: [
    _Action('View', Icons.event, app: _blue),
    _Action('Schedule', Icons.event, app: _blue),
  ],
  seam: [_Action('Copy', Icons.content_copy_outlined)],
);

const _windowsPhone = _Case(
  label: 'Windows (Seam\'s own actions)',
  sender: 'Drew Andersen',
  before: 'Works. Call me at ',
  span: '(404) 555-0123',
  after: ' when you are close',
  own: true,
  kind: 'Phone number',
  system: [],
  seam: [
    _Action('Call', Icons.call_outlined),
    _Action('Message in Seam', Icons.forum_outlined),
    _Action('Copy', Icons.content_copy_outlined),
  ],
  windows: true,
);

const _cases = [_address, _phone, _date, _windowsPhone];

enum _Variant { menu, sheet, chips }

/// The leading visual of an action: a placeholder app icon for an Android
/// action, a plain glyph for one of Seam's.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon(this.action, {required this.size});
  final _Action action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final app = action.app;
    if (app == null) {
      return Icon(
        action.icon,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: app, shape: BoxShape.circle),
      child: Icon(action.icon, size: size * 0.58, color: Colors.white),
    );
  }
}

/// Variant A. A vertical menu anchored to the span: Android's actions in
/// Android's order, a divider, then Seam's.
class _AnchoredMenu extends StatelessWidget {
  const _AnchoredMenu(this.data);
  final _Case data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menu = theme.popupMenuTheme;
    Widget item(_Action a) => SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _ActionIcon(a, size: 24),
            const SizedBox(width: 12),
            Text(
              a.title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
    return Material(
      color: menu.color,
      elevation: menu.elevation ?? 3,
      shadowColor: theme.colorScheme.shadow,
      surfaceTintColor: Colors.transparent,
      shape: menu.shape,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in data.system) item(a),
                if (data.system.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                for (final a in data.seam) item(a),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Variant B. A modal bottom sheet: the detected text as its headline with
/// copy beside it, then every other action as one row of tonal buttons.
class _ActionSheet extends StatelessWidget {
  const _ActionSheet(this.data);
  final _Case data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = data.all.where((a) => a.title != 'Copy').toList();
    Widget button(_Action a) {
      final label = Text(
        a.title == 'Message in Seam' ? 'Seam' : a.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
      );
      final icon = a.app == null
          ? Icon(a.icon, size: 24, color: scheme.onSecondaryContainer)
          : _ActionIcon(a, size: 24);
      return Material(
        color: scheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          height: actions.length == 1 ? 56 : 72,
          child: actions.length == 1
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [icon, const SizedBox(width: 8), label],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [icon, const SizedBox(height: 6), label],
                ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.span,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.kind,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {},
                  tooltip: 'Copy',
                  icon: const Icon(Icons.content_copy_outlined),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Row(
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: button(a)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Variant C. Assist chips that unfold under the bubble.
class _ChipRow extends StatelessWidget {
  const _ChipRow(this.data);
  final _Case data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      alignment: data.own ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (final a in data.all)
          ActionChip(
            onPressed: () {},
            avatar: a.app == null
                ? Icon(a.icon, size: 18, color: theme.colorScheme.primary)
                : _ActionIcon(a, size: 18),
            label: Text(a.title),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.own, required this.child});
  final bool own;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Material(
          color: own
              ? theme.bubbleColor
              : theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 16,
                height: 1.3,
                color: own ? theme.onBubbleColor : theme.colorScheme.onSurface,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One phone (or window) showing [data] under [variant]. Lays out once to
/// find where the span landed, then hangs the anchored menu under the bubble,
/// lined up with the span.
class _Frame extends StatefulWidget {
  const _Frame({required this.data, required this.variant});
  final _Case data;
  final _Variant variant;

  @override
  State<_Frame> createState() => _FrameState();
}

class _FrameState extends State<_Frame> {
  final _paragraph = GlobalKey();
  final _stack = GlobalKey();
  Rect? _span;
  double _bubbleBottom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final paragraph =
          _paragraph.currentContext!.findRenderObject()! as RenderParagraph;
      final stack = _stack.currentContext!.findRenderObject()! as RenderBox;
      final start = widget.data.before.length;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: start,
          extentOffset: start + widget.data.span.length,
        ),
      );
      var rect = boxes.first.toRect();
      for (final box in boxes.skip(1)) {
        rect = rect.expandToInclude(box.toRect());
      }
      final origin = paragraph.localToGlobal(Offset.zero, ancestor: stack);
      setState(() {
        _span = rect.shift(origin);
        // The bubble's edge: the paragraph plus the bubble's 8dp padding.
        _bubbleBottom = origin.dy + paragraph.size.height + 8;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = widget.data;
    final variant = widget.variant;
    final windows = data.windows;
    // On Windows a modal bottom sheet has no place, so B falls back to A.
    final showMenu =
        variant == _Variant.menu || (variant == _Variant.sheet && windows);
    final showSheet = variant == _Variant.sheet && !windows;
    final textColor = data.own ? theme.onBubbleColor : scheme.onSurface;
    final active = showMenu || variant == _Variant.chips;

    final message = Text.rich(
      key: _paragraph,
      TextSpan(
        children: [
          TextSpan(text: data.before),
          TextSpan(
            text: data.span,
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: textColor,
              backgroundColor: active ? textColor.withAlpha(46) : null,
            ),
          ),
          TextSpan(text: data.after),
        ],
      ),
    );

    final span = _span;
    final menuOnRight = span != null && span.center.dx > _frameW / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(windows ? 8 : 28),
      child: SizedBox(
        width: _frameW,
        height: _frameH,
        child: ColoredBox(
          color: scheme.surface,
          child: Stack(
            key: _stack,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        if (!windows) ...[
                          Icon(Icons.arrow_back, color: scheme.onSurface),
                          const SizedBox(width: 16),
                        ],
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: scheme.tertiaryContainer,
                          child: Text(
                            'D',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          data.sender,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Bubble(
                          own: !data.own,
                          child: Text(
                            data.own
                                ? 'I can meet you out front'
                                : 'Where should I head?',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Bubble(own: data.own, child: message),
                        if (variant == _Variant.chips)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _ChipRow(data),
                          ),
                        const SizedBox(height: 12),
                        _Bubble(
                          own: !data.own,
                          child: Text(data.own ? 'Perfect' : 'On my way'),
                        ),
                        if (data.own) ...[
                          const SizedBox(height: 4),
                          const _Bubble(
                            own: false,
                            child: Text('Leaving in ten'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (showSheet) ...[
                const Positioned.fill(child: ColoredBox(color: Colors.black54)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ActionSheet(data),
                ),
              ],
              if (showMenu && span != null)
                Positioned(
                  top: _bubbleBottom + 4,
                  left: menuOnRight ? null : span.left.clamp(8, _frameW),
                  right: menuOnRight
                      ? (_frameW - span.right).clamp(8, _frameW)
                      : null,
                  child: _AnchoredMenu(data),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _rows = [
  (
    _Variant.menu,
    'A  Anchored menu',
    'Tap the underlined span: a menu opens against it. Android\'s actions '
        'first, in Android\'s order, with each app\'s own icon; Seam\'s below '
        'the divider. Long-press still selects the message.',
  ),
  (
    _Variant.sheet,
    'B  Bottom sheet with an action row',
    'Tap runs the first action at once (Map, Call, View). Long-press the '
        'span opens this modal bottom sheet: the detected text as headline, '
        'copy beside it, every other action as one row of tonal buttons.',
  ),
  (
    _Variant.chips,
    'C  Assist chips under the bubble',
    'Tap the span: a row of assist chips unfolds under the bubble, no '
        'scrim and nothing covered. Tap elsewhere to fold it. Long-press '
        'still selects the message.',
  ),
];

String _caption(_Variant variant, _Case data) => switch ((variant, data)) {
  (_, _Case(windows: true)) when variant == _Variant.sheet =>
    'Windows keeps the anchored menu from A: Material reserves modal '
        'bottom sheets for mobile.',
  (_, _Case(windows: true)) =>
    'Left click or right click on the span. Call shows only when a tel: '
        'handler is registered (Phone Link, Teams).',
  (_Variant.menu, _Case(label: 'Address')) =>
    'One Android action here, so the menu is two items.',
  (_Variant.sheet, _Case(label: 'Address')) =>
    'A lone action becomes one full-width button. No map preview: nothing '
        'local can draw one.',
  (_Variant.chips, _Case(label: 'Address')) =>
    'Two chips sit on one line under the bubble.',
  (_Variant.chips, _Case(label: 'Phone number')) =>
    'Five actions wrap to a second line and push the thread down.',
  (_, _Case(label: 'Date and time')) =>
    'Android offers Schedule only for a time in the future.',
  _ => 'Android returns Call, Add, Message in that order.',
};

class _Sheet extends StatelessWidget {
  const _Sheet(this.brightness);
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF16181D);
    final soft = ink.withAlpha(184);
    return Container(
      width: _cases.length * (_frameW + _gap) + _gap,
      color: dark ? const Color(0xFF2A2B30) : const Color(0xFFE4E6EC),
      child: Padding(
        padding: const EdgeInsets.all(_gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _cases.length * (_frameW + _gap) - _gap,
              color: const Color(0xFFFFD84D),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'TEST RENDER  Data detector actions, three arrangements. '
                'Coloured discs are PLACEHOLDERS for the app icons Android '
                'supplies at runtime (Maps, Phone, Contacts, Messages, '
                'Calendar). Titles and order are AOSP TextClassifier\'s.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            for (final (variant, title, behaviour) in _rows) ...[
              const SizedBox(height: 28),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(behaviour, style: TextStyle(fontSize: 15, color: soft)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, data) in _cases.indexed) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width: _frameW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          MediaQuery(
                            data: const MediaQueryData(
                              size: Size(_frameW, _frameH),
                            ),
                            child: Builder(
                              builder: (context) => Theme(
                                data: FluffyThemes.buildTheme(
                                  context,
                                  brightness,
                                  _seed,
                                ),
                                child: _Frame(data: data, variant: variant),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _caption(variant, data),
                            style: TextStyle(fontSize: 13, color: soft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _out.createSync(recursive: true);
    final sans = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      sans.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    }
    await sans.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '$flutterRoot/bin/cache/artifacts/material_fonts/'
              'MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
  });

  for (final brightness in Brightness.values) {
    testWidgets('data detector arrangements, ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1900, 2700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Tests paint a shadow as a solid outline unless told otherwise; the
      // menu's elevation should look as it does in the app.
      debugDisableShadows = false;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'GoogleSansFlex'),
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: Material(
                type: MaterialType.transparency,
                child: _Sheet(brightness),
              ),
            ),
          ),
        ),
      );
      // The second frame places each anchored menu under its span's bubble.
      await tester.pump();
      expect(find.byType(_AnchoredMenu), findsNWidgets(5));
      expect(find.byType(_ActionSheet), findsNWidgets(3));
      expect(find.byType(ActionChip), findsNWidgets(2 + 5 + 3 + 3));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${_out.path}/sheet_${brightness.name}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      debugDisableShadows = true;
    });
  }
}
