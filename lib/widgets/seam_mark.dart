// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:material_ui/material_ui.dart';

/// The Seam mark, still, drawn in [color] with the piece above the seam in
/// [pale] (one colour when null) on the stitch loader's logo pose, so it
/// lines up exactly with [SeamStitchLoader] at the same [size].
class SeamMark extends StatelessWidget {
  final double size;
  final Color color;
  final Color? pale;

  const SeamMark({
    super.key,
    this.size = 96,
    this.color = Colors.white,
    this.pale,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: SeamStitchPainter(
      motion: SeamStitchMotion()..land(),
      ink: color,
      pale: pale,
    ),
  );
}
