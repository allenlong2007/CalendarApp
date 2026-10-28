# Voice command upgrade: 2026-10-28

## Changes

- Allow four-second pauses instead of stopping after 1.7 seconds.
- End microphone audio before waiting up to two seconds for final words. Cancelled
  or superseded recognition callbacks are rejected by a segment UUID.
- Keep completed recognition segments when Apple finalizes a task during dictation.
  Partial hypotheses replace the current segment rather than being appended twice.
- Provide deduplicated on-device vocabulary hints from calendar names, location
  overrides, saved-address labels/addresses, and known campus places. No private
  vocabulary is supplied to the existing server fallback.
- Correct the complete known phrase “mirror/mere/mure tennis court(s)” to “Muir
  tennis courts”; ordinary uses of “mirror” stay unchanged.
- Extract title, location, date/time, duration, category, reminders, and notes more
  flexibly. Quoted titles retain date/place words. Multiple-event parsing preserves
  conjunctions inside names and details.
- Add previewed, undoable location edits. Bulk matching requires exact title words,
  applies weekday filters, and limits updates to 120 upcoming matches within the
  existing one-year search window. Ambiguous single-event requests require narrowing.
- Weekday-specific location fallback records avoid relabeling other weekdays with
  the same event title. Their keys use the existing synced location record format.
- Typed commands cancel pending microphone results and clear stale speech errors.

## Validation

RED checkpoint: ed207c4. New cases failed because long-command speech helpers and
location-change intents were absent. Log: /private/tmp/calendar-voice-red.log.

GREEN checkpoint: 218af5c. Full unit suite passed; subsequent refinements also passed:
124 tests in 26 suites, including 360 field-order/separator combinations. Final log:
/private/tmp/calendar-voice-postrefine-tests.log.

Optimized Mac Catalyst and physical iPhone Release builds passed:
/private/tmp/calendar-voice-final-mac.log and /private/tmp/calendar-voice-final-phone.log.
Both installed successfully. Deep strict signature verification passed. Phone
installation evidence: /private/tmp/calendar-voice-final-phone-install.json.

Live Mac checks:

- An intentionally reordered long instruction produced the correct title, Thursday
  date, 5:00–6:30 PM time block, Exercise category, Muir Tennis Courts, 30-minute
  reminder, and notes. Test drafts were closed without adding events.
- Typed submission stopped the microphone and retained the intended draft.
- The location command found one matching upcoming Thursday team practice:
  October 29, 2026, 5:00–5:45 PM. Its location was changed to Muir Tennis Courts.
  The value persisted after restarting the app. The other pickleball event that
  day retained Warren Tennis Courts.

## Limits

Live recognition accuracy with Allen's spoken audio and the iPhone microphone has
not been measured. The parser remains deterministic and is not a universal language
model. Missing or ambiguous details still need review in the draft. Cross-device
arrival of the calendar edit was not inspected on the physical phone.

The required Swift reviewer was invoked but its initial `swift build` gate cannot
review an Xcode-only project without Package.swift. Xcode builds, unit tests, local
diff review, and live app checks supplied validation instead.
