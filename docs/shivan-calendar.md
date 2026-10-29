# Shivan and Important events

Allen requested this integration October 28, 2026. Grok Bot `Shivan · Calender` was created through the desktop app and acknowledged its calendar-coordinator role. “Calender” retains Allen's requested spelling. Categories inside CalendarApp remain the existing EventKit calendars.

## Important

The event editor has an Important switch, off by default. When on, the event gets a CalendarApp notification 30 minutes before its start, titled `Shivan · <event title>`. The ordinary reminder preference is retained underneath; turning Important off restores it. This is a CalendarApp local notification, not a Grok push message. Existing notification permission, Focus settings, the nearest-60 queue limit, and opening CalendarApp periodically still apply. A newly marked event whose 30-minute reminder time is already past does not get a retroactive alert.

EventKit has no custom Boolean field. Important is encoded as the exact notes line `[CalendarApp:important=true]`, carried with the event over the existing calendar sync. The editor hides that metadata from its Notes field and preserves user notes. Other calendar apps may show the metadata line. This avoids adding a separate, device-local database flag that Shivan or another device cannot read. The Shortcuts Create Calendar Event action also exposes Important, Category, Location and Notes.

## Local bridge

Build with `bash scripts/build-shivan-bridge.sh`. The helper is:

`build/ShivanCalendarBridge.app/Contents/MacOS/ShivanCalendarBridge`

Use `bash scripts/shivan-calendar.sh` with one JSON object on stdin. This wrapper launches the signed helper through LaunchServices with private request/response files, so macOS uses the helper's own approved Calendar identity rather than Grok's zsh parent. It returns JSON and propagates structured failure status. Directly running the binary from a shell was denied even after helper permission; do not use that path or grant zsh broad access. The app's file arguments are constrained to its private Application Support/ShivanCalendarBridge/exchange directory; the wrapper cleans request, response and status files. No web server, public endpoint, credential export or cloud upload. The Mac and Grok desktop must be awake and reachable; Grok's cloud computer cannot see local EventKit by itself. Without arguments a normal helper app launch is read-only and never waits for stdin. The signing identity defaults to Allen's current Apple Development certificate; set SHIVAN_SIGN_IDENTITY when building on another developer's machine.

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

TDD RED: `/tmp/calendar-important-red.log` and `/tmp/calendar-bridge-red.log` fail before the respective new types exist; `/tmp/calendar-shivan-metadata-red.log` covers hidden routing metadata. GREEN: `/tmp/calendar-shivan-complete-tests.log`, 133 tests in 28 suites pass on Mac Catalyst; final CRLF normalization is rechecked in `/tmp/calendar-shivan-final-green.log`. Tests cover metadata round-trip, unchanged user notes including blank lines, exact marker matching, hidden routing IDs preserved on edit, 30-minute calculation, Important override, and malformed/ambiguous bridge requests. Coverage percentage was not measured. Swift review approved after fixing concurrent duplicate creation, lost request markers on notes edits, ignored category changes and wrapper failure status. Helper compiles in Swift 6.

Live checks October 28 after unlock: System Settings verified ShivanCalendarBridge full Calendar access, with zsh still Add Only. Shivan's LaunchServices wrapper listed nine calendars, seven writable. CalendarApp notification settings were already enabled for desktop, Notification Center, Lock Screen and sound. Installed Mac UI verified Important on/off. Allen confirmed the test notification appeared around 7:46 p.m. PDT; this is user-observed delivery, not merely a successful save. Grok per-command approvals remain unchanged.

Final Release builds succeeded for Mac Catalyst (`/tmp/calendar-shivan-final-mac.log`) and iOS (`/tmp/calendar-shivan-final-ios.log`), and both final builds were installed on the Mac and connected physical iPhone 16. Mac launch was reverified. Final metadata tests pass: `/tmp/calendar-shivan-final-green.log`, 133 tests. Phone notification delivery and cross-device arrival were not independently observed; open CalendarApp on the phone to refresh its queue. The Mac widget's generated App Intents resource changed after Xcode signing; the widget and containing installed app were re-signed with the same Apple Development identity, preserving entitlements/requirements/flags, and final `codesign --verify --deep --strict` passed. iPhone build signature also passed before successful installation.

Shivan created one `Shivan setup check (temporary)` event in Tech, 8:16–8:21 p.m. PDT, Important=true, request UUID `83F8A09C-7E59-40DF-AAB7-287B34C75B94`. Replaying returned alreadyExists with the same ID; range read-back found one event. After Allen confirmed notification delivery, Shivan changed only the test event to Important=false and new notes, verified retention of its routing marker, replayed again without a duplicate, deleted the test event and verified an empty time range. No real appointment changed. All five routing recipients were independently visible in Grok's exchange list: Alex, Robert, Aarya, Nathan and Ari. Alex acknowledged saving the instruction. Raw UI evidence and transcripts remain in the private Grok archive `shivan/`, not this public app repo.
