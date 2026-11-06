# material_ui 1.8.0, patched for FluffyChat

A copy of `lib/` from the pub.dev release of `material_ui` 1.8.0 (the Material
library that Flutter 3.47 ships as a package), used through
`dependency_overrides` in the app's `pubspec.yaml`.

Upstream opens popup menus and dropdowns item by item: the panel grows
linearly, one item height at a time, and each item fades in after the one
above it. The patch makes each menu open as one eased motion:

- `lib/src/popup_menu.dart`: the panel opens at full width and its height
  follows `Easing.emphasizedDecelerate`, every item fades in at the same
  time, and the items are clipped to the growing panel.
- `lib/src/dropdown.dart`: the panel grows on `Easing.emphasizedDecelerate`
  from the start, and the remaining items fade in together while it grows.

Every patched spot is marked `FluffyChat:`. To move to a newer `material_ui`,
copy its `lib/` over this one and reapply those hunks.
