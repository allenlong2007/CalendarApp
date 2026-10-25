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
