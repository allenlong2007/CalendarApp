# Shivan and Important events

Allen requested this integration October 28, 2026. Grok Bot `Shivan · Calender` was created through the desktop app and acknowledged its calendar-coordinator role. “Calender” retains Allen's requested spelling. Categories inside CalendarApp remain the existing EventKit calendars.

## Important

The event editor has an Important switch, off by default. When on, the event gets a CalendarApp notification 30 minutes before its start, titled `Shivan · <event title>`. The ordinary reminder preference is retained underneath; turning Important off restores it. This is a CalendarApp local notification, not a Grok push message. Existing notification permission, Focus settings, the nearest-60 queue limit, and opening CalendarApp periodically still apply. A newly marked event whose 30-minute reminder time is already past does not get a retroactive alert.

EventKit has no custom Boolean field. Important is encoded as the exact notes line `[CalendarApp:important=true]`, carried with the event over the existing calendar sync. The editor hides that metadata from its Notes field and preserves user notes. Other calendar apps may show the metadata line. This avoids adding a separate, device-local database flag that Shivan or another device cannot read. The Shortcuts Create Calendar Event action also exposes Important, Category, Location and Notes.

## Local bridge

Build with `bash scripts/build-shivan-bridge.sh`. The helper is:

`build/ShivanCalendarBridge.app/Contents/MacOS/ShivanCalendarBridge`

It accepts one JSON object on stdin and returns JSON. There is no web server, public endpoint, credential export, or cloud upload. Run it only through Grok's approved local command tool. macOS must grant Calendar access to the helper. Do not grant a general-purpose shell full Calendar access as a workaround. The Mac and Grok desktop must be awake and reachable for this integration; Grok's cloud computer cannot see local EventKit by itself.

Commands:

- `{"action":"calendars"}` lists real calendars with identifiers and writable flags.
- `{"action":"events","start":"2026-11-04T00:00:00-08:00","end":"2026-11-05T00:00:00-08:00"}` lists a bounded range.
- `create` requires title, explicit start/end with timezone offsets, an exact writable calendarID and a stable UUID requestID. Optional fields: important (default false), allDay, location, notes. Reuse the same requestID for a retry.
- `update` requires eventID, title, start and end; optional category/location/notes/important preserve existing values when omitted. Repeating events and events with attendees are refused.
- `delete` requires eventID. Repeating events and events with attendees are refused. Shivan must obtain Allen's explicit instruction before deleting or changing an existing event.

The helper uses a cross-process file lock, persistent request receipts, and a reserved `[Shivan:request=<UUID>]` notes line for deduplication. Editing notes through the helper retains that marker. Deleted events or changed identifiers do not silently recreate on replay: they return an error requiring a calendar check. Request receipts live in the user's Application Support/ShivanCalendarBridge directory. Never copy credentials or browser state there. After writes the helper opens CalendarApp to refresh its app-owned notification queue; a successful event save alone does not prove notification delivery.

## Bot handoff contract

When Allen says “let Shivan know,” the originating bot should send Shivan the confirmed title, exact local date, start/end, timezone, category, location, Important true/false, and a stable handoff UUID. Shivan clarifies missing fields, checks conflicts and duplicates, uses the approved helper, and reports the read-back result. Tentative discussions are not automatically scheduled. No invitation or outward email is authorized by a calendar handoff. Keep current calendar ownership and existing bot routines unchanged.

## Verification

TDD RED: `/tmp/calendar-important-red.log` and `/tmp/calendar-bridge-red.log` fail before the respective new types exist. GREEN: `/tmp/calendar-shivan-final-tests.log`, 132 tests in 28 suites pass on Mac Catalyst. Tests cover metadata round-trip, unchanged user notes including blank lines, exact marker matching, 30-minute calculation, Important override, and malformed/ambiguous bridge requests. Coverage percentage was not measured. Swift review approved after fixing concurrent duplicate creation, lost request markers on notes edits, and ignored category changes. Helper compiles in Swift 6.

Live permission/CRUD and notification delivery remain pending. The initial command failed with Calendar access denied; no events were created, changed or deleted. System Settings showed CalendarApp full access, but no separate Shivan entry. An embedded executable Info.plist was added for helper identity; do not treat a successful build as proof of Calendar authorization. Allen approved granting the helper Calendar access, but the Mac locked before the remaining UI steps. Grok per-command approvals remain unchanged.

Release builds succeeded for Mac Catalyst (`/tmp/calendar-shivan-mac-release.log`) and generic iOS (`/tmp/calendar-shivan-ios-release.log`). Installation is not complete: Mac UI is locked, and physical iPhone installation failed with CoreDevice error 4016 (device unavailable). The new toggle is in the built source, not yet verified in Allen's installed daily-driver apps. Resume by unlocking the Mac, granting helper-only Calendar access, verifying a read-only calendar list through Shivan, installing both builds, and testing a temporary event/reminder without altering real appointments. Do not grant zsh broad access. Peer-bot routing instructions have not yet been distributed or tested.
