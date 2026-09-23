# CalendarApp

My own calendar app, for iPhone and Mac. Used to be a website, but I rebuilt it natively so it could actually do widgets, lock screen info, and Siri.

<p align="center">
  <img src="docs/screenshots/01_month.png" width="230" alt="Month view with events" />
  <img src="docs/screenshots/02_week.png" width="230" alt="Week view with hourly grid" />
  <img src="docs/screenshots/03_agenda.png" width="230" alt="Agenda list view" />
</p>

## Why I rebuilt it

I'd made my calendar as a website first, and it worked fine, but a website can't sit on your home screen as a widget, can't show up on your lock screen, and can't talk to Siri — that stuff is OS-level only. So I redid it as a real app.

Under the hood it uses Apple's own calendar system, so anything you add actually syncs through iCloud and shows up in the regular Calendar app too. I also added a "Planner" — basically a scratchpad for sketching out a week before it becomes real events — plus quick templates, saved addresses, and undo for when you delete something by accident.

## What it can do

- Month, Week, Day, and Agenda views, plus a full event editor with location search
- Planner mode for roughing out a week before it's official
- Mark things done, with undo for deletes and changes
- Widgets for your next event or the day's schedule, home screen and lock screen
- Ask Siri to add an event or tell you what's next
- Runs as an actual Mac app too, not just iPhone
- Pulled in everything from my old website calendar so I didn't lose history switching over
- Gmail import if you want it (off by default, needs your own Google setup)

## Built with

Swift, SwiftUI, EventKit, SwiftData with iCloud sync, WidgetKit, Siri Shortcuts, MapKit, XcodeGen.

## How it works

Real events live in EventKit, Apple's own calendar system, so they sync for free and show up in the actual Calendar app too — no extra syncing code on my end. Everything else the app does that a normal calendar can't — Planner, marking things done, saved addresses, templates — sits in its own local database that syncs through iCloud separately.

Widgets and Siri both pull from that same data, so however you're checking your schedule, it's all coming from one place.

## Running it

```bash
git clone https://github.com/allenlong2007/CalendarApp.git
cd CalendarApp
xcodegen generate
open CalendarApp.xcodeproj
```

Needs [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode. Pick the CalendarApp scheme, let it have calendar access, and run it. Gmail import stays off until you drop your own Google API key into `CalendarApp/Gmail/GoogleOAuthConfig.swift`.

## Status

I use it every day, iPhone and Mac both. Never put it on the App Store — it's just for me.
