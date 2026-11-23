// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/gallery_picker/camera_view.dart';
import 'package:fluffychat/pages/chat/gallery_picker/media_grid_sheet.dart';
import 'package:fluffychat/pages/chat/gallery_picker/picked_media.dart';
import 'package:fluffychat/pages/chat/gallery_picker/send_preview.dart';
import 'package:fluffychat/pages/chat/gallery_picker/thumbnail_cache.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:photo_manager/photo_manager.dart';

/// What the gallery picker returns when the user taps send.
class GalleryPickerResult {
  final List<XFile> files;
  final String caption;

  /// Send at full quality instead of the usual compressed size.
  final bool hd;

  const GalleryPickerResult({
    required this.files,
    required this.caption,
    required this.hd,
  });
}

/// Opens the full-screen camera and gallery picker. Resolves to null when
/// the user closes it without sending.
Future<GalleryPickerResult?> showGalleryPicker(
  BuildContext context, {
  required String recipientName,
}) => Navigator.of(context, rootNavigator: true).push<GalleryPickerResult>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => GalleryPickerPage(recipientName: recipientName),
  ),
);

/// Full-screen picker modelled on the camera-and-gallery flow of modern
/// messaging apps.
///
/// The upper area shows a live camera while nothing is picked and switches
/// to a send preview (carousel, caption, send) once something is. Below it a
/// draggable sheet lists recent gallery media. The page always renders in a
/// dark scheme because it frames a camera viewfinder and photos.
class GalleryPickerPage extends StatefulWidget {
  final String recipientName;

  const GalleryPickerPage({required this.recipientName, super.key});

  @override
  State<GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends State<GalleryPickerPage> {
  /// Collapsed height of the gallery sheet as a fraction of the body.
  static const double _sheetFraction = 0.34;

  /// Gap between the upper area and the collapsed sheet.
  static const double _sheetGap = 12;

  final MediaSelection _selection = MediaSelection();
  final ThumbnailCache _thumbnails = ThumbnailCache();
  final TextEditingController _caption = TextEditingController();

  /// Requested once up front. The camera waits for it before asking for its
  /// own permission, because Android shows one permission dialog at a time.
  late final Future<PermissionState> _galleryPermission =
      PhotoManager.requestPermissionExtend();

  /// Built once and reused, so page rebuilds (switching views, toggling HD,
  /// sending) never rebuild the grid.
  late final Widget _sheet = MediaGridSheet(
    selection: _selection,
    thumbnails: _thumbnails,
    permission: _galleryPermission,
    minChildSize: _sheetFraction,
  );

  /// True while the user has asked for the camera on top of an existing
  /// selection via the camera button in the send preview.
  bool _cameraRequested = false;
  int _lastLength = 0;
  bool _hd = false;
  bool _sending = false;

  bool get _showCamera => _selection.isEmpty || _cameraRequested;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    _caption.dispose();
    super.dispose();
  }

  /// Rebuilds the page only when the upper area has to switch views; list
  /// changes are handled by the send preview itself.
  void _onSelectionChanged() {
    // The selection has already changed, so the previous view is derived
    // from the length seen last time.
    final wasCamera = _lastLength == 0 || _cameraRequested;
    final grew = _selection.length > _lastLength;
    _lastLength = _selection.length;
    // Picking or capturing something always leads to the send preview.
    if (grew) _cameraRequested = false;
    if (_showCamera != wasCamera) setState(() {});
  }

  void _close() => Navigator.of(context).pop();

  ThemeData? _appTheme;
  ThemeData? _darkTheme;

  /// The app theme when it is already dark, otherwise a dark theme from the
  /// same seed colour. Cached per app theme: a fresh ThemeData on every
  /// rebuild would make every themed widget below rebuild too.
  ThemeData _pickerTheme(BuildContext context) {
    final appTheme = Theme.of(context);
    if (appTheme.brightness == Brightness.dark) return appTheme;
    if (!identical(appTheme, _appTheme) || _darkTheme == null) {
      _appTheme = appTheme;
      _darkTheme = FluffyThemes.buildTheme(
        context,
        Brightness.dark,
        appTheme.colorScheme.primary,
      );
    }
    return _darkTheme!;
  }

  Future<void> _send() async {
    if (_sending || _selection.isEmpty) return;
    setState(() => _sending = true);
    try {
      final files = <XFile>[];
      for (final media in _selection.items) {
        switch (media) {
          case CapturedMedia():
            files.add(media.file);
          case GalleryMedia():
            final entity = media.entity;
            // In HD the untouched original is preferred. Otherwise the
            // platform's displayable copy is enough (on iOS that is a JPEG
            // rather than the HEIC original).
            final file = _hd
                ? await entity.originFile ?? await entity.file
                : await entity.file ?? await entity.originFile;
            if (file == null) continue;
            files.add(
              XFile(
                file.path,
                mimeType: entity.mimeType ?? await entity.mimeTypeAsync,
              ),
            );
        }
      }
      if (!mounted) return;
      if (files.isEmpty) {
        setState(() => _sending = false);
        return;
      }
      Navigator.of(context).pop(
        GalleryPickerResult(
          files: files,
          caption: _caption.text.trim(),
          hd: _hd,
        ),
      );
    } catch (e, s) {
      Logs().w('Unable to resolve picked media', e, s);
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _pickerTheme(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: PopScope(
          // Back from the camera returns to the send preview when there is
          // a selection to go back to.
          canPop: !(_cameraRequested && _selection.length > 0),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _cameraRequested = false);
          },
          child: Scaffold(
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            resizeToAvoidBottomInset: true,
            body: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    // With the keyboard up the grid is hidden and the
                    // preview takes the whole body, so the caption row sits
                    // directly above the keyboard.
                    bottom: keyboardOpen
                        ? 0
                        : constraints.maxHeight * _sheetFraction + _sheetGap,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(
                            begin: 0.96,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _showCamera
                          ? CameraView(
                              key: const ValueKey('camera'),
                              waitFor: _galleryPermission,
                              onClose: _close,
                              onCaptured: _selection.add,
                            )
                          : SendPreview(
                              key: const ValueKey('preview'),
                              selection: _selection,
                              thumbnails: _thumbnails,
                              recipientName: widget.recipientName,
                              caption: _caption,
                              hd: _hd,
                              sending: _sending,
                              onToggleHd: () => setState(() => _hd = !_hd),
                              onClose: _close,
                              onOpenCamera: () =>
                                  setState(() => _cameraRequested = true),
                              onSend: _send,
                            ),
                    ),
                  ),
                  // Kept mounted while the keyboard is up so the loaded
                  // assets and scroll position survive.
                  Offstage(offstage: keyboardOpen, child: _sheet),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
