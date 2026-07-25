#!/usr/bin/env python3
"""Capture phone-sized screenshots of every Weekend Planner tab.

The test seeds SharedPreferences in its isolated browser context, loads the
real Nix-built Flutter web app, navigates through every bottom-navigation tab,
and fails on browser errors or missing UI.

Usage:
  python3 tool/web/smoke_test.py <url> <chromium-executable> [out-dir]
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys

from playwright.sync_api import sync_playwright


URL = sys.argv[1]
EXE = sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 else "/tmp/weekend-planner-web"
VIEW_W = int(os.environ.get("WEEKEND_VIEW_W", "414"))
VIEW_H = int(os.environ.get("WEEKEND_VIEW_H", "896"))
SCALE = float(os.environ.get("WEEKEND_SCALE", "2"))


def iso(value: dt.date) -> str:
    return value.isoformat()


def activity(
    activity_id: str,
    name: str,
    range_kind: str,
    first_date: dt.date,
    start_part: str | None,
    slot_length: int,
    needs_booking: bool,
    people: list[dict[str, str]],
    *,
    second_date: dt.date | None = None,
    recurring: bool = False,
    frequency: int | None = None,
    location: dict[str, object] | None = None,
    url: str | None = None,
) -> dict[str, object]:
    return {
        "id": activity_id,
        "name": name,
        "rangeKind": range_kind,
        "firstDate": iso(first_date),
        "secondDate": iso(second_date) if second_date else None,
        "startPart": start_part,
        "slotLength": slot_length,
        "needsBooking": needs_booking,
        "people": people,
        "isRecurring": recurring,
        "desiredFrequencyWeeks": frequency,
        "location": location,
        "url": url,
        "createdAt": f"{iso(first_date)}T10:00:00.000",
    }


today = dt.date(2026, 7, 25)
# Dart's firstRelevantFriday chooses the upcoming Friday on Mon–Thu and the
# current/previous Friday on Fri–Sun.
friday = today + dt.timedelta(days=4 - today.weekday())
next_week = friday + dt.timedelta(days=7)
spring_deadline = today + dt.timedelta(days=180)

elena = {"name": "Elena", "status": "confirmed"}
luca = {"name": "Luca", "status": "interested"}
marta = {"name": "Marta", "status": "possibly"}

database = {
    "schemaVersion": 1,
    "activities": [
        activity(
            "jazz",
            "Jazz at Magnolia",
            "exact",
            friday,
            "night",
            1,
            True,
            [elena, luca],
            location={
                "name": "Circolo Magnolia",
                "latitude": 45.4617,
                "longitude": 9.2786,
                "coordinateInput": "45.4617, 9.2786",
            },
            url="https://www.circolomagnolia.it/",
        ),
        activity(
            "trek",
            "Trekking in Val Masino",
            "within",
            spring_deadline,
            "morning",
            2,
            False,
            [luca, marta],
            location={
                "name": "Val Masino",
                "latitude": 46.215,
                "longitude": 9.638,
                "coordinateInput": "46.215, 9.638",
            },
        ),
        activity(
            "lunch",
            "Sunday lunch with friends",
            "anytime",
            today,
            "afternoon",
            1,
            False,
            [elena, luca, marta],
            recurring=True,
            frequency=4,
        ),
        activity(
            "cinema",
            "Cinema on a rainy evening",
            "between",
            today,
            "night",
            1,
            False,
            [elena],
            second_date=spring_deadline,
        ),
    ],
    "assignments": {
        f"{iso(friday)}#0": {"activityId": "jazz", "part": 1, "total": 1},
        f"{iso(friday)}#1": {"activityId": "trek", "part": 1, "total": 2},
        f"{iso(friday)}#2": {"activityId": "trek", "part": 2, "total": 2},
        f"{iso(friday)}#5": {"activityId": "lunch", "part": 1, "total": 1},
    },
    "cachedPeople": ["Elena", "Luca", "Marta"],
    "feeds": [
        {
            "id": "arci",
            "name": "ARCI Bellezza",
            "url": "https://arcibellezza.it/feed/",
            "lastChecked": f"{iso(today)}T10:00:00.000",
        },
        {
            "id": "magnolia",
            "name": "Circolo Magnolia",
            "url": "https://www.circolomagnolia.it/feed/",
            "lastChecked": f"{iso(today)}T10:00:00.000",
        },
    ],
    "inbox": [
        {
            "id": "arci-one",
            "feedId": "arci",
            "source": "ARCI Bellezza",
            "title": "Insieme è più bello",
            "link": "https://arcibellezza.it/",
            "eventDate": f"{iso(next_week)}T19:30:00.000",
            "startPart": "night",
            "slotLength": 1,
            "imported": False,
        },
        {
            "id": "magnolia-one",
            "feedId": "magnolia",
            "source": "Circolo Magnolia",
            "title": "Orchestre Tout Puissant Marcel Duchamp",
            "link": "https://www.circolomagnolia.it/",
            "eventDate": f"{iso(next_week + dt.timedelta(days=1))}T21:00:00.000",
            "startPart": "night",
            "slotLength": 1,
            "imported": False,
        },
        {
            "id": "arci-two",
            "feedId": "arci",
            "source": "ARCI Bellezza",
            "title": "La liberazione non è scontata",
            "link": "https://arcibellezza.it/",
            "eventDate": (
                f"{iso(next_week + dt.timedelta(days=9))}T18:00:00.000"
            ),
            "startPart": "night",
            "slotLength": 1,
            "imported": False,
        },
    ],
    "settings": {"calendarEnabled": False},
    "eventLog": [],
}

# shared_preferences_web JSON-encodes every value. PlannerStore stores its
# database as a JSON string, so the localStorage representation is encoded
# twice: first the database, then the preference string.
database_json = json.dumps(database, ensure_ascii=False, separators=(",", ":"))
storage_value = json.dumps(database_json, ensure_ascii=False)
init_script = (
    "const fixedTime = new Date('2026-07-25T10:00:00.000Z').valueOf();"
    "const OriginalDate = Date;"
    "class FixedDate extends OriginalDate {"
    "constructor(...args) {"
    "if (args.length === 0) { super(fixedTime); } else { super(...args); }"
    "}"
    "static now() { return fixedTime; }"
    "}"
    "Object.setPrototypeOf(FixedDate, OriginalDate);"
    "window.Date = FixedDate;"
    "window.localStorage.setItem("
    + json.dumps("flutter.weekend_planner_state_v1")
    + ","
    + json.dumps(storage_value, ensure_ascii=False)
    + ");"
)

os.makedirs(OUT, exist_ok=True)
errors: list[str] = []
ok = True

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        executable_path=EXE,
        headless=True,
        args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
    )
    context = browser.new_context(
        viewport={"width": VIEW_W, "height": VIEW_H},
        device_scale_factor=SCALE,
        timezone_id="Europe/Rome",
    )
    context.add_init_script(script=init_script)
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(f"pageerror: {error}"))
    page.goto(URL, wait_until="load", timeout=60_000)
    page.wait_for_timeout(9_000)

    # Enable Flutter's semantics tree. A JS click bypasses its off-screen guard.
    page.evaluate(
        "() => document.querySelector('flt-semantics-placeholder')?.click()"
    )
    page.wait_for_timeout(2_500)

    def semantics_labels() -> list[str]:
        return page.eval_on_selector_all(
            "flt-semantics[aria-label]",
            "elements => elements.map(e => e.getAttribute('aria-label'))"
            ".filter(Boolean)",
        )

    def tab(label: str):
        for element in page.query_selector_all("flt-semantics[aria-label]"):
            value = element.get_attribute("aria-label") or ""
            if value == label or value.endswith(f"\n{label}"):
                return element
        return None

    labels = semantics_labels()
    print("semantics labels:", labels)
    for label in ("Weekends", "Activities", "People", "Inbox"):
        if tab(label) is None:
            print(f"FAIL: '{label}' was not exposed by Flutter semantics")
            ok = False

    for label in ("Weekends", "Activities", "People", "Inbox"):
        element = tab(label)
        if element is None:
            continue
        element.click(force=True)
        page.mouse.move(1, 1)
        page.wait_for_timeout(1_500)
        target = os.path.join(OUT, f"tab_{label.lower()}.png")
        page.screenshot(path=target)
        print("SCREENSHOT:", target)

    context.close()
    browser.close()

if errors:
    print("PAGE ERRORS:", errors)
    ok = False

for label in ("weekends", "activities", "people", "inbox"):
    path = os.path.join(OUT, f"tab_{label}.png")
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        print("FAIL: screenshot missing:", path)
        ok = False

print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
