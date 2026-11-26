#!/usr/bin/env python3
"""Session times from the cinemas' own websites, merged into data/showtimes.json.

  python3 scripts/sessions.py sites         # all of the sources below
  python3 scripts/sessions.py ugc           # UGC's Paris cinemas (ugc.fr), every published day
  python3 scripts/sessions.py grandaction   # Le Grand Action (legrandaction.com)
  python3 scripts/sessions.py balzac        # Le Balzac (cinemabalzac.com)
  python3 scripts/sessions.py grandrex      # Le Grand Rex (legrandrex.com)
  python3 scripts/sessions.py studio28      # Studio 28 (cinema-studio28.fr)

Cinemas publish their programme a week at a time (Wednesday to Tuesday), usually on the
Monday or Tuesday before, so these sources reach next Tuesday, plus special screenings
further ahead. AlloCiné's cinema pages (scripts/allocine.py theaters) add today and tomorrow
for every other cinema. Le Louxor, Max Linder, Luminor, Le Champo, Reflet Médicis, Escurial,
Saint-André des Arts, Christine, Les 7 Parnassiens, Elysées Lincoln, Pathé and mk2 load their
times in the browser from booking services rather than in the page, so they come from AlloCiné.

Each day a source has read for a cinema replaces what was stored for that cinema and day;
days it didn't read are kept; past days are dropped. Requests are spaced out (1.5 s).
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
import urllib.request
import zoneinfo

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SHOWTIMES = DATA / "showtimes.json"
CINEMAS = DATA / "cinemas.json"
TITLES = DATA / "site-titles.json"   # film ids of cinema websites -> titles (public data, a cache)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
PAUSE = 1.5
PARIS = zoneinfo.ZoneInfo("Europe/Paris")


def slug(s):
    s = unicodedata.normalize("NFD", str(s).lower())
    s = "".join(ch for ch in s if not 0x0300 <= ord(ch) <= 0x036F)
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def get(url, encoding=None, referer=None):
    headers = {"User-Agent": UA, "Accept-Language": "fr-FR,fr;q=0.9"}
    if referer:
        headers["Referer"] = referer
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=40) as r:
        raw = r.read()
        charset = encoding or r.headers.get_content_charset() or "utf-8"
        return raw.decode(charset, "replace"), r.geturl()


def text(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()


def today():
    return datetime.datetime.now(PARIS).date()


def load_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


# ---------------------------------------------------------------- film matching

class Films:
    """Finds a film id in the release list from an AlloCiné id or a title."""

    NOISE = [
        r"\bavant[- ]premi[eè]re\b.*$", r"\bavp\b.*$", r"\(?\b(vf|vost|vostfr|vo)\b\)?",
        r"\(?\b(4k|3d|imax|4dx|screenx|dolby( cinema)?|version (longue|restaur[ée]e))\b\)?",
        r"\s+-\s+(partie|part)\s+\d+.*$", r"\s*\([^)]*\)\s*$",
    ]

    def __init__(self):
        self.week_of, self.by_ac, self.by_slug = {}, {}, {}
        originals = {}
        for path in sorted((DATA / "weeks").glob("*.json")):   # oldest first, so the newest release wins
            doc = json.loads(path.read_text(encoding="utf-8"))
            for r in doc.get("films", []):
                if not (isinstance(r, list) and len(r) > 1):
                    continue
                fid = f"{r[0]}_{slug(r[1])}"
                self.week_of[fid] = path.stem
                self.by_slug[slug(r[1])] = fid
                if len(r) > 8 and isinstance(r[8], str) and not r[8].isdigit():
                    originals[slug(r[8])] = fid
        for k, fid in originals.items():
            self.by_slug.setdefault(k, fid)
        for fid, e in sorted(load_json(DATA / "extras.json", {}).items()):
            if e.get("ac") and fid in self.week_of:
                self.by_ac[int(e["ac"])] = fid

    def find(self, title=None, ac=None):
        if ac and int(ac) in self.by_ac:
            return self.by_ac[int(ac)]
        if not title:
            return None
        k = slug(title)
        if k in self.by_slug:
            return self.by_slug[k]
        t = title.lower()
        for pat in self.NOISE:
            t = re.sub(pat, " ", t, flags=re.I)
        k = slug(t)
        if k in self.by_slug:
            return self.by_slug[k]
        close = difflib.get_close_matches(k, list(self.by_slug), n=1, cutoff=0.93)
        return self.by_slug[close[0]] if close else None


# ---------------------------------------------------------------- merging

def merge(scraped, covered, addresses):
    """scraped: {(film id, cinema): {day: {"HH:MM"}}}; covered: {(cinema, day)} read in full."""
    shows = load_json(SHOWTIMES, {})
    films = Films()
    day0 = today().isoformat()
    now = datetime.datetime.now(PARIS).isoformat(timespec="minutes")
    for fid in list(shows):
        kept = []
        for c in shows[fid].get("cinemas") or []:
            name = c.get("name")
            times = {d: v for d, v in (c.get("times") or {}).items() if d >= day0 and (name, d) not in covered}
            if times:
                c["times"] = times
                kept.append(c)
        if kept:
            shows[fid]["cinemas"] = kept
        else:
            del shows[fid]
    for (fid, name), times in scraped.items():
        entry = shows.setdefault(fid, {"week": films.week_of.get(fid), "cinemas": []})
        entry["week"] = films.week_of.get(fid, entry.get("week"))
        entry["updatedAt"] = now
        entry.pop("note", None)
        cinema = next((c for c in entry["cinemas"] if c.get("name") == name), None)
        if cinema is None:
            cinema = {"name": name, "address": addresses.get(name, ""), "times": {}}
            entry["cinemas"].append(cinema)
        if not cinema.get("address") and addresses.get(name):
            cinema["address"] = addresses[name]
        for day, hours in times.items():
            if day >= day0:
                cinema["times"][day] = sorted(set(cinema["times"].get(day, [])) | set(hours))
    for entry in shows.values():
        entry["cinemas"] = [c for c in entry["cinemas"] if c.get("times")]
        entry["cinemas"].sort(key=lambda c: c.get("name", ""))
        for c in entry["cinemas"]:
            c["times"] = dict(sorted(c["times"].items()))
    shows = {k: v for k, v in shows.items() if v["cinemas"]}
    SHOWTIMES.write_text(json.dumps(dict(sorted(shows.items())), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    sessions = sum(len(v) for e in shows.values() for c in e["cinemas"] for v in c["times"].values())
    print(f"data/showtimes.json: {len(shows)} films, {sessions} sessions")


def cinema_addresses():
    return {c["name"]: c.get("address", "") for c in load_json(CINEMAS, [])}


def add_cinema(name, kind, address, lat, lng):
    """Adds a cinema to data/cinemas.json (the app's list) if it isn't there yet."""
    cinemas = load_json(CINEMAS, [])
    if any(c["name"] == name for c in cinemas) or lat is None or lng is None:
        return
    cinemas.append({"name": name, "type": kind, "address": address, "lat": round(lat, 4), "lng": round(lng, 4)})
    CINEMAS.write_text(json.dumps(cinemas, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"added {name} to data/cinemas.json")


class Collector:
    def __init__(self, films):
        self.films = films
        self.scraped, self.covered, self.unmatched = {}, set(), set()

    def add(self, cinema, day, hhmm, title=None, ac=None):
        fid = self.films.find(title, ac)
        if not fid:
            self.unmatched.add(title or str(ac))
            return
        self.scraped.setdefault((fid, cinema), {}).setdefault(day, set()).add(hhmm)

    def report(self, label):
        n = sum(len(v) for t in self.scraped.values() for v in t.values())
        films = len({fid for fid, _ in self.scraped})
        print(f"{label}: {n} sessions for {films} films")
        if self.unmatched:
            names = sorted(self.unmatched)
            print(f"  not in the release list ({len(names)}): " + ", ".join(names[:20]) + ("…" if len(names) > 20 else ""))


# ---------------------------------------------------------------- UGC

UGC = [  # ugc.fr cinema id, name in the app (None: the name on ugc.fr)
    (10, "UGC Ciné Cité Les Halles"), (12, "UGC Ciné Cité Bercy"), (37, None), (7, None),
    (4, None), (13, None), (15, None), (14, None), (9, None), (11, None), (5, None),
]


def ugc(col):
    start = today()
    for cid, app_name in UGC:
        page_url = f"https://www.ugc.fr/cinema.html?id={cid}"
        try:
            page, _ = get(page_url)
        except Exception as ex:
            print(f"UGC {cid}: {ex}", file=sys.stderr)
            time.sleep(PAUSE)
            continue
        time.sleep(PAUSE)
        title = re.search(r"<title>(.*?)</title>", page, re.S)
        name = app_name or (text(title.group(1)).split(",")[0] if title else f"UGC {cid}")
        addr = re.search(r'(\d[^<>"]{3,80}?)\s+(750\d\d)\s+PARIS', page)
        lat = re.search(r'latitude"\s*:\s*(-?\d+\.\d+)', page)
        lng = re.search(r'longitude"\s*:\s*(-?\d+\.\d+)', page)
        address = f"{text(addr.group(1))}, {addr.group(2)}" if addr else ""
        add_cinema(name, "Multiplex", address, float(lat.group(1)) if lat else None, float(lng.group(1)) if lng else None)
        counts, low = [], 0
        for i in range(21):
            day = start + datetime.timedelta(days=i)
            url = (f"https://www.ugc.fr/showingsCinemaAjaxAction!getShowingsForCinemaPage.action"
                   f"?cinemaId={cid}&date={day.isoformat()}&page=30007")
            try:
                frag, _ = get(url, referer=page_url)
            except Exception as ex:
                print(f"{name} {day}: {ex}", file=sys.stderr)
                time.sleep(PAUSE)
                break
            time.sleep(PAUSE)
            n = 0
            for b in re.findall(r"<button[^>]*data-seanceHour=[^>]*>", frag):
                hour = re.search(r'data-seanceHour="(\d\d:\d\d)"', b)
                date = re.search(r'data-seanceDate="(\d\d)/(\d\d)/(\d{4})"', b)
                film = re.search(r'data-film="([^"]*)"', b)
                if not (hour and date and film):
                    continue
                d = f"{date.group(3)}-{date.group(2)}-{date.group(1)}"
                col.add(name, d, hour.group(1), title=html.unescape(film.group(1)))
                n += 1
            col.covered.add((name, day.isoformat()))
            counts.append(n)
            # stop once the programme runs out (next week not published yet): two thin days in a row
            low = low + 1 if i >= 2 and n < 0.25 * max(counts) else 0
            if low >= 2:
                break
        print(f"{name}: {sum(counts)} sessions over {len(counts)} days")


# ---------------------------------------------------------------- Le Grand Action

def grandaction(col):
    name = "Le Grand Action"
    try:
        page, _ = get("https://www.legrandaction.com/")
    except Exception as ex:
        print(f"{name}: {ex}", file=sys.stderr)
        return
    time.sleep(PAUSE)
    m = re.search(r"var scheduleData = (\{.*?\});\s*\n", page, re.S)
    if not m:
        print(f"{name}: no schedule found", file=sys.stderr)
        return
    movies = json.loads(m.group(1)).get("calendar", {}).get("movies", {}) or {}
    titles = load_json(TITLES, {})
    known = titles.setdefault("legrandaction", {})
    days = set()
    for mid, by_day in movies.items():
        if mid not in known:
            try:
                film_page, final = get(f"https://www.legrandaction.com/?p={mid}")
                h1 = re.search(r"<h1[^>]*>(.*?)</h1>", film_page, re.S)
                known[mid] = text(h1.group(1)) if h1 else final.rstrip("/").rsplit("/", 1)[-1]
            except Exception as ex:
                print(f"{name} film {mid}: {ex}", file=sys.stderr)
                known[mid] = None
            time.sleep(PAUSE)
        for day, hours in (by_day or {}).items():
            days.add(day)
            for hhmm in hours:
                if known.get(mid):
                    col.add(name, day, hhmm[:5], title=known[mid])
    TITLES.write_text(json.dumps(titles, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    if days:
        first, last = today(), max(datetime.date.fromisoformat(d) for d in days)
        while first <= last:
            col.covered.add((name, first.isoformat()))
            first += datetime.timedelta(days=1)
    print(f"{name}: {len(movies)} films, {len(days)} days")


# ---------------------------------------------------------------- Le Balzac (Cotecine)

def cotecine(col, name, url):
    try:
        page, _ = get(url)
    except Exception as ex:
        print(f"{name}: {ex}", file=sys.stderr)
        return
    time.sleep(PAUSE)
    n = 0
    for block in page.split('<div class="hr_film')[1:]:
        film = re.search(r'/film/(\d+)/"[^>]*>(.*?)</a>', block, re.S)
        if not film:
            continue
        title = text(re.sub(r'<span class="flag[^"]*">.*?</span>', "", film.group(2), flags=re.S))
        for ts in re.findall(r"/reserver/F\d+/D(\d+)/", block):
            t = datetime.datetime.fromtimestamp(int(ts), PARIS)
            col.add(name, t.date().isoformat(), t.strftime("%H:%M"), title=title, ac=int(film.group(1)))
            n += 1
    tabs = len(set(re.findall(r'class="fcel jour(\d+)', page)))
    for i in range(max(tabs, 1)):
        col.covered.add((name, (today() + datetime.timedelta(days=i)).isoformat()))
    print(f"{name}: {n} sessions over {tabs} days")


def balzac(col):
    cotecine(col, "Le Balzac", "https://www.cinemabalzac.com/horaires/")


# ---------------------------------------------------------------- Le Grand Rex

def grandrex(col):
    name = "Le Grand Rex"
    try:
        page, _ = get("https://www.legrandrex.com/cinema/")
    except Exception as ex:
        print(f"{name}: {ex}", file=sys.stderr)
        return
    time.sleep(PAUSE)
    days = sorted(set(re.findall(r'href="/cinema/\?date=(\d{4}-\d\d-\d\d)"\s+data-jour', page)))
    n = 0
    for day in days:
        try:
            page, _ = get(f"https://www.legrandrex.com/cinema/?date={day}")
        except Exception as ex:
            print(f"{name} {day}: {ex}", file=sys.stderr)
            time.sleep(PAUSE)
            continue
        time.sleep(PAUSE)
        for card in re.findall(r'<article class="carte[^"]*"[^>]*>(.*?)</article>', page, re.S):
            if f"?date={day}" not in card:
                continue
            title = re.search(r'carte__libelle">(.*?)</span>', card, re.S)
            seances = " ".join(re.findall(r'class="carte__seances"[^>]*>(.*?)</span>', card, re.S))
            for hhmm in sorted(set(re.findall(r"\b([01]\d|2[0-3]):([0-5]\d)\b", text(seances)))):
                col.add(name, day, f"{hhmm[0]}:{hhmm[1]}", title=text(title.group(1)) if title else None)
                n += 1
        col.covered.add((name, day))
    print(f"{name}: {n} sessions over {len(days)} days")


# ---------------------------------------------------------------- Studio 28

def studio28(col):
    name = "Studio 28"
    try:
        page, _ = get("https://www.cinema-studio28.fr/tous-les-films/")
    except Exception as ex:
        print(f"{name}: {ex}", file=sys.stderr)
        return
    time.sleep(PAUSE)
    days, n = set(), 0
    for art in re.findall(r'<article class="mec-[^"]*event-article[^"]*">(.*?)</article>', page, re.S):
        day = re.search(r"occurrence=(\d{4}-\d\d-\d\d)", art)
        hour = re.search(r"mec-event-time[^>]*>(?:\s*<i[^>]*></i>)?\s*(\d{1,2})\s*h\s*(\d{2})", art)
        title = re.search(r'aria-label="([^"]+)"', art)
        if not (day and hour and title) or day.group(1) < today().isoformat():
            continue
        days.add(day.group(1))
        col.add(name, day.group(1), f"{int(hour.group(1)):02d}:{hour.group(2)}", title=html.unescape(title.group(1)))
        n += 1
    if days:
        d, last = today(), datetime.date.fromisoformat(max(days))
        while d <= last:
            col.covered.add((name, d.isoformat()))
            d += datetime.timedelta(days=1)
    print(f"{name}: {n} sessions over {len(days)} days")


# ----------------------------------------------------------------

SOURCES = {"ugc": ugc, "grandaction": grandaction, "balzac": balzac, "grandrex": grandrex, "studio28": studio28}

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    chosen = list(SOURCES) if cmd == "sites" else [cmd] if cmd in SOURCES else []
    if not chosen:
        print(__doc__)
        sys.exit(1)
    col = Collector(Films())
    for key in chosen:
        SOURCES[key](col)
    col.report("websites")
    merge(col.scraped, col.covered, cinema_addresses())
