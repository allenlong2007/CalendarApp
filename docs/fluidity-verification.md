# Calendar fluidity verification — 2026-10-24

## Problem and implementation

The previous installation was a Debug Mac Catalyst build. Scroll position lived in
MonthView state, so changes could regenerate week descriptors and row content.
Day grouping and per-day sorting were repeated during redraws. Single-click
handlers competed with double-click handlers. EventStore revision changes and the
undo-toast animation could animate a large part of the calendar view tree.

The fix isolates scroll position in an observable reference, reuses grouped day
maps with the existing bounded/revision-aware event cache, and uses the sorted
query order directly. Single and double taps recognize together within each
view's gesture, preserving normal child-over-parent precedence. Data invalidation
is unanimated; selection/completion feedback stays local, and toast animation is
scoped to the toast. Catalyst deceleration is 0.995 (between normal and fast).
The installed Mac app uses the optimized Release configuration.

## Regression evidence

- RED checkpoint: a851668. CalendarRenderCacheTests failed compilation because
  CalendarEventCache.eventsByDay was absent. Log: /private/tmp/calendar-fluid-red.log.
- GREEN: the complete unit suite passed (111 tests, 20 suites) after implementation.
  Log: /private/tmp/calendar-fluid-green.log.
- Regression tests exercise 50 redraws reusing one grouping, revision invalidation,
  sharing event-query results, overnight coverage, and eviction of derived maps.
- Final unit run: 111 tests in 20 suites passed. Log:
  /private/tmp/calendar-fluid-final-tests.log.
- Optimized universal Mac Catalyst Release build passed. Log:
  /private/tmp/calendar-fluid-mac-release.log.
- Installed /Applications/CalendarApp.app; strict deep signature verification passed,
  and its executable SHA-256 matches the built Release executable.
- Live checks on October 25: event click retains the preview; double-click opens
  that event's editor; an empty-day click selects the day; empty-day double-click
  opens a new draft. Both editors were cancelled without saving changes.
- Scrolling down/up settles on aligned three-week rows. Month/Week/Day controls
  switch correctly. The app was left in Month view.
- Required Swift review found an ancestor/child tap conflict in the initial
  implementation; combined gestures at each level fixed it and live checks passed.

## Scope and limitations

The CPU sample (/private/tmp/calendar-fluid-before.sample.txt) was dominated by
idle time and accessibility traversal during automated interactions. It is not a
frame-rate benchmark and does not establish a measured frame-rate improvement.
Manual scrolling and interaction checks complement deterministic cache tests.

## External mouse-wheel follow-up — 2026-10-25

- Added a discrete-input UIPanGestureRecognizer; the native scroll recognizer
  retains continuous trackpad input and touch handling. See Apple's
  [scroll input types](https://developer.apple.com/documentation/uikit/uiscrolltypemask).
- Wheel deltas feed a bounded, refresh-rate-independent 75 ms exponential glide.
  Reversing the wheel clears travel in the previous direction. Toolbar jumps,
  native panning, removal from the window, and representable teardown cancel it.
- Weak display-link ownership and teardown restore the original native scroll
  input mask/deceleration. Reduce Motion applies movement without interpolation.
- Settling resolves the closest instantiated week marker in scroll-view coordinates,
  avoiding stale SwiftUI row identities after manual contentOffset updates.
- RED: 162e1cd (motion integrator absent), /private/tmp/calendar-wheel-red.log.
- Additional RED: f001562 (visible-row settlement absent),
  /private/tmp/calendar-wheel-settling-red.log.
- GREEN: 116 tests / 22 suites passed, /private/tmp/calendar-wheel-final-tests.log.
  Tests cover accumulation, reversal, bounded travel, 60/120 Hz equivalence,
  input routing, repeated installation, restoring native settings, and choosing
  the nearest row even after lazy-stack coordinate shifts.
- Optimized universal Mac Catalyst build passed:
  /private/tmp/calendar-wheel-final-release.log. Installed app passed deep strict
  code-signature verification.
- Live automated scroll input reached the discrete-wheel handler (confirmed in
  /private/tmp/calendar-wheel-live.log). Initial live testing exposed stale-row
  settling; the geometry-based regression/fix addresses it. Final live settling
  checks passed after unlock: the calendar retained the new November 1 top week
  after a downward wheel scroll, then returned to October 25 after reversing.
  Both positions showed three complete aligned weeks without snapping back.
- The required Swift reviewer was invoked but declined review because its role
  requires swift build, which cannot validate this Xcode-only project. Xcode
  builds, deterministic tests, and local diff review were used for validation.

## iPhone rollout and portrait framing — 2026-10-25

- Portrait iPhones render the foreground artwork at 86% of the previous height,
  bottom-aligned, with a faded top edge and soft backing to fill the viewport.
  Landscape, iPad, and Catalyst framing retain their previous geometry.
- Device Release build and iOS Simulator build passed. Logs:
  /private/tmp/calendar-phone-latest.log and
  /private/tmp/calendar-phone-portrait-preview.log.
- Signed app installed successfully on the connected physical iPhone 16, device
  00008140-00115584368B001C. devicectl independently listed CalendarApp afterward.
  Installation result: /private/tmp/calendar-phone-install-result.json.
- Simulator app-control preview was unavailable because this environment has
  command-line simulator services but no Simulator.app UI bundle. No visual
  inspection on the physical phone is claimed.

- Portrait follow-up: reduced foreground height from 86% to 80% for a further
  gentle zoom-out. Device Release build and installation on the same physical
  iPhone 16 succeeded. Logs: /private/tmp/calendar-phone-portrait-80.log and
  /private/tmp/calendar-phone-portrait-80-install.json.

- Further portrait adjustment: foreground height 80% to 74% (7.5% smaller than
  the prior version). Release build, strict signature verification, and physical
  iPhone installation succeeded. Logs: /private/tmp/calendar-phone-portrait-74.log
  and /private/tmp/calendar-phone-portrait-74-install.json.

- Portrait top-edge refinement: reduced foreground height 74% to 70%, removed
  the enlarged blurred duplicate, and extended the fade into the canvas to 26%
  of the image height using gradual opacity stops. Device Release build, strict
  signature check, and physical iPhone installation passed. Logs:
  /private/tmp/calendar-phone-portrait-blend.log and
  /private/tmp/calendar-phone-portrait-blend-install.json.

- Portrait framing follow-up (2026-10-25): reduced artwork height from 70% to
  58% of the viewport, about 17% smaller than the previous framing. Retained
  bottom alignment and the existing top fade. Device Release and iPhone 16
  Simulator builds passed; strict deep signature verification and installation
  on the physical iPhone 16 succeeded, and the updated app launched. Inspected
  the simulator portrait screenshot at /private/tmp/calendar-portrait-framing-after.png.
  Build logs: /private/tmp/calendar-portrait-framing-build.log and
  /private/tmp/calendar-portrait-framing-sim.log. Install result:
  /private/tmp/calendar-portrait-framing-install.json. Physical-phone visual
  approval remains with the user.

- Tab-bar clearance follow-up: kept the 58% portrait scale and raised the
  artwork 96 pt, with a short bottom fade into the canvas. iPhone 16 simulator
  screenshot confirms both characters are fully above the Calendar/Planner bar
  (/private/tmp/calendar-portrait-clearance.png). Simulator and device Release
  builds passed; strict signature verification and physical iPhone installation
  succeeded. Logs: /private/tmp/calendar-portrait-clearance-build.log,
  /private/tmp/calendar-portrait-clearance-sim.log, and
  /private/tmp/calendar-portrait-clearance-install.json.

- Subtler placement: reduced portrait bottom clearance from 96 pt to 76 pt
  while retaining the same scale and fades. Device Release and simulator builds,
  strict signature verification, and physical iPhone installation/launch passed.
  Logs: /private/tmp/calendar-portrait-subtle-build.log,
  /private/tmp/calendar-portrait-subtle-sim.log, and
  /private/tmp/calendar-portrait-subtle-install.json.

- Cloud/sky visibility: shortened the top fade from 26% to 7% of artwork
  height, keeping the 58% scale and 76 pt lift. Device Release and simulator
  builds, strict signature verification, and physical iPhone installation and
  launch passed. Logs: /private/tmp/calendar-portrait-sky-build.log,
  /private/tmp/calendar-portrait-sky-sim.log, and
  /private/tmp/calendar-portrait-sky-install.json.

- Removed the visible top cutoff by extending the included artwork's blue sky
  130 pt upward, with a 12% cloud fade over that backing. Composite the artwork
  and sky before applying the shared opacity to avoid a second horizontal seam.
  Scale and position remain 58% / 76 pt. Simulator screenshot inspected:
  /private/tmp/calendar-portrait-sky-blend.png. Device Release and simulator
  builds and strict signature verification passed. Logs:
  /private/tmp/calendar-portrait-sky-blend-build.log and
  /private/tmp/calendar-portrait-sky-blend-sim.log.

- Subtle vertical stretch: stretched the portrait artwork by 3.5% vertically
  around its bottom edge, preserving width and 76 pt menu clearance. Shortened
  the sky extension to 80 pt. Simulator and device Release builds, strict
  signature verification, and physical iPhone installation passed. Logs:
  /private/tmp/calendar-portrait-stretch-build.log,
  /private/tmp/calendar-portrait-stretch-sim.log, and
  /private/tmp/calendar-portrait-stretch-install.json.

- Softer edge refinement: total vertical stretch is now 5% (previously 3.5%).
  Top fade spans 16%, bottom fade 6%, each with intermediate opacity stops;
  sky extends 100 pt upward with a gradual transition. Menu clearance remains
  76 pt. Simulator and device Release builds, strict signature verification,
  and physical iPhone installation passed. Logs:
  /private/tmp/calendar-portrait-soft-build.log,
  /private/tmp/calendar-portrait-soft-sim.log, and
  /private/tmp/calendar-portrait-soft-install.json.

- After reverting the longer-fade experiment, made a small adjustment only:
  top fade 16% to 18%, bottom fade 6% to 7%, with matching intermediate stops.
  Sky backing follows the new top fade length; sky extension, size, stretch,
  and position remain unchanged.
  Simulator and device Release builds, strict signature verification, and
  physical iPhone installation passed. Logs:
  /private/tmp/calendar-portrait-smallfade-build.log,
  /private/tmp/calendar-portrait-smallfade-sim.log, and
  /private/tmp/calendar-portrait-smallfade-install.json.

- Upper sky reach: extended the sky backing from 100 pt to 160 pt above the
  artwork so its transition continues behind the date controls and view-mode
  bar. Artwork mask and the approved bottom fade remain unchanged. Simulator
  and device Release builds, strict signature verification, and physical iPhone
  installation passed. Logs: /private/tmp/calendar-portrait-upperfade-build.log,
  /private/tmp/calendar-portrait-upperfade-sim.log, and
  /private/tmp/calendar-portrait-upperfade-install.json.

- Consistent top transition: removed intermediate top mask and sky gradient
  stops, giving continuous linear opacity ramps without the sky plateau. Kept
  the approved bottom fade, framing, and upper reach. Simulator and device
  Release builds, signature verification, and physical iPhone installation
  passed. Logs: /private/tmp/calendar-portrait-linear-build.log,
  /private/tmp/calendar-portrait-linear-sim.log, and
  /private/tmp/calendar-portrait-linear-install.json.

- Cloud-top reveal: moved the end of the top fade from 18% to 15% of artwork
  height so the upper cloud becomes visible sooner. Kept the transparent edge,
  continuous ramp, sky backing, framing, and bottom fade.
  Simulator and device Release builds, strict signature verification, and
  physical iPhone installation passed. Logs:
  /private/tmp/calendar-portrait-cloudtop-build.log,
  /private/tmp/calendar-portrait-cloudtop-sim.log, and
  /private/tmp/calendar-portrait-cloudtop-install.json.

- Higher blend: top mask reaches full visibility at 12% instead of 15%; sky
  extension increased from 160 pt to 180 pt. Bottom fade and artwork framing
  unchanged. Simulator and device Release builds, signature verification, and
  physical iPhone installation passed. Logs:
  /private/tmp/calendar-portrait-higher-build.log,
  /private/tmp/calendar-portrait-higher-sim.log, and
  /private/tmp/calendar-portrait-higher-install.json.

- Tiny upward nudge: top fade endpoint 12% to 11%, sky extension 180 pt to
  190 pt; bottom and framing unchanged. Device Release build and strict
  signature verification passed. Build log:
  /private/tmp/calendar-portrait-nudge-build.log.

- Continued the linear top blend farther upward past the Today divider:
  top fade endpoint 11% to 10%, sky extension 190 pt to 205 pt. Bottom and
  framing unchanged. Device Release build and signature verification passed.
  Build log: /private/tmp/calendar-portrait-divider-build.log.

- Divider follow-up: top fade endpoint 10% to 9%, sky extension 205 pt to
  220 pt for a slightly higher, longer blend around the divider. Bottom and
  framing unchanged. Device Release build and signature verification passed.
  Build log: /private/tmp/calendar-portrait-divider-next-build.log.

- Further top fade: top mask endpoint 9% to 8%, sky extension 220 pt to
  235 pt. Bottom and framing unchanged. Device Release build and signature
  verification passed. Build log:
  /private/tmp/calendar-portrait-divider-final-build.log.

- Additional upward step: top mask endpoint 8% to 7%, sky extension 235 pt
  to 250 pt. Bottom and framing unchanged. Device Release build and signature
  verification passed. Build log:
  /private/tmp/calendar-portrait-upperstep-build.log.

- Next upward step: top mask endpoint 7% to 6%, sky extension 250 pt to
  265 pt. Bottom and framing unchanged. Device Release build and signature
  verification passed. Build log:
  /private/tmp/calendar-portrait-nextstep-build.log.

- Smoothed the flattened top: sky extension 265 pt to 280 pt, with a wider
  cloud fade (6% to 8%) to soften the upper edge. Bottom and framing unchanged.
  Simulator and device Release builds, strict signature verification, and
  physical iPhone installation passed. Logs:
  /private/tmp/calendar-portrait-smoothup-build.log,
  /private/tmp/calendar-portrait-smoothup-sim.log, and
  /private/tmp/calendar-portrait-smoothup-install.json.

- Tiny cloud reveal: adjusted only the top mask endpoint from 8% to 7%,
  retaining sky extension, framing, and bottom fade. Device Release build and
  strict signature verification passed. Build log:
  /private/tmp/calendar-portrait-reveal-build.log.

- Extended only the top sky blend another 10 pt upward (280 pt to 290 pt).
  All other settings retained. Device Release build and strict signature
  verification passed. Build log:
  /private/tmp/calendar-portrait-tenpoint-build.log.

- Extended the top sky blend another 10 pt upward (290 pt to 300 pt).
  All other settings retained. Device Release build and strict signature
  verification passed. Build log: /private/tmp/calendar-portrait-300-build.log.

- Extended the top sky blend another 20 pt upward (300 pt to 320 pt).
  All other settings retained. Device Release build and strict signature
  verification passed. Build log: /private/tmp/calendar-portrait-320-build.log.

- Extended the top sky blend another 30 pt upward (320 pt to 350 pt).
  All other settings retained. Device Release build and strict signature
  verification passed. Build log: /private/tmp/calendar-portrait-350-build.log.

- Extended the top sky blend another 40 pt upward (350 pt to 390 pt).
  All other settings retained. Device Release build and strict signature
  verification passed. Build log: /private/tmp/calendar-portrait-390-build.log.

- Clearer cloud top: reduced the artwork's top fade from 7% to 2.5%, keeping
  sky reach and bottom/framing unchanged. The source artwork already crops the
  very top of the central cloud. Simulator screenshot inspected:
  /private/tmp/calendar-portrait-clearcloud.png. Simulator and device Release
  builds and strict signature verification passed. Logs:
  /private/tmp/calendar-portrait-clearcloud-build.log and
  /private/tmp/calendar-portrait-clearcloud-sim.log.

- Gradual cloud correction: widened the abrupt 2.5% artwork fade to 12%,
  with eased opacity stops at quarter intervals. Used the same easing for
  the sky's existing 390 pt extension. Bottom and framing unchanged.
  Simulator and device Release builds and signature verification passed.
  Logs: /private/tmp/calendar-portrait-gradual-build.log and
  /private/tmp/calendar-portrait-gradual-sim.log.

- Reverted the last eased whole-cloud fade at the user's request. Restored
  linear sky blending; the included artwork now supplies a luminance mask
  that preserves the bright cloud while fading its surrounding blue sky.
  Only the first 1.5% at the top tips fades in. Custom photos retain the prior
  simple 2.5% fade. Bottom, stretch, and positioning unchanged. Simulator
  screenshot inspected: /private/tmp/calendar-portrait-contour.png.
  Simulator and device Release builds and signature verification passed.
  Logs: /private/tmp/calendar-portrait-contour-sim.log and
  /private/tmp/calendar-portrait-contour-build.log.

- Restored more cloud tips by reducing only their fade from 1.5% to 0.5% of
  artwork height. Approved sky blend and all framing retained. Device Release
  build and strict signature verification passed. Build log:
  /private/tmp/calendar-portrait-tips-build.log.

- Removed the remaining 0.5% cloud-tip fade so the luminance mask preserves
  the cloud right up to the image's top edge. Sky blend and framing retained.
  Device Release build and strict signature verification passed. Build log:
  /private/tmp/calendar-portrait-fulltips-build.log.

- 2026-10-26 source cutoff fix: the original image itself crops the crown.
  Added a portrait-only extended asset with an ImageGen reconstruction of the
  missing crown and extra sky; source/provenance in
  `docs/cloud-background-restoration.md`. Compensated portrait artwork height
  for the added canvas. Original landscape/Mac asset and custom imports retained.
  Inspected the actual iPhone 16 simulator screenshot:
  /private/tmp/calendar-portrait-completecloud.png. The complete rounded crown
  is visible with blue sky above, and characters remain above the bottom menu.
  Simulator and device Release builds and strict signature verification passed.
  Logs: /private/tmp/calendar-portrait-completecloud-build.log and
  /private/tmp/calendar-portrait-completecloud-sim.log.
