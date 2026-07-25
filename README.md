# Weekend Planner

A local-first Flutter planner for the weeks ahead. It is based on the supplied
Claude Design mockup and runs on Android and the web.

## Screenshots

<p align="center">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/download/latest/weekend-planner-web-weekends.png" alt="Upcoming weekends" width="210">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/download/latest/weekend-planner-web-activities.png" alt="Activity ideas" width="210">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/download/latest/weekend-planner-web-people.png" alt="People cache" width="210">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/download/latest/weekend-planner-web-inbox.png" alt="Feed inbox" width="210">
</p>

## What it does

- Starts with Friday night plus Saturday and Sunday, and lets every
  morning/afternoon/night slot from Monday through Sunday be enabled or
  disabled in Settings. Days that have already passed are hidden.
- Assigns compatible activity ideas across one or more consecutive slots.
- Keeps a read-only activity view with every past and upcoming assignment.
- Supports recurring activities with an optional desired frequency, overdue
  warnings, and a manual counter reset; recurrence never creates assignments
  automatically.
- Supports `anytime`, `within`, `between`, and `exact` activity date
  constraints. Dates are directly editable as `YYYY-MM-DD`, with quick
  deadlines for one week, one to three months, one year, and the next season.
  New activities default to `anytime`.
- Lets activities optionally require any day of the week, a time of day, or
  both, such as Friday night or Wednesday night.
- Tracks booking requirements and filters ideas that need booking.
- Caches participant names locally and tracks possibly/interested/confirmed
  status. Cached people can be added directly from the People tab, renamed, or
  removed.
- Stores optional activity URLs and named locations. Coordinates accept
  latitude/longitude pairs, `geo:` URLs, and full Open Location Codes; pinned
  locations open in OsmAnd.
- Adds RSS, Atom, and iCalendar (`.ics`) feeds and imports entries as editable
  activities. HTML autodiscovery also recognizes linked calendar feeds.
- Normalizes all-caps RSS titles, carries the entry URL into the activity,
  opens the editor immediately after import, and filters the inbox by source.
  The compact inbox groups entries by week and decodes feed bytes according to
  their declared encoding.
- Discovers feeds automatically when a normal HTML page contains a standard
  `<link rel="alternate">` for RSS, Atom, or iCalendar.
- Checks stale feeds every 30 minutes while the app is active and whenever the
  app resumes, while keeping manual refresh available.
- Persists activities, assignments, people, feeds, the inbox, settings, and a
  detailed diagnostic event log on-device.
- Exports the complete versioned database as JSON from Settings.
- Optionally reads selected Android calendars and shows the first overlapping
  event beside otherwise available slots. Calendar contents stay outside the
  planner database and its exports.

The database schema is currently version `3`. The stored document carries that
version explicitly, and loading always runs through the migration pipeline.
Schema v1 and v2 remain untouched under their original storage keys. The
v2→v3 migration converts numeric weekend assignment positions to stable
date/time keys, records configurable weekly slots, feed kinds, and Android
calendar filters.

CalDAV synchronization is deliberately left for a later iteration.

## Run and test

The flake provides Flutter, Java, Gradle, and the Android SDK:

```sh
nix develop path:.
flutter test
flutter analyze
```

Build both release artifacts reproducibly:

```sh
nix build path:.#web -o result-web
nix build path:.#apk -o result-apk
nix build path:.#web-smoke -o result-screenshots
```

Serve the Nix-built web app on port 8003:

```sh
nix run path:. -- 8003
```

The server in `tool/web/serve.py` serves the static Flutter output and a
same-origin `/feed-proxy` endpoint. The proxy follows RSS/Atom/iCalendar
autodiscovery, accepts only public HTTP(S) destinations, blocks local/private
addresses, uses a browser user agent, limits responses to 5 MB, and binds to
`127.0.0.1`. HTTP status, response metadata, discovery decisions, exceptions,
and stack traces are available in Settings → Event log.

The `web-smoke` derivation loads the Nix-built site in Playwright, navigates
all four tabs, and emits deterministic phone-sized screenshots. The individual
`web-screenshot-*` packages expose stable release artifact names, while the
README follows the rolling `latest` release tag.

The ARM64 artifact is a release APK signed with Flutter's generated debug key,
which is suitable for direct installation and testing but not app-store
distribution.
