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

Menus also follow the Material 3 menu guidelines on fitting the window:

- `lib/src/popup_menu.dart`: `MenuObscuredInsets` names the edges of the
  window that something outside the app covers (the Windows taskbar over a
  window that runs under it), and popup menus stay that far inside, on top
  of the view padding and their 8 pixel margin. A popup menu that does not
  fit below the point it opens from opens above it when it fits there. A
  menu too tall for the window scrolls with its scrollbar always showing.
- `lib/src/menu_anchor.dart`: `MenuAnchor` menus keep clear of
  `MenuObscuredInsets` too.

Every patched spot is marked `FluffyChat:`. To move to a newer `material_ui`,
copy its `lib/` over this one and reapply those hunks.
