# Splash redesign (feat/splash-redesign)

Base: feat/integration2 at febcfc877.

- Task 1 (done): no "inbox" wording; slogan is "Where all your threads meet." (source: seam-site src/copy.ts).
- Task 2 (done): the welcome page is variant B, full cobalt with a sheet
  (lib/pages/intro/intro_page.dart, lib/widgets/terms_acceptance_views.dart). Stacked in portrait and
  narrow windows, two panes from 600 dp wide in landscape and from 841 dp in any shape. The launch
  morph keeps the mark at 192 dp. Tests: test/onboarding/welcome_test.dart. After-screens:
  /tmp/review/splash/final_*.png.
- Play feature graphic and alt text carry the new slogan (android/store/make-graphics.py).
  android/store/icon-512.png was left as it was; the duotone branch owns the brand kit.
