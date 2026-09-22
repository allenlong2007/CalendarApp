# CalendarApp

A native iOS/macOS calendar app that replaced a web-app calendar with one backed by real iCloud Calendar data — home screen widgets, Lock Screen widgets, and Siri support that a PWA could never provide.

<p align="center">
  <img src="docs/screenshots/01_month.png" width="230" alt="Month view with events" />
  <img src="docs/screenshots/02_week.png" width="230" alt="Week view with hourly grid" />
  <img src="docs/screenshots/03_agenda.png" width="230" alt="Agenda list view" />
</p>

## Overview

I originally built my calendar as a Cloudflare Worker-hosted PWA, but a web app fundamentally can't offer OS-level integration — no home screen widgets, no Lock Screen glance, no Siri. So I rewrote it natively: real events live in **EventKit** (genuine iCloud Calendar data, not a custom database), which means they sync via iCloud for free and show up in Apple's own Calendar app and widgets automatically. App-only concepts EventKit has no room for — a separate day-planner, completion tracking, saved addresses, reusable templates — live alongside it in **SwiftData** with CloudKit sync.

## Features

- **Month / Week / Day / Agenda views** plus a full event editor with location search (MapKit) and color-coded categories
- **Planner** — a separate scratch-planning surface (SwiftData-backed) for drafting a week before committing events to the real calendar, with duplicate-to-days and quick-add templates
- **Completion tracking & undo** — mark events done, with a full undo toast for deletes and status changes
- **Home Screen & Lock Screen widgets** (WidgetKit) — Next Event and Today's Agenda
- **Siri / App Intents** — create an event or query your next event by voice, no app launch required
- **Mac Catalyst support** — same codebase runs as a full Mac app, including Calendar permission handling for Catalyst's different TCC behavior
- **One-time import** from the original PWA's export format, so switching over doesn't lose history
- Optional **Gmail import** scaffold (OAuth PKCE + Gmail API + on-device event extraction) — gated behind a user-supplied Google Cloud client ID, off by default

## Tech Stack

Swift, SwiftUI, EventKit, SwiftData + CloudKit, WidgetKit, App Intents (Siri), MapKit, Mac Catalyst, XcodeGen.

## How It Works

Two data layers, deliberately kept separate:

- **EventKit** owns anything that's a "real" calendar event — it's the source of truth, so it syncs across every Apple device and calendar app for free, with no custom sync code to write or maintain.
- **SwiftData** (with `cloudKitDatabase: .automatic`) owns everything EventKit has no concept of: Planner scratch events before they're committed, completion status, saved addresses, and quick-add templates.

Widgets and Siri intents both read through the same `EventStoreManager` the main app uses, so there's one code path for "what does the user's calendar look like right now" regardless of surface.

## Setup

```bash
git clone https://github.com/allenlong2007/CalendarApp.git
cd CalendarApp
xcodegen generate
open CalendarApp.xcodeproj
```

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode 16+. Select the `CalendarApp` scheme, grant Calendar access on first launch, and run. Gmail import stays disabled until you supply your own OAuth client ID in `CalendarApp/Gmail/GoogleOAuthConfig.swift` (see the comment there — iOS OAuth clients use PKCE, so there's no secret to configure).

## Status

Complete and in daily personal use, running via Xcode on both iPhone Simulator and as a Mac Catalyst app. Not distributed on the App Store (personal-use project).
