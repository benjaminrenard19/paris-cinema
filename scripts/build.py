#!/usr/bin/env python3
"""Builds data/paris-cinema.json (the feed the iPhone app downloads) from:

  data/weeks/<Wednesday>.json   one file per French cinema week (Wednesday to Tuesday)
  data/details.json             {film id: {"synopsis", "producers", "cast", "checkedAt"}}
  data/showtimes.json           {film id: {"week", "updatedAt", "cinemas": [{"name", "address", "times": {"YYYY-MM-DD": ["HH:MM"]}}]}}
  data/cinemas.json             the Paris cinemas shown on the map
  data/posters.json             {film id: official poster image URL (AlloCiné)}
  data/extras.json              {film id: {"ac", "poster", "press", "spect", "duration"}} from scripts/allocine.py

It also copies the feed into ParisCinema/paris-cinema.json so a fresh build of the
app already contains every film. Run it after changing anything in data/:

  python3 scripts/build.py

A film in a week file is an array:
  [date, French title, category, genres, origin, release size, director, cast,
   original title (or year for re-releases), note, synopsis, producers]
Category: B A C D T V M E R O or its full label. Size: W M L X or its full label.
"""
import datetime
import hashlib
import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = DATA / "paris-cinema.json"
APP_COPY = ROOT / "ParisCinema" / "paris-cinema.json"

CATS = [("B", "Blockbuster"), ("A", "Animation & family"), ("C", "Comedy"), ("D", "Drama"),
        ("T", "Thriller / action / sci-fi"), ("V", "Documentary"), ("M", "Biopic & music"),
        ("E", "Event screening"), ("R", "Re-release / classic"), ("O", "Other")]
SIZES = [("W", "Wide"), ("M", "Mid"), ("L", "Limited"), ("X", "One-off / event")]
DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def code(value, table, default):
    v = str(value or "").strip()
    for c, label in table:
        if v == c or v.lower() == label.lower():
            return c
    return default


def text(v):
    return str(v).strip() if v not in (None, "") else None


def slug(s):
    """Same as the Claude page: lower case, accents removed, other characters -> '-'."""
    s = unicodedata.normalize("NFD", str(s).lower())
    s = "".join(ch for ch in s if not 0x0300 <= ord(ch) <= 0x036F)
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def week_of(day):
    d = datetime.date.fromisoformat(day)
    js_weekday = (d.weekday() + 1) % 7  # Sunday = 0, like JavaScript
    return (d - datetime.timedelta(days=(js_weekday + 4) % 7)).isoformat()


def load(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def main():
    details = load(DATA / "details.json", {})
    showtimes = load(DATA / "showtimes.json", {})
    cinemas = load(DATA / "cinemas.json", [])
    posters = load(DATA / "posters.json", {})
    extras = load(DATA / "extras.json", {})
    films, seen_ids, problems = [], set(), []

    for path in sorted((DATA / "weeks").glob("*.json")):
        doc = load(path, {})
        week = doc.get("week") or path.stem
        if week_of(week) != week:
            problems.append(f"{path.name}: {week} is not a Wednesday")
            continue
        for row in doc.get("films", []):
            if not isinstance(row, list) or len(row) < 2 or not DAY.match(str(row[0])) or not row[1]:
                problems.append(f"{path.name}: skipped {row!r:.80}")
                continue
            row = list(row) + [None] * (12 - len(row))
            date, title = str(row[0]), str(row[1]).strip()
            fid = f"{date}_{slug(title)}"
            if fid in seen_ids:
                continue
            seen_ids.add(fid)
            f = {
                "id": fid, "week": week, "date": date, "title": title,
                "cat": code(row[2], CATS, "O"), "genre": text(row[3]), "origin": text(row[4]),
                "size": code(row[5], SIZES, "L"), "dir": text(row[6]), "cast": text(row[7]),
                "orig": text(row[8]), "note": text(row[9]), "syn": text(row[10]), "prod": text(row[11]),
            }
            d = details.get(fid) or {}
            f["syn"] = f["syn"] or text(d.get("synopsis"))
            f["prod"] = f["prod"] or text(d.get("producers"))
            cast = text(d.get("cast"))
            if cast and len(cast) > len(f["cast"] or ""):
                f["cast"] = cast
            x = extras.get(fid) or {}
            poster = text(x.get("poster")) or text(posters.get(fid))
            if poster and "empty" not in poster:
                f["poster"] = poster
            for key in ("press", "spect"):
                if isinstance(x.get(key), (int, float)) and 0 < x[key] <= 5:
                    f[key] = round(float(x[key]), 1)
            if isinstance(x.get("duration"), int) and 30 <= x["duration"] <= 400:
                f["duration"] = x["duration"]
            if x.get("ac"):
                f["ac"] = x["ac"]
            films.append(f)

    body = {"format": "paris-cinema-weeks/1", "films": films, "showtimes": showtimes, "cinemas": cinemas}
    digest = hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    old = load(OUT, {})
    if old.get("digest") == digest and old.get("exportedAt"):
        stamp = old["exportedAt"]
    else:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    feed = {"format": body["format"], "exportedAt": stamp, "digest": digest, "films": films,
            "showtimes": showtimes, "cinemas": cinemas}
    raw = json.dumps(feed, ensure_ascii=False, separators=(",", ":"))
    OUT.write_text(raw, encoding="utf-8")
    APP_COPY.write_text(raw, encoding="utf-8")

    weeks = sorted({f["week"] for f in films})
    print(f"{len(films)} films in {len(weeks)} weeks ({weeks[0]} to {weeks[-1]}), "
          f"{len(details)} detail records, {sum(1 for f in films if f.get('poster'))} posters, "
          f"{sum(1 for f in films if f.get('press') or f.get('spect'))} rated, "
          f"{sum(1 for f in films if f.get('duration'))} running times, "
          f"{len(showtimes)} showtime lists. exportedAt {stamp}")
    for p in problems:
        print("warning:", p, file=sys.stderr)


if __name__ == "__main__":
    main()
