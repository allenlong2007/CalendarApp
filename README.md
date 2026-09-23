# CalendarApp

A calendar app I built for myself, for iPhone and Mac. It replaced a website version I'd made earlier, so I could get real widgets, lock screen info, and Siri support — things a website just can't do.

<p align="center">
  <img src="docs/screenshots/01_month.png" width="230" alt="Month view with events" />
  <img src="docs/screenshots/02_week.png" width="230" alt="Week view with hourly grid" />
  <img src="docs/screenshots/03_agenda.png" width="230" alt="Agenda list view" />
</p>

## What it does

I originally built my calendar as a website. That worked fine, but a website can't show up as a home screen widget, can't put anything on your lock screen, and can't talk to Siri. So I rebuilt it as a real app.

It uses Apple's own Calendar system underneath, so any event you make actually syncs through iCloud like normal — it shows up in the regular Calendar app too. On top of that, I added a separate "Planner" section for roughing out a plan for the week before turning it into real events, plus quick templates, saved addresses, and undo for anything you delete.

## Features

- Month, Week, Day, and Agenda views, with a full event editor and location search
- Planner — a scratchpad for planning your week before committing to real events
- Mark things done, with undo for deletes and changes
- Home Screen and Lock Screen widgets showing your next event or today's schedule
- Ask Siri to create an event or tell you what's next
- Also works as a real Mac app, not just on iPhone
- One-time import from my old website calendar, so I didn't lose anything switching over
- Optional Gmail import to catch events buried in email (off by default — needs your own Google account setup)

## Built with

Swift and SwiftUI, EventKit (Apple's built-in calendar system), SwiftData with iCloud sync, WidgetKit, Siri Shortcuts, MapKit, and XcodeGen.

## How it's put together

Real calendar events live in Apple's own EventKit system, so they sync automatically and show up in Apple's Calendar app too — no extra syncing code to write or maintain. Everything the app has that a normal calendar doesn't — the Planner, marking things done, saved addresses, templates — lives in its own local database (SwiftData) that also syncs through iCloud.

Widgets and Siri both read from that same calendar data, so however you're checking your schedule, it's all coming from the same place.

## Running it yourself

```bash
git clone https://github.com/allenlong2007/CalendarApp.git
cd CalendarApp
xcodegen generate
open CalendarApp.xcodeproj
```

You'll need [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode. Pick the CalendarApp scheme, allow calendar access when it asks, and run. Gmail import stays off until you add your own Google API key in `CalendarApp/Gmail/GoogleOAuthConfig.swift`.

## Status

Done, and I use it every day on both my iPhone and Mac. Not on the App Store — just for my own use.
