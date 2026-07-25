# Weekend Planner

A local-first Flutter planner for the weekends ahead. It is based on the
supplied Claude Design mockup and runs on Android and the web.

## Screenshots

<p align="center">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/latest/download/weekend-planner-web-weekends.png" alt="Upcoming weekends" width="210">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/latest/download/weekend-planner-web-activities.png" alt="Activity ideas" width="210">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/latest/download/weekend-planner-web-people.png" alt="People cache" width="210">
  <img src="https://github.com/aleclearmind/weekend-planner/releases/latest/download/weekend-planner-web-inbox.png" alt="RSS inbox" width="210">
</p>

## What it does

- Shows Friday night plus the morning, afternoon, and night slots for Saturday
  and Sunday.
- Assigns compatible activity ideas across one or more consecutive slots.
- Keeps a read-only activity view with every past and upcoming assignment.
- Supports recurring activities with an optional desired frequency and
  overdue warnings; recurrence never creates assignments automatically.
- Supports `anytime`, `within`, `between`, and `exact` activity date
  constraints. Dates are directly editable as `YYYY-MM-DD`, with quick
  deadlines for one week, one to three months, one year, and the next season.
- Lets activities start at any time, or only in the morning, afternoon, or
  night.
- Tracks booking requirements and filters ideas that need booking.
- Caches participant names locally and tracks possibly/interested/confirmed
  status. Cached people can be renamed or removed.
- Stores optional activity URLs and named locations. Coordinates accept
  latitude/longitude pairs, `geo:` URLs, and full Open Location Codes; pinned
  locations open in OsmAnd.
- Adds RSS or Atom feeds and imports feed entries as editable activities.
- Normalizes all-caps RSS titles, carries the entry URL into the activity,
  opens the editor immediately after import, and filters the inbox by source.
  The compact inbox groups entries by week and decodes feed bytes according to
  their declared encoding.
- Discovers feeds automatically when a normal HTML page contains a standard
  `<link rel="alternate" type="application/rss+xml">` or Atom equivalent.
- Persists activities, assignments, people, feeds, the inbox, settings, and a
  detailed diagnostic event log on-device.
- Exports the complete versioned database as JSON from Settings.
- Optionally reads the Android calendar and shows the first overlapping event
  beside otherwise available weekend slots. Calendar contents stay outside
  the planner database and its exports.

The database schema is currently version `1`. The stored document carries that
version explicitly, and loading always runs through the migration pipeline.
Schema versions are only incremented when a corresponding one-step migration
has been added.

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
same-origin `/rss-proxy` endpoint. The proxy follows RSS/Atom autodiscovery,
accepts only public HTTP(S) destinations, blocks local/private addresses,
uses a browser user agent, limits responses to 5 MB, and binds to `127.0.0.1`.
HTTP status, response metadata, discovery decisions, exceptions, and stack
traces are available in Settings → Event log.

The `web-smoke` derivation loads the Nix-built site in Playwright, navigates
all four tabs, and emits deterministic phone-sized screenshots. The individual
`web-screenshot-*` packages expose stable release artifact names, while the
README follows them through GitHub's `releases/latest/download` URLs.

The ARM64 artifact is a release APK signed with Flutter's generated debug key,
which is suitable for direct installation and testing but not app-store
distribution.
