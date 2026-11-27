// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

/// The measurements every settings page shares, from the Material 3 list
/// spec (m3.material.io/components/lists/specs): a contained list of filled
/// items, separated by gaps and grouped under section headers.
abstract class SettingsMetrics {
  /// Space between a group and the edge of the page.
  static const double pageMargin = 16;

  /// Space between the edge of a row and its content
  /// (`list-item.leading-space`, `list-item.trailing-space`).
  static const double rowInset = 16;

  /// Space between a row's icon and its text (`list-item.between-space`).
  static const double iconGap = 12;

  /// `list-item.leading-icon.size`.
  static const double iconSize = 24;

  /// `list-item.one-line.container.height`.
  static const double oneLineHeight = 56;

  /// `list-item.two-line.container.height`.
  static const double twoLineHeight = 72;

  /// `list-item.top-space` and `list-item.bottom-space`.
  static const double rowVerticalPadding = 10;

  /// The outer corners of a group (`list.container.shape`).
  static const double groupRadius = 16;

  /// The corners of a row inside a group
  /// (`list-item.container.expressive.shape`).
  static const double rowRadius = 4;

  /// Space between two rows of a group (`list.segmented.gap`).
  static const double rowGap = 2;

  /// The widest the content of a settings page gets, so rows stay readable
  /// in a wide desktop pane.
  static const double maxContentWidth = 640;

  /// Where a section header and a caption start: in line with the text of
  /// a row without an icon.
  static const double textInset = pageMargin + rowInset;

  /// The fill of a row: one step above the surface the page sits on, which
  /// in the column-mode card is surfaceContainerLow.
  static Color rowColor(ThemeData theme) {
    final scheme = theme.colorScheme;
    return scheme.surface == scheme.surfaceContainerLow
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainer;
  }

  static const ShapeBorder rowShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(rowRadius)),
  );
}

/// The scrolling body of a settings page: [children] in a column no wider
/// than [SettingsMetrics.maxContentWidth], centred in a wide pane.
class SettingsBody extends StatelessWidget {
  final List<Widget> children;

  const SettingsBody({required this.children, super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: SettingsMetrics.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

/// A settings sub-page: an app bar titled [title] over a [SettingsBody].
/// In column mode a page opened from the settings home fills the side card
/// with nothing to go back to, so its title is centred and the back button
/// left out. A [nested] page, opened from another sub-page, keeps the back
/// button there too.
class SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final List<Widget> children;
  final bool nested;

  const SettingsPage({
    required this.title,
    required this.children,
    this.actions,
    this.nested = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final columnMode = FluffyThemes.isColumnMode(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: nested || !columnMode,
        centerTitle: columnMode,
        actions: actions,
      ),
      body: SettingsBody(children: children),
    );
  }
}

/// The title of a group of settings, with an optional [description] of
/// what the group is for.
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String? description;

  const SettingsSectionHeader(this.title, {this.description, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = this.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SettingsMetrics.textInset,
        20,
        SettingsMetrics.textInset,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A line of explanation between groups, in line with the section headers.
class SettingsCaption extends StatelessWidget {
  final String text;
  final Color? color;

  const SettingsCaption(this.text, {this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SettingsMetrics.textInset,
        vertical: 8,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A group of rows with rounded outer corners. Each child paints its own
/// fill ([SettingsTile], [SettingsGroupItem]) and the gap around it, so a
/// child that builds nothing leaves no trace in the group.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const SettingsGroup({required this.children, super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: SettingsMetrics.pageMargin),
    child: ClipRRect(
      clipper: const _GroupClipper(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// Rounds the corners of a group along the fill of its first and last
/// rows, which starts half a gap inside the group.
class _GroupClipper extends CustomClipper<RRect> {
  const _GroupClipper();

  @override
  RRect getClip(Size size) => RRect.fromLTRBR(
    0,
    SettingsMetrics.rowGap / 2,
    size.width,
    size.height - SettingsMetrics.rowGap / 2,
    const Radius.circular(SettingsMetrics.groupRadius),
  );

  @override
  bool shouldReclip(_GroupClipper oldClipper) => false;
}

/// The filled container of one entry in a [SettingsGroup], for content
/// that is not a [SettingsTile]: a slider, a row of swatches, a preview.
class SettingsGroupItem extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const SettingsGroupItem({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SettingsMetrics.rowGap / 2),
    child: Material(
      color: color ?? SettingsMetrics.rowColor(Theme.of(context)),
      shape: SettingsMetrics.rowShape,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// One row of a settings page: 56 dp tall with a title, 72 dp with a
/// [subtitle], a 24 dp [leading] icon and the same insets on every page.
class SettingsTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;

  /// An icon, sized and coloured by the row, or an avatar.
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// Marks the row as the page shown beside the list in column mode.
  final bool selected;

  /// Colours the title and the icon, for a destructive action.
  final Color? color;

  const SettingsTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.color,
    super.key,
  });

  /// The trailing arrow of a row that opens another page.
  static const Widget chevron = Icon(Icons.chevron_right_outlined);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        color ?? (selected ? scheme.onSecondaryContainer : scheme.onSurface);
    final secondary =
        color ??
        (selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant);
    return SettingsGroupItem(
      color: selected ? scheme.secondaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: SettingsMetrics.rowInset,
        ),
        horizontalTitleGap: SettingsMetrics.iconGap,
        minLeadingWidth: SettingsMetrics.iconSize,
        minVerticalPadding: SettingsMetrics.rowVerticalPadding,
        minTileHeight: subtitle == null
            ? SettingsMetrics.oneLineHeight
            : SettingsMetrics.twoLineHeight,
        shape: SettingsMetrics.rowShape,
        iconColor: secondary,
        textColor: foreground,
        titleTextStyle: theme.textTheme.bodyLarge,
        subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: color == null && !selected ? scheme.onSurfaceVariant : null,
        ),
        leadingAndTrailingTextStyle: theme.textTheme.labelLarge?.copyWith(
          color: secondary,
        ),
        leading: leading == null
            ? null
            : IconTheme.merge(
                data: const IconThemeData(size: SettingsMetrics.iconSize),
                child: leading!,
              ),
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
        enabled: enabled,
      ),
    );
  }
}

/// A [SettingsTile] with a switch. Tapping anywhere on the row toggles it.
class SettingsSwitchTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final bool value;

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;

  const SettingsSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: SettingsTile(
        title: title,
        subtitle: subtitle,
        leading: leading,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged(!value),
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// A setting picked on a slider: its [title], the current [valueLabel] and
/// the [slider] underneath, as one entry of a [SettingsGroup].
class SettingsSliderTile extends StatelessWidget {
  final String title;
  final String? valueLabel;
  final Widget slider;

  const SettingsSliderTile({
    required this.title,
    required this.slider,
    this.valueLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueLabel = this.valueLabel;
    return SettingsGroupItem(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SettingsMetrics.rowInset,
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
                if (valueLabel != null)
                  Text(
                    valueLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      // Digits of one width, so the label keeps its place
                      // while the slider moves.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          // The slider's own 24 dp inset puts the ends of its track in
          // line with the row's content.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SettingsMetrics.rowInset - 24 + 8,
            ),
            child: slider,
          ),
        ],
      ),
    );
  }
}
