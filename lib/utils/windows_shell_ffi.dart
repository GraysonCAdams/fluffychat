// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Title bar colours and the taskbar unread badge, set through Win32 over FFI
/// so that the runner in `windows/` can stay a stock Flutter template.
abstract final class WindowsShell {
  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _gdi32 = DynamicLibrary.open('gdi32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _ole32 = DynamicLibrary.open('ole32.dll');
  static final _dwmapi = DynamicLibrary.open('dwmapi.dll');

  static final _findWindowEx = _user32
      .lookupFunction<
        Pointer Function(Pointer, Pointer, Pointer<Utf16>, Pointer<Utf16>),
        Pointer Function(Pointer, Pointer, Pointer<Utf16>, Pointer<Utf16>)
      >('FindWindowExW');
  static final _getWindowThreadProcessId = _user32
      .lookupFunction<
        Uint32 Function(Pointer, Pointer<Uint32>),
        int Function(Pointer, Pointer<Uint32>)
      >('GetWindowThreadProcessId');
  static final _getCurrentProcessId = _kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
  static final _dwmSetWindowAttribute = _dwmapi
      .lookupFunction<
        Int32 Function(Pointer, Uint32, Pointer, Uint32),
        int Function(Pointer, int, Pointer, int)
      >('DwmSetWindowAttribute');
  static final _coInitializeEx = _ole32
      .lookupFunction<
        Int32 Function(Pointer, Uint32),
        int Function(Pointer, int)
      >('CoInitializeEx');
  static final _coCreateInstance = _ole32
      .lookupFunction<
        Int32 Function(
          Pointer<_Guid>,
          Pointer,
          Uint32,
          Pointer<_Guid>,
          Pointer<Pointer>,
        ),
        int Function(
          Pointer<_Guid>,
          Pointer,
          int,
          Pointer<_Guid>,
          Pointer<Pointer>,
        )
      >('CoCreateInstance');
  static final _createDibSection = _gdi32
      .lookupFunction<
        Pointer Function(
          Pointer,
          Pointer<_BitmapInfoHeader>,
          Uint32,
          Pointer<Pointer>,
          Pointer,
          Uint32,
        ),
        Pointer Function(
          Pointer,
          Pointer<_BitmapInfoHeader>,
          int,
          Pointer<Pointer>,
          Pointer,
          int,
        )
      >('CreateDIBSection');
  static final _createBitmap = _gdi32
      .lookupFunction<
        Pointer Function(Int32, Int32, Uint32, Uint32, Pointer),
        Pointer Function(int, int, int, int, Pointer)
      >('CreateBitmap');
  static final _deleteObject = _gdi32
      .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
        'DeleteObject',
      );
  static final _createIconIndirect = _user32
      .lookupFunction<
        Pointer Function(Pointer<_IconInfo>),
        Pointer Function(Pointer<_IconInfo>)
      >('CreateIconIndirect');
  static final _destroyIcon = _user32
      .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
        'DestroyIcon',
      );

  static const _dwmwaUseImmersiveDarkMode = 20;
  static const _dwmwaCaptionColor = 35;
  static const _dwmwaTextColor = 36;

  // Slot numbers in the ITaskbarList3 vtable (IUnknown takes 0 to 2).
  static const _vtHrInit = 3;
  static const _vtSetOverlayIcon = 18;

  static const _badgeSize = 32;

  static Pointer? _hwnd;
  static Pointer<Pointer<IntPtr>>? _taskbar;
  static Pointer? _overlayIcon;
  static String? _lastCaption;
  static String? _lastBadge;

  static Pointer get _window {
    final cached = _hwnd;
    if (cached != null && cached.address != 0) return cached;
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final pid = calloc<Uint32>();
    final ownPid = _getCurrentProcessId();
    var hwnd = Pointer.fromAddress(0);
    try {
      while (true) {
        hwnd = _findWindowEx(nullptr, hwnd, className, nullptr);
        if (hwnd.address == 0) break;
        _getWindowThreadProcessId(hwnd, pid);
        if (pid.value == ownPid) break;
      }
    } finally {
      calloc.free(className);
      calloc.free(pid);
    }
    return _hwnd = hwnd;
  }

  /// Matches the native caption to the app's top surface. The caption colour
  /// takes effect on Windows 11; Windows 10 only honours the dark mode flag.
  static void setTitleBarColors({
    required Brightness brightness,
    required Color caption,
    required Color text,
  }) {
    final key = '$brightness ${caption.toARGB32()} ${text.toARGB32()}';
    if (key == _lastCaption) return;
    final hwnd = _window;
    if (hwnd.address == 0) return;
    _lastCaption = key;

    final value = calloc<Uint32>();
    try {
      value.value = brightness == Brightness.dark ? 1 : 0;
      _dwmSetWindowAttribute(hwnd, _dwmwaUseImmersiveDarkMode, value, 4);
      value.value = _colorRef(caption);
      _dwmSetWindowAttribute(hwnd, _dwmwaCaptionColor, value, 4);
      value.value = _colorRef(text);
      _dwmSetWindowAttribute(hwnd, _dwmwaTextColor, value, 4);
    } finally {
      calloc.free(value);
    }
  }

  /// Shows [count] as an overlay badge on the taskbar button, or clears it
  /// when [count] is zero.
  static Future<void> setTaskbarBadge(
    int count, {
    required Color background,
    required Color foreground,
  }) async {
    final label = count <= 0 ? '' : (count > 99 ? '99+' : '$count');
    final key = '$label ${background.toARGB32()} ${foreground.toARGB32()}';
    if (key == _lastBadge) return;
    _lastBadge = key;

    final taskbar = _taskbarList;
    final hwnd = _window;
    if (taskbar == null || hwnd.address == 0) return;

    final icon = label.isEmpty
        ? nullptr
        : await _badgeIcon(label, background, foreground);

    final description = label.toNativeUtf16();
    try {
      final setOverlayIcon = _vtable(taskbar, _vtSetOverlayIcon)
          .cast<
            NativeFunction<
              Int32 Function(Pointer, Pointer, Pointer, Pointer<Utf16>)
            >
          >()
          .asFunction<
            int Function(Pointer, Pointer, Pointer, Pointer<Utf16>)
          >();
      setOverlayIcon(taskbar, hwnd, icon, description);
    } finally {
      calloc.free(description);
    }

    final previous = _overlayIcon;
    if (previous != null) _destroyIcon(previous);
    _overlayIcon = icon.address == 0 ? null : icon;
  }

  static Pointer<Pointer<IntPtr>>? get _taskbarList {
    final cached = _taskbar;
    if (cached != null) return cached;

    // The runner initialises COM on the platform thread already; this covers
    // the case where Dart runs on a separate UI thread. A mode mismatch here
    // is harmless.
    _coInitializeEx(nullptr, 2 /* COINIT_APARTMENTTHREADED */);

    final clsid = _Guid.allocate('56FDF344-FD6D-11D0-958A-006097C9A090');
    final iid = _Guid.allocate('EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF');
    final out = calloc<Pointer>();
    try {
      final hr = _coCreateInstance(
        clsid,
        nullptr,
        1 /* CLSCTX_INPROC_SERVER */,
        iid,
        out,
      );
      if (hr < 0) {
        Logs().w(
          'Unable to create ITaskbarList3: 0x${hr.toUnsigned(32).toRadixString(16)}',
        );
        return null;
      }
      final taskbar = out.value.cast<Pointer<IntPtr>>();
      final hrInit = _vtable(taskbar, _vtHrInit)
          .cast<NativeFunction<Int32 Function(Pointer)>>()
          .asFunction<int Function(Pointer)>();
      hrInit(taskbar);
      return _taskbar = taskbar;
    } finally {
      calloc.free(clsid);
      calloc.free(iid);
      calloc.free(out);
    }
  }

  static Pointer _vtable(Pointer<Pointer<IntPtr>> object, int slot) =>
      Pointer.fromAddress(object.value[slot]);

  static int _colorRef(Color color) =>
      ((color.b * 255).round() << 16) |
      ((color.g * 255).round() << 8) |
      (color.r * 255).round();

  static Future<Pointer> _badgeIcon(
    String label,
    Color background,
    Color foreground,
  ) async {
    const size = _badgeSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()
        ..color = background
        ..isAntiAlias = true,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: foreground,
          fontSize: label.length > 2 ? 12 : (label.length > 1 ? 16 : 20),
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );
    painter.dispose();
    final image = await recorder.endRecording().toImage(size, size);
    final rgba = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    image.dispose();

    final header = calloc<_BitmapInfoHeader>();
    final bits = calloc<Pointer>();
    final info = calloc<_IconInfo>();
    try {
      header.ref
        ..biSize = sizeOf<_BitmapInfoHeader>()
        ..biWidth = size
        ..biHeight =
            -size // Negative height makes the DIB top-down.
        ..biPlanes = 1
        ..biBitCount = 32;
      final color = _createDibSection(nullptr, header, 0, bits, nullptr, 0);
      final mask = _createBitmap(size, size, 1, 1, nullptr);

      final pixels = bits.value.cast<Uint8>().asTypedList(size * size * 4);
      final source = rgba.buffer.asUint8List(
        rgba.offsetInBytes,
        size * size * 4,
      );
      for (var i = 0; i < source.length; i += 4) {
        pixels[i] = source[i + 2];
        pixels[i + 1] = source[i + 1];
        pixels[i + 2] = source[i];
        pixels[i + 3] = source[i + 3];
      }

      info.ref
        ..fIcon = 1
        ..hbmMask = mask
        ..hbmColor = color;
      final icon = _createIconIndirect(info);
      _deleteObject(color);
      _deleteObject(mask);
      return icon;
    } finally {
      calloc.free(header);
      calloc.free(bits);
      calloc.free(info);
    }
  }
}

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;

  static Pointer<_Guid> allocate(String text) {
    final hex = text.replaceAll('-', '');
    final guid = calloc<_Guid>();
    guid.ref
      ..data1 = int.parse(hex.substring(0, 8), radix: 16)
      ..data2 = int.parse(hex.substring(8, 12), radix: 16)
      ..data3 = int.parse(hex.substring(12, 16), radix: 16);
    for (var i = 0; i < 8; i++) {
      guid.ref.data4[i] = int.parse(
        hex.substring(16 + i * 2, 18 + i * 2),
        radix: 16,
      );
    }
    return guid;
  }
}

final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

final class _IconInfo extends Struct {
  @Int32()
  external int fIcon;
  @Uint32()
  external int xHotspot;
  @Uint32()
  external int yHotspot;
  external Pointer hbmMask;
  external Pointer hbmColor;
}

/// Keeps the native title bar in step with the current theme.
class WindowsTitleBarSync extends StatelessWidget {
  final Widget child;

  const WindowsTitleBarSync({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WindowsShell.setTitleBarColors(
        brightness: theme.brightness,
        caption: theme.colorScheme.surface,
        text: theme.colorScheme.onSurface,
      ),
    );
    return child;
  }
}

/// Shows [unreadChats] on the taskbar in the same colours as in-app badges.
Future<void> updateWindowsTaskbarBadge(BuildContext context, int unreadChats) {
  final colors = Theme.of(context).colorScheme;
  return WindowsShell.setTaskbarBadge(
    unreadChats,
    background: colors.primary,
    foreground: colors.onPrimary,
  );
}
