#!/usr/bin/env python3
"""Adds posters, press and audience ratings and running times to data/extras.json,
from AlloCiné's public weekly release pages and film pages.

  python3 scripts/allocine.py agenda 2026-12-02 2026-12-09   # those weeks
  python3 scripts/allocine.py agenda --missing 8             # the 8 weeks with most gaps
  python3 scripts/allocine.py durations 120                  # running times for up to 120 films
  python3 scripts/allocine.py theaters                       # session times at the cinemas in data/theaters.json

data/showtimes.json: {film id: {"week", "updatedAt", "cinemas": [{"name", "address",
                               "times": {"YYYY-MM-DD": ["HH:MM"]}}]}}
  Each cinema's public page lists that day's sessions (and some for the next day). Earlier
  days are dropped, today's list is replaced, later days already collected are kept.

data/extras.json: {film id: {"ac": AlloCiné id, "poster": url, "press": 3.8, "spect": 4.0,
                              "duration": 157, "checked": "YYYY-MM-DD"}}
Requests are spaced out (1.5 s) and use AlloCiné's ordinary public pages.
"""
import datetime
import difflib
import html
import json
import pathlib
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
EXTRAS = DATA / "extras.json"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
PAUSE = 1.5


def slug(s):
    s = unicodedata.normalize("NFD", str(s).lower())
    s = "".join(ch for ch in s if not 0x0300 <= ord(ch) <= 0x036F)
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def get(url, tries=5):
    """Fetches a public page, trying up to 5 times (2, 4, 8, 16 s apart)."""
    last = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "fr-FR,fr;q=0.9"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as ex:
            if ex.code in (403, 404, 410):
                raise
            last = ex
        except Exception as ex:
            last = ex
        time.sleep(2 ** (attempt + 1))
    raise last


def text(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def note(card, label):
    m = re.search(label + r"\s*</span>.*?stareval-note[^>]*>\s*([\d,]+)\s*<", card, re.S)
    return float(m.group(1).replace(",", ".")) if m else None


def minutes(s):
    m = re.search(r"(\d+)h\s*(\d+)\s*min", s)
    if m:
        return int(m.group(1)) * 60 + int(m.group(2))
    m = re.search(r"\b(\d{2,3})\s*min\b", s)
    return int(m.group(1)) if m else None


def parse_agenda(page):
    cards = []
    for part in page.split('<li class="mdl">')[1:]:
        m = re.search(r'fichefilm_gen_cfilm=(\d+)\.html"[^>]*>(.*?)</a>', part, re.S)
        if not m:
            continue
        poster = None
        for p in re.findall(r'(?:data-src|src)="(https://[^"]*acsta\.net/[^"]+)"', part):
            if "empty" not in p and not p.endswith(".svg"):
                poster = p
                break
        orig = re.search(r'Titre original\s*</span>\s*<span[^>]*>(.*?)</span>', part, re.S)
        info = re.search(r'meta-body-info">(.*?)</div>', part, re.S)
        cards.append({
            "ac": int(m.group(1)), "title": text(m.group(2)), "orig": text(orig.group(1)) if orig else None,
            "poster": poster, "press": note(part, "Presse"), "spect": note(part, "Spectateurs"),
            "duration": minutes(text(info.group(1))) if info else None,
        })
    return cards


def week_films(week):
    path = DATA / "weeks" / f"{week}.json"
    if not path.exists():
        return []
    doc = json.loads(path.read_text(encoding="utf-8"))
    out = []
    for r in doc.get("films", []):
        if isinstance(r, list) and len(r) > 1:
            out.append((f"{r[0]}_{slug(r[1])}", str(r[1]), str(r[8]) if len(r) > 8 and r[8] else None))
    return out


def match(card, films):
    k = slug(card["title"])
    ko = slug(card["orig"]) if card["orig"] else None
    for fid, title, orig in films:
        if slug(title) == k or (ko and (slug(title) == ko or (orig and slug(orig) == ko))):
            return fid
    names = {slug(t): fid for fid, t, _ in films}
    close = difflib.get_close_matches(k, list(names), n=1, cutoff=0.86)
    return names[close[0]] if close else None


def load():
    try:
        return json.loads(EXTRAS.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save(extras):
    EXTRAS.write_text(json.dumps(dict(sorted(extras.items())), ensure_ascii=False, indent=1), encoding="utf-8")


def agenda(weeks):
    extras = load()
    today = datetime.date.today().isoformat()
    for w in weeks:
        films = week_films(w)
        if not films:
            continue
        found = 0
        for page_no in (1, 2, 3):
            url = f"https://www.allocine.fr/film/agenda/sem-{w}/" + (f"?page={page_no}" if page_no > 1 else "")
            try:
                page = get(url)
            except Exception as e:
                print(f"{w}: {e}", file=sys.stderr)
                break
            time.sleep(PAUSE)
            cards = parse_agenda(page)
            for c in cards:
                fid = match(c, films)
                if not fid:
                    continue
                e = extras.get(fid, {})
                e["ac"] = c["ac"]
                for key in ("poster", "press", "spect", "duration"):
                    if c[key] is not None:
                        e[key] = c[key]
                e["checked"] = today
                extras[fid] = e
                found += 1
            if f"?page={page_no + 1}" not in page:
                break
        print(f"{w}: {found}/{len(films)} films matched")
        save(extras)


def missing_weeks(n):
    extras = load()
    gaps = []
    for path in sorted((DATA / "weeks").glob("*.json")):
        films = week_films(path.stem)
        missing = sum(1 for fid, _, _ in films if not extras.get(fid, {}).get("poster"))
        if missing:
            gaps.append((missing, path.stem))
    gaps.sort(key=lambda g: (-g[0], g[1]), reverse=False)
    return [w for _, w in gaps[:n]]


def durations(limit):
    extras = load()
    todo = [fid for fid, e in extras.items() if e.get("ac") and not e.get("duration") and not e.get("noDuration")]
    todo.sort(reverse=True)  # most recent first
    done = 0
    for fid in todo[:limit]:
        e = extras[fid]
        try:
            page = get(f"https://www.allocine.fr/film/fichefilm_gen_cfilm={e['ac']}.html")
        except Exception as ex:
            print(f"{fid}: {ex}", file=sys.stderr)
            time.sleep(PAUSE)
            continue
        time.sleep(PAUSE)
        info = re.search(r'meta-body-info">(.*?)</div>', page, re.S)
        d = minutes(text(info.group(1))) if info else None
        if d and 30 <= d <= 400:
            e["duration"] = d
            done += 1
        else:
            e["noDuration"] = True
        if not e.get("poster"):
            m = re.search(r'thumbnail-img[^>]*src="(https://[^"]*acsta\.net/[^"]+)"', page)
            if m and "empty" not in m.group(1):
                e["poster"] = m.group(1)
        if done % 20 == 0:
            save(extras)
    save(extras)
    print(f"running times found for {done} of {min(limit, len(todo))} films")


SHOWTIMES = DATA / "showtimes.json"
THEATERS = DATA / "theaters.json"


def parse_theater(page):
    """[(AlloCiné film id, title, {"YYYY-MM-DD": {"HH:MM"}})] from a cinema's public page."""
    out = []
    for part in page.split('class="card entity-card entity-card-list movie-card-theater')[1:]:
        m = re.search(r'fichefilm_gen_cfilm=(\d+)\.html"[^>]*>(.*?)</a>', part, re.S)
        if not m:
            continue
        times = {}
        for stamp in re.findall(r'data-showtime-time="(\d{4}-\d\d-\d\d)T(\d\d:\d\d)', part):
            times.setdefault(stamp[0], set()).add(stamp[1])
        if times:
            out.append((int(m.group(1)), text(m.group(2)), times))
    return out


def recent_films(days=120):
    """Films released in the last `days` days or coming soon, newest first."""
    start = (datetime.date.today() - datetime.timedelta(days=days)).isoformat()
    films = []
    for path in sorted((DATA / "weeks").glob("*.json"), reverse=True):
        if path.stem >= start:
            films += [(fid, title, orig, path.stem) for fid, title, orig in week_films(path.stem)]
    return films


def theaters():
    extras = load()
    films = recent_films(days=800)          # AlloCiné ids are exact, so any release counts
    week_of = {fid: w for fid, _, _, w in films}
    soon = (datetime.date.today() - datetime.timedelta(days=120)).isoformat()
    by_ac = {}
    for fid, e in sorted(extras.items()):
        if e.get("ac") and fid in week_of:
            by_ac[int(e["ac"])] = fid  # sorted, so the newest release wins
    by_slug = {}
    for fid, title, orig, w in reversed(films):
        if w < soon:                        # titles only for recent releases (classics share titles)
            continue
        by_slug[slug(title)] = fid
        if orig:
            by_slug.setdefault(slug(orig), fid)
    addresses = {c["name"]: c.get("address", "") for c in json.loads((DATA / "cinemas.json").read_text(encoding="utf-8"))}
    try:
        shows = json.loads(SHOWTIMES.read_text(encoding="utf-8"))
    except FileNotFoundError:
        shows = {}

    today = datetime.date.today().isoformat()
    now = datetime.datetime.now().astimezone().isoformat(timespec="minutes")
    scraped = {}   # (film id, cinema) -> {day: set}
    done, failed, unmatched = [], [], set()
    for t in json.loads(THEATERS.read_text(encoding="utf-8")):
        name = t["name"]
        got = False
        for code in t["codes"]:
            try:
                page = get(f"https://www.allocine.fr/seance/salle_gen_csalle={code}.html")
            except Exception as ex:
                print(f"{name} ({code}): {ex}", file=sys.stderr)
                time.sleep(PAUSE)
                continue
            time.sleep(PAUSE)
            got = True
            for ac, title, times in parse_theater(page):
                fid = by_ac.get(ac) or by_slug.get(slug(title))
                if not fid:
                    unmatched.add(title)
                    continue
                slot = scraped.setdefault((fid, name), {})
                for day, hours in times.items():
                    slot.setdefault(day, set()).update(hours)
        (done if got else failed).append(name)

    # merge: drop past days; for the cinemas just read, today's list is replaced
    # and later days are added to what was already collected.
    fresh = set(done)
    for fid in list(shows):
        kept = []
        for c in shows[fid].get("cinemas") or []:
            times = {d: v for d, v in (c.get("times") or {}).items() if d >= today}
            if c.get("name") in fresh:
                times.pop(today, None)
            if times:
                c["times"] = times
                kept.append(c)
        if kept:
            shows[fid]["cinemas"] = kept
        else:
            del shows[fid]
    for (fid, name), times in scraped.items():
        entry = shows.setdefault(fid, {"week": week_of.get(fid), "cinemas": []})
        entry["week"] = week_of.get(fid, entry.get("week"))
        entry["updatedAt"] = now
        entry.pop("note", None)
        cinema = next((c for c in entry["cinemas"] if c.get("name") == name), None)
        if cinema is None:
            t = next(x for x in json.loads(THEATERS.read_text(encoding="utf-8")) if x["name"] == name)
            cinema = {"name": name, "address": t.get("address") or addresses.get(name, ""), "times": {}}
            entry["cinemas"].append(cinema)
        for day, hours in times.items():
            if day < today:
                continue
            cinema["times"][day] = sorted(set(cinema["times"].get(day, [])) | hours)
    for entry in shows.values():
        entry["cinemas"].sort(key=lambda c: c.get("name", ""))
        for c in entry["cinemas"]:
            c["times"] = dict(sorted(c["times"].items()))
    SHOWTIMES.write_text(json.dumps(dict(sorted(shows.items())), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    sessions = sum(len(v) for e in shows.values() for c in e["cinemas"] for v in c["times"].values())
    print(f"{len(done)} cinemas read, {len(failed)} failed {failed if failed else ''}".rstrip())
    print(f"{len(shows)} films with session times, {sessions} sessions in all")
    if unmatched:
        print(f"{len(unmatched)} titles not in the release list (older films, events): "
              + ", ".join(sorted(unmatched)[:25]) + ("…" if len(unmatched) > 25 else ""))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "agenda":
        if len(sys.argv) > 2 and sys.argv[2] == "--missing":
            agenda(missing_weeks(int(sys.argv[3]) if len(sys.argv) > 3 else 8))
        else:
            agenda(sys.argv[2:])
    elif cmd == "durations":
        durations(int(sys.argv[2]) if len(sys.argv) > 2 else 100)
    elif cmd == "theaters":
        theaters()
    else:
        print(__doc__)
