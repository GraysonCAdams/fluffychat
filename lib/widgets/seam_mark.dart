// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:material_ui/material_ui.dart';

/// The Seam mark, still, drawn in one [color] on the stitch loader's logo
/// pose, so it lines up exactly with [SeamStitchLoader] at the same [size].
class SeamMark extends StatelessWidget {
  final double size;
  final Color color;

  const SeamMark({super.key, this.size = 96, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: SeamStitchPainter(motion: SeamStitchMotion()..land(), ink: color),
  );
}
