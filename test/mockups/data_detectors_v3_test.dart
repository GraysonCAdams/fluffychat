// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Design mockup, not product code: an anchored menu on a tapped detection
// plus one assist chip under the bubble that offers the most likely action
// without a tap. Writes to build/mockups/data_detectors_v3:
//
//   sheet_dark.png, sheet_light.png   still contact sheets
//   frames_dark, frames_light, frames_windows
//                                     one PNG per 1/30 s of the flow, to be
//                                     joined with ffmpeg
//
//   flutter test test/mockups/data_detectors_v3_test.dart
//
// At runtime Android supplies each action's icon and title through
// TextClassification.getActions(). Here the icons are read from
// build/mockups/icons/<package>.png (not in the repository); an action
// whose file is missing falls back to a Material icon.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart'
    show reactionChipHeight, reactionChipOverlap;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _seed = Color(0xFF1A5AD7);
const _phoneW = 412.0;
const _gap = 24.0;
final _out = Directory('build/mockups/data_detectors_v3');
final _iconDir = Directory('build/mockups/icons');

/// App icons by package name, decoded once before the tests.
final _appIcons = <String, ui.Image>{};

/// One chip or menu item. [package] set means the action comes from Android
/// and carries that app's icon; otherwise it is Seam's own.
class _Action {
  const _Action(this.title, this.glyph, {this.package});
  final String title;
  final IconData glyph;
  final String? package;
}

const _map = _Action(
  'Map',
  Icons.place_outlined,
  package: 'com.google.android.apps.maps',
);
const _call = _Action(
  'Call',
  Icons.call_outlined,
  package: 'com.google.android.dialer',
);
const _add = _Action(
  'Add',
  Icons.person_add_outlined,
  package: 'com.google.android.contacts',
);
const _sms = _Action(
  'Message',
  Icons.sms_outlined,
  package: 'com.google.android.apps.messaging',
);
const _view = _Action(
  'View',
  Icons.event_outlined,
  package: 'com.google.android.calendar',
);
const _inSeam = _Action('Message in Seam', Icons.forum_outlined);
const _copy = _Action('Copy', Icons.content_copy_outlined);
const _seamCall = _Action('Call', Icons.call_outlined);
const _seamMap = _Action('Map', Icons.map_outlined);

/// A stretch of message text; [detected] stretches are underlined.
typedef _Part = (String text, bool detected);

/// The menu of one detection: Android's actions, then Seam's.
typedef _Menu = (List<_Action> system, List<_Action> seam);

class _Msg {
  const _Msg(
    this.parts, {
    this.own = false,
    this.reactions = const [],
    this.chips = const [],
    this.status,
    this.chipBesideReactions = false,
    this.menus = const [],
  });
  final List<_Part> parts;
  final bool own;
  final List<String> reactions;

  /// The actions offered under the bubble without a tap.
  final List<_Action> chips;

  /// The line under everything: read state or time.
  final String? status;

  /// Whether the bubble is wide enough for the chip and the reaction pills
  /// to share the band under it, one at each corner.
  final bool chipBesideReactions;

  /// The menu of each detection, in reading order.
  final List<_Menu> menus;
}

const _addressText = '3456 Chelsea Park Lane Apt D, Peachtree Corners GA 30092';

/// An action's leading visual: the app's icon for an Android action, a
/// Material icon for one of Seam's.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon(this.action, {required this.size, this.color});
  final _Action action;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final image = _appIcons[action.package];
    if (image == null) {
      return Icon(action.glyph, size: size, color: color);
    }
    return ClipOval(
      child: RawImage(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The entries of a detection's menu, built as the app builds its other
/// popup menus: an icon, 12dp, the label.
List<PopupMenuEntry<_Action>> _menuItems(_Menu menu) {
  PopupMenuItem<_Action> item(_Action a) => PopupMenuItem(
    value: a,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(a, size: 24),
        const SizedBox(width: 12),
        Text(a.title),
      ],
    ),
  );
  final (system, seam) = menu;
  return [
    for (final a in system) item(a),
    if (system.isNotEmpty && seam.isNotEmpty) const PopupMenuDivider(),
    for (final a in seam) item(a),
  ];
}

/// The height [showMenu] gives [menu]: 8dp above and below, 48dp an item,
/// 16dp for the divider.
double _menuHeight(_Menu menu) {
  final (system, seam) = menu;
  final divider = system.isNotEmpty && seam.isNotEmpty ? 16.0 : 0.0;
  return 16 + 48.0 * (system.length + seam.length) + divider;
}

/// The assist chips under a bubble, 8dp apart.
class _Chips extends StatelessWidget {
  const _Chips(this.actions);
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          ActionChip(
            onPressed: () {},
            // The 48dp target reaches past the 32dp container; shrunk here
            // so the picture shows the container's true spacing.
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            avatar: _ActionIcon(a, size: 18, color: theme.colorScheme.primary),
            label: Text(a.title),
          ),
        ],
      ],
    );
  }
}

/// Reaction pills drawn to the measurements of the app's own: ringed in the
/// page colour and overlapping the bubble.
class _Reactions extends StatelessWidget {
  const _Reactions(this.keys);
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, key) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            height: reactionChipHeight,
            constraints: const BoxConstraints(minWidth: reactionChipHeight),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: scheme.surfaceContainerHighest,
              shape: StadiumBorder(
                side: BorderSide(color: scheme.surface, width: 2),
              ),
            ),
            child: Text(
              key,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface,
                fontFamilyFallback: const ['Emoji'],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A bubble with everything that hangs under it.
class _Message extends StatefulWidget {
  const _Message(
    this.msg, {
    this.paragraphKey,
    this.pressed,
    this.showChips = true,
    this.onDetectionTap,
    super.key,
  });
  final _Msg msg;
  final Key? paragraphKey;

  /// The detection that shows as pressed, its menu open.
  final int? pressed;

  /// Whether the chips are out; they fold away when this turns off.
  final bool showChips;
  final ValueChanged<int>? onDetectionTap;

  @override
  State<_Message> createState() => _MessageState();
}

class _MessageState extends State<_Message> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final msg = widget.msg;
    final own = msg.own;
    final textColor = own ? theme.onBubbleColor : scheme.onSurface;
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    var detection = 0;
    final spans = <TextSpan>[];
    for (final (text, detected) in msg.parts) {
      if (!detected) {
        spans.add(TextSpan(text: text));
        continue;
      }
      final index = detection++;
      final onTap = widget.onDetectionTap;
      TapGestureRecognizer? recognizer;
      if (onTap != null) {
        recognizer = TapGestureRecognizer()..onTap = () => onTap(index);
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: text,
          recognizer: recognizer,
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: textColor,
            backgroundColor: widget.pressed == index
                ? textColor.withAlpha(46)
                : null,
          ),
        ),
      );
    }
    final bubble = Material(
      color: own ? theme.bubbleColor : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text.rich(
          key: widget.paragraphKey,
          TextSpan(children: spans),
          style: TextStyle(
            fontSize: AppConfig.messageFontSize,
            color: textColor,
          ),
        ),
      ),
    );

    final hasReactions = msg.reactions.isNotEmpty;
    final beside = hasReactions && msg.chipBesideReactions;
    // Reaction pills hang below the bubble by their height less the
    // overlap. A chip sharing their band starts 4dp under the bubble and is
    // 32dp tall.
    const hang = reactionChipHeight - reactionChipOverlap;
    final band = !hasReactions ? 0.0 : (beside ? 36.0 : hang);
    final chips = msg.chips.isEmpty ? null : _Chips(msg.chips);

    return Column(
      crossAxisAlignment: own
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: band),
              child: bubble,
            ),
            if (hasReactions)
              Positioned(
                bottom: band - hang,
                left: own ? 0 : null,
                right: own ? null : 0,
                child: _Reactions(msg.reactions),
              ),
            if (beside && chips != null)
              Positioned(
                bottom: 0,
                left: own ? null : 0,
                right: own ? 0 : null,
                child: chips,
              ),
          ],
        ),
        if (!beside && chips != null)
          AnimatedSize(
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            alignment: own ? Alignment.topRight : Alignment.topLeft,
            child: widget.showChips
                ? Padding(padding: const EdgeInsets.only(top: 4), child: chips)
                : const SizedBox.shrink(),
          ),
        if (msg.status != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
            child: Text(
              msg.status!,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// The messages of a chat, newest at the bottom, in the timeline's own
/// metrics: 8dp at the sides, 16dp between senders, bubbles that leave an
/// avatar's width free on the far side.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.children, required this.own});
  final List<Widget> children;
  final List<bool> own;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.maxTimelineWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed)
                Align(
                  alignment: own[i]
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        FluffyThemes.columnWidth * 1.5,
                        constraints.maxWidth - 44,
                      ),
                    ),
                    child: child,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The bar over a chat: back on a phone, then the contact.
PreferredSizeWidget _appBar(BuildContext context, {required bool windows}) {
  final scheme = Theme.of(context).colorScheme;
  return AppBar(
    automaticallyImplyLeading: false,
    leading: windows
        ? null
        : IconButton(onPressed: () {}, icon: const Icon(Icons.arrow_back)),
    titleSpacing: windows ? 16 : 0,
    title: Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: scheme.tertiaryContainer,
          child: Text(
            'D',
            style: TextStyle(fontSize: 14, color: scheme.onTertiaryContainer),
          ),
        ),
        const SizedBox(width: 12),
        const Text('Drew Andersen', style: TextStyle(fontSize: 16)),
      ],
    ),
  );
}

/// Where a detection sits, in the coordinates of [ancestor]: the box around
/// its text and the bubble's top and bottom edges.
(Rect span, double bubbleTop, double bubbleBottom) _locate(
  GlobalKey paragraphKey,
  List<_Part> parts,
  int detection,
  RenderObject? ancestor,
) {
  final paragraph =
      paragraphKey.currentContext!.findRenderObject()! as RenderParagraph;
  var start = 0;
  var length = 0;
  var seen = 0;
  for (final (text, detected) in parts) {
    if (detected && seen++ == detection) {
      length = text.length;
      break;
    }
    start += text.length;
  }
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + length),
  );
  var rect = boxes.first.toRect();
  for (final box in boxes.skip(1)) {
    rect = rect.expandToInclude(box.toRect());
  }
  final origin = paragraph.localToGlobal(Offset.zero, ancestor: ancestor);
  // The bubble pads its text by 8dp above and below.
  return (
    rect.shift(origin),
    origin.dy - 8,
    origin.dy + paragraph.size.height + 8,
  );
}

/// Where the menu of a detection goes in a space [size]: under the bubble
/// and lined up with the span, or over the bubble when there is no room
/// underneath.
RelativeRect _menuPosition(
  (Rect, double, double) place,
  _Menu menu,
  Size size,
) {
  final (span, bubbleTop, bubbleBottom) = place;
  final height = _menuHeight(menu);
  final below = bubbleBottom + 4;
  final top = below + height <= size.height - 8
      ? below
      : bubbleTop - 4 - height;
  // A left edge past the right one hangs the menu from its right edge.
  final alignRight = span.center.dx > size.width / 2;
  final x = alignRight ? span.right : span.left;
  return RelativeRect.fromLTRB(
    alignRight ? size.width : x,
    top,
    alignRight ? size.width - x : size.width - x,
    0,
  );
}

// ---------------------------------------------------------------------------
// The animated flow.

/// The pointer drawn over the recording: a fingertip on a phone, an arrow
/// on Windows.
typedef _Pointer = ({Offset at, bool down});

class _PointerPainter extends CustomPainter {
  _PointerPainter(this.pointer, {required this.mouse, required this.ink})
    : super(repaint: pointer);
  final ValueNotifier<_Pointer?> pointer;
  final bool mouse;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final value = pointer.value;
    if (value == null) return;
    if (!mouse) {
      final radius = value.down ? 16.0 : 20.0;
      canvas
        ..drawCircle(
          value.at,
          radius,
          Paint()..color = ink.withAlpha(value.down ? 90 : 50),
        )
        ..drawCircle(
          value.at,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = ink.withAlpha(150),
        );
      return;
    }
    final arrow = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 17)
      ..lineTo(4.5, 13)
      ..lineTo(7.5, 20)
      ..lineTo(10, 19)
      ..lineTo(7, 12)
      ..lineTo(12.5, 12)
      ..close();
    canvas
      ..save()
      ..translate(value.at.dx, value.at.dy)
      ..drawPath(arrow, Paint()..color = Colors.white)
      ..drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_PointerPainter old) => false;
}

/// A message arriving as the app's own do: it grows from nothing over
/// [FluffyThemes.animationDuration].
class _Arrive extends StatefulWidget {
  const _Arrive({required this.animate, required this.child, super.key});
  final bool animate;
  final Widget child;

  @override
  State<_Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<_Arrive> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    if (!_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = true);
      });
    }
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: _shown ? widget.child : const SizedBox.shrink(),
    );
  }
}

/// A chat whose messages arrive one by one. Tapping a detection opens its
/// menu with [showMenu]; only the newest message with chips shows them.
class _Chat extends StatefulWidget {
  const _Chat({required this.messages, required this.windows, super.key});
  final List<_Msg> messages;
  final bool windows;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  static const _initial = 2;
  int _count = _initial;
  (int message, int detection)? _pressed;
  late final _paragraphs = [
    for (final _ in widget.messages) GlobalKey(debugLabel: 'paragraph'),
  ];

  void showNext() => setState(() => _count++);

  /// Where a detection is on screen.
  Rect detectionRect(int message, int detection) => _locate(
    _paragraphs[message],
    widget.messages[message].parts,
    detection,
    null,
  ).$1;

  Future<void> _openMenu(int message, int detection) async {
    final menu = widget.messages[message].menus[detection];
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final place = _locate(
      _paragraphs[message],
      widget.messages[message].parts,
      detection,
      overlay,
    );
    setState(() => _pressed = (message, detection));
    await showMenu<_Action>(
      context: context,
      position: _menuPosition(place, menu, overlay.size),
      items: _menuItems(menu),
    );
    if (mounted) setState(() => _pressed = null);
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.messages.sublist(0, _count);
    final newestWithChips = shown.lastIndexWhere((m) => m.chips.isNotEmpty);
    return Scaffold(
      appBar: _appBar(context, windows: widget.windows),
      body: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: _Timeline(
          own: [for (final msg in shown) msg.own],
          children: [
            for (final (i, msg) in shown.indexed)
              _Arrive(
                key: ValueKey(i),
                animate: i >= _initial,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _Message(
                    msg,
                    paragraphKey: _paragraphs[i],
                    pressed: _pressed?.$1 == i ? _pressed?.$2 : null,
                    showChips: i == newestWithChips,
                    onDetectionTap: msg.menus.isEmpty
                        ? null
                        : (detection) => _openMenu(i, detection),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<_Msg> _flow({required bool windows}) => [
  const _Msg([('Almost there?', false)]),
  const _Msg([('Ten minutes out', false)], own: true),
  _Msg(
    const [
      ('Works. Call me at ', false),
      ('(404) 555-0123', true),
      (' when you are close', false),
    ],
    chips: [windows ? _seamCall : _call],
    menus: [
      windows
          ? (const [], const [_seamCall, _inSeam, _copy])
          : (const [_call, _add, _sms], const [_inSeam, _copy]),
    ],
  ),
  const _Msg([('Leaving now', false)], own: true),
  _Msg(
    const [
      ('Come to ', false),
      (_addressText, true),
      (' and ring ', false),
      ('(404) 555-0199', true),
      (' at the gate', false),
    ],
    chips: windows ? const [_seamMap, _seamCall] : const [_map, _call],
    menus: windows
        ? const [
            (<_Action>[], [_seamMap, _copy]),
            (<_Action>[], [_seamCall, _inSeam, _copy]),
          ]
        : const [
            ([_map], [_copy]),
            ([_call, _add, _sms], [_inSeam, _copy]),
          ],
  ),
];

// ---------------------------------------------------------------------------
// The still sheet.

class _Scene {
  const _Scene({
    required this.label,
    required this.caption,
    required this.messages,
    this.menuOpen = false,
    this.width = _phoneW,
    this.windows = false,
  });
  final String label;
  final String caption;
  final List<_Msg> messages;

  /// Whether the menu of the last message's first detection is open.
  final bool menuOpen;
  final double width;
  final bool windows;
}

const _phoneMenu = ([_call, _add, _sms], [_inSeam, _copy]);

const _scenes = [
  _Scene(
    label: 'Incoming',
    caption:
        'The chip hangs 4dp under the bubble on the bubble\'s own side. Only '
        'the newest message with a detection gets one: the phone number '
        'further up stays underlined, with its menu a tap away.',
    messages: [
      _Msg([('My new number is ', false), ('(404) 555-0188', true)]),
      _Msg([('Got it', false)], own: true),
      _Msg(
        [('Come by whenever. ', false), (_addressText, true)],
        chips: [_map],
      ),
    ],
  ),
  _Scene(
    label: 'Outgoing',
    caption:
        'Mirrored for the user\'s own bubble. The status line (read state, '
        'time, edited) keeps its place as the last line, under the chip.',
    messages: [
      _Msg([('I can meet you out front', false)]),
      _Msg(
        [
          ('Works. Call me at ', false),
          ('(404) 555-0123', true),
          (' when you are close', false),
        ],
        own: true,
        chips: [_call],
        status: 'Read 1:33 PM',
      ),
    ],
  ),
  _Scene(
    label: 'With reactions, wide bubble',
    caption:
        'Reaction pills hang off the far corner (right for incoming, left '
        'for outgoing), so on a bubble wide enough for both the chip takes '
        'the near corner of the same band.',
    messages: [
      _Msg([('Where should I head?', false)], own: true),
      _Msg(
        [('Come by whenever. ', false), (_addressText, true)],
        reactions: ['❤️ 2', '👍'],
        chips: [_map],
        chipBesideReactions: true,
      ),
    ],
  ),
  _Scene(
    label: 'With reactions, narrow bubble',
    caption:
        'When the two would touch, the chip drops to its own line under the '
        'pills. Order, top to bottom: bubble, reactions, chip, status line.',
    messages: [
      _Msg([('What time works?', false)]),
      _Msg(
        [('Friday at 7pm', true)],
        own: true,
        reactions: ['👍', '🎉 2'],
        chips: [_view],
        status: 'Read 1:33 PM',
      ),
    ],
  ),
  _Scene(
    label: 'Two detections in one message',
    caption:
        'One chip per detection, in reading order, capped at two. A third '
        'detection stays underlined only.',
    messages: [
      _Msg([('Where should I head?', false)], own: true),
      _Msg(
        [
          ('Come to ', false),
          (_addressText, true),
          (' and ring ', false),
          ('(404) 555-0123', true),
          (' at the gate', false),
        ],
        chips: [_map, _call],
      ),
    ],
  ),
  _Scene(
    label: 'Tap the underlined number',
    caption:
        'Tapping the chip runs its action. Tapping the span still opens the '
        'full anchored menu, over the chip, with the chip\'s action first.',
    messages: [
      _Msg([('I can meet you out front', false)]),
      _Msg(
        [
          ('Works. Call me at ', false),
          ('(404) 555-0123', true),
          (' when you are close', false),
        ],
        own: true,
        chips: [_call],
        status: 'Read 1:33 PM',
        menus: [_phoneMenu],
      ),
    ],
    menuOpen: true,
  ),
  _Scene(
    label: 'Windows',
    caption:
        'Same placement at desktop width. The chip is Seam\'s first action '
        'for the type, with a Material icon since no app supplies one. Left '
        'or right click on the span opens Seam\'s menu.',
    messages: [
      _Msg([('I can meet you out front', false)]),
      _Msg(
        [
          ('Works. Call me at ', false),
          ('(404) 555-0123', true),
          (' when you are close', false),
        ],
        own: true,
        chips: [_seamCall],
        status: 'Read 1:33 PM',
      ),
    ],
    width: 2 * _phoneW + _gap,
    windows: true,
  ),
];

const _sceneH = 500.0;

/// One phone or window showing [scene]. Lays out once to find where the
/// last message's first detection landed, then draws its menu there.
class _Frame extends StatefulWidget {
  const _Frame(this.scene);
  final _Scene scene;

  @override
  State<_Frame> createState() => _FrameState();
}

class _FrameState extends State<_Frame> {
  final _paragraph = GlobalKey();
  final _stack = GlobalKey();
  (Rect, double, double)? _place;

  @override
  void initState() {
    super.initState();
    if (!widget.scene.menuOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _place = _locate(
          _paragraph,
          widget.scene.messages.last.parts,
          0,
          _stack.currentContext!.findRenderObject(),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scene = widget.scene;
    final place = _place;
    final last = scene.messages.length - 1;
    final size = Size(scene.width, _sceneH);

    Widget? menu;
    if (place != null) {
      final entries = scene.messages.last.menus.first;
      final position = _menuPosition(place, entries, size);
      final popup = theme.popupMenuTheme;
      menu = Positioned(
        top: position.top,
        left: position.left > position.right ? null : position.left,
        right: position.left > position.right ? position.right : null,
        child: Material(
          color: popup.color,
          elevation: popup.elevation ?? 3,
          shadowColor: theme.colorScheme.shadow,
          surfaceTintColor: Colors.transparent,
          shape: popup.shape,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
            child: IntrinsicWidth(
              // Menu items announce themselves as part of a menu, which
              // this still picture of one is not.
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _menuItems(entries),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(scene.windows ? 8 : 28),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          key: _stack,
          children: [
            Scaffold(
              appBar: _appBar(context, windows: scene.windows),
              body: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _Timeline(
                  own: [for (final msg in scene.messages) msg.own],
                  children: [
                    for (final (i, msg) in scene.messages.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _Message(
                          msg,
                          paragraphKey: i == last ? _paragraph : null,
                          pressed: scene.menuOpen && i == last ? 0 : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ?menu,
          ],
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet(this.brightness);
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF16181D);
    final soft = ink.withAlpha(184);
    Widget cell(_Scene scene) => SizedBox(
      width: scene.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scene.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          MediaQuery(
            data: MediaQueryData(size: Size(scene.width, _sceneH)),
            child: Builder(
              builder: (context) => Theme(
                data: FluffyThemes.buildTheme(context, brightness, _seed),
                child: _Frame(scene),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(scene.caption, style: TextStyle(fontSize: 13, color: soft)),
        ],
      ),
    );
    Widget row(List<_Scene> scenes) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, scene) in scenes.indexed) ...[
          if (i > 0) const SizedBox(width: _gap),
          cell(scene),
        ],
      ],
    );
    return Container(
      width: 4 * (_phoneW + _gap) + _gap,
      color: dark ? const Color(0xFF2A2B30) : const Color(0xFFE4E6EC),
      padding: const EdgeInsets.all(_gap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFFFD84D),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text(
              'TEST RENDER  Anchored menu plus one auto-shown assist chip. '
              'App icons are the apps\' store icons, standing in for the '
              'ones Android supplies with each TextClassifier action. The '
              'chip is the first of those actions.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 28),
          row(_scenes.sublist(0, 4)),
          const SizedBox(height: 32),
          row(_scenes.sublist(4)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
    // Reaction emoji need a colour emoji font; the test engine has none of
    // its own. Windows ships one.
    final emoji = File(r'C:\Windows\Fonts\seguiemj.ttf');
    if (emoji.existsSync()) {
      final loader = FontLoader('Emoji')
        ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync())));
      await loader.load();
    }
    if (_iconDir.existsSync()) {
      for (final file in _iconDir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.endsWith('.png')) continue;
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        _appIcons[name.substring(0, name.length - 4)] = frame.image;
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('still sheet, ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1900, 1500);
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
      // The second frame draws the open menu against its span.
      await tester.pump();
      expect(find.byType(PopupMenuItem<_Action>), findsNWidgets(5));
      expect(find.byType(ActionChip), findsNWidgets(8));

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

  for (final (name, brightness, size, windows) in const [
    ('dark', Brightness.dark, Size(_phoneW, 660), false),
    ('light', Brightness.light, Size(_phoneW, 660), false),
    ('windows', Brightness.dark, Size(720, 560), true),
  ]) {
    testWidgets('animated flow, $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      if (windows) debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final frames = Directory('${_out.path}/frames_$name');
      if (frames.existsSync()) frames.deleteSync(recursive: true);
      frames.createSync(recursive: true);

      final boundaryKey = GlobalKey();
      final chatKey = GlobalKey<_ChatState>();
      final pointer = ValueNotifier<_Pointer?>(null);
      final messages = _flow(windows: windows);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: FluffyThemes.buildTheme(context, brightness, _seed),
              builder: (context, child) => Stack(
                children: [
                  child!,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _PointerPainter(
                          pointer,
                          mouse: windows,
                          ink: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              home: _Chat(key: chatKey, messages: messages, windows: windows),
            ),
          ),
        ),
      );

      var index = 0;
      const step = Duration(microseconds: 33333);
      Future<void> record(double seconds) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        for (var i = 0; i < (seconds * 30).round(); i++) {
          await tester.pump(step);
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              '${frames.path}/f${(index++).toString().padLeft(4, '0')}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }

      final mouse = windows
          ? await tester.createGesture(kind: PointerDeviceKind.mouse)
          : null;
      var cursor = Offset(size.width * 0.5, size.height * 0.45);
      if (mouse != null) {
        await mouse.addPointer(location: cursor);
        pointer.value = (at: cursor, down: false);
      }

      /// Brings the pointer to [target]: the arrow glides, the fingertip
      /// appears.
      Future<void> approach(Offset target) async {
        if (mouse == null) {
          pointer.value = (at: target, down: false);
          await record(0.2);
          return;
        }
        final from = cursor;
        const steps = 14;
        for (var i = 1; i <= steps; i++) {
          final t = Curves.easeInOut.transform(i / steps);
          cursor = Offset.lerp(from, target, t)!;
          await mouse.moveTo(cursor);
          pointer.value = (at: cursor, down: false);
          await record(1 / 30);
        }
        await record(0.3);
      }

      /// Presses at [target] for [hold] seconds and lets go.
      Future<void> press(Offset target, {double hold = 0.1}) async {
        await approach(target);
        final gesture = mouse ?? await tester.createGesture();
        await gesture.down(target);
        pointer.value = (at: target, down: true);
        await record(hold);
        await gesture.up();
        pointer.value = mouse == null ? null : (at: target, down: false);
      }

      // 1. The message arrives, underlined, with its chip.
      await record(0.8);
      chatKey.currentState!.showNext();
      await record(1.6);
      expect(find.byType(ActionChip), findsOneWidget);

      // 2. A tap on the span opens the anchored menu.
      await press(chatKey.currentState!.detectionRect(2, 0).center);
      await record(2.2);
      expect(find.byType(PopupMenuItem<_Action>), findsWidgets);

      // 3. A tap outside dismisses it.
      await press(Offset(size.width * 0.5, 120));
      await record(1.0);
      expect(find.byType(PopupMenuItem<_Action>), findsNothing);

      // 4. A tap on the chip: pressed state and ripple.
      await press(tester.getCenter(find.byType(ActionChip)), hold: 0.4);
      await record(1.2);

      // 5. A reply, then a message with two detections: two chips, and the
      // older message's chip folds away.
      if (mouse != null) await approach(Offset(size.width * 0.5, 150));
      chatKey.currentState!.showNext();
      await record(1.0);
      chatKey.currentState!.showNext();
      await record(3.0);
      expect(find.byType(ActionChip), findsNWidgets(2));

      if (mouse != null) await mouse.removePointer();
      debugDisableShadows = true;
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
