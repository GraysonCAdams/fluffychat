# Splash redesign (feat/splash-redesign)

Base: feat/integration2 at febcfc877.

- Task 1 (done): no "inbox" wording; slogan is "Where all your threads meet." (source: seam-site src/copy.ts).
- Task 2 (waiting on Grayson's choice): welcome page and terms acceptance redesign. Three prototypes
  (A hero band, B full cobalt + sheet, C editorial) live in test/mockups/ as review-only widgets;
  `flutter test test/mockups/splash_mockups_test.dart` renders them to build/mockups/, and the
  contact sheets are /tmp/review/splash/contact_{light,dark}.png. Nothing in lib/ is changed yet.
  When a variant is chosen: build it in lib/pages/intro/intro_page.dart and
  lib/widgets/terms_acceptance_views.dart, keep the launch morph (SeamStartup.loaderSize 192),
  extend test/onboarding/welcome_test.dart, then delete test/mockups/.
