#!/usr/bin/env python3
"""Every film released in France from 2015 to 2025, from AlloCiné's public weekly release pages
(the same pages scripts/allocine.py reads for this year), into data/history.json.

The app uses it for search, for imports (screen recordings, ratings from other apps) and for the
Hall of Fame; the Films page stays on this year. Facts only: title, date, genres, director, cast,
poster link, ratings and running time. No synopses.

    python3 scripts/history.py                 # 2015 to 2025, skipping weeks already fetched
    python3 scripts/history.py 2019 2020       # only those years

Fetched weeks are kept in data/history-weeks/ (so a run can stop and go on later); the final file
is data/history.json: {"format": 1, "updatedAt", "films": [{"id", "date", "title", ...}]}.
Requests are spaced out like scripts/allocine.py's.
"""
import datetime
import json
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from allocine import ROOT, PAUSE, get, text, note, minutes, slug, english, english_terms  # noqa: E402

WEEKS = ROOT / "data" / "history-weeks"
OUT = ROOT / "data" / "history.json"
MONTHS = {m: i + 1 for i, m in enumerate(
    ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"])}

# AlloCiné genres (in English) to the app's categories.
CAT_RULES = [("A", ("animation", "family")), ("V", ("documentary",)), ("M", ("biopic", "musical", "music")),
             ("T", ("thriller", "action", "sci-fi", "horror", "crime", "adventure", "war", "spy", "fantasy", "western")),
             ("C", ("comedy",)), ("D", ("drama", "romance", "history"))]


def wednesdays(years):
    d = datetime.date(min(years), 1, 1)
    while d.weekday() != 2:
        d += datetime.timedelta(days=1)
    while d.year <= max(years):
        if d.year in years:
            yield d.isoformat()
        d += datetime.timedelta(days=7)


def release_date(info, week):
    m = re.search(r"(\d{1,2})(?:er)?\s+([a-zéû]+)\s+(\d{4})", info)
    if m and m.group(2) in MONTHS:
        try:
            return datetime.date(int(m.group(3)), MONTHS[m.group(2)], int(m.group(1))).isoformat()
        except ValueError:
            pass
    return week


def category(genre):
    g = (genre or "").lower()
    for code, words in CAT_RULES:
        if any(w in g for w in words):
            return code
    return "O"


def parse(page, week, terms):
    films = []
    for part in page.split('<li class="mdl">')[1:]:
        m = re.search(r'fichefilm_gen_cfilm=(\d+)\.html"[^>]*>(.*?)</a>', part, re.S)
        if not m:
            continue
        title = text(m.group(2))
        poster = None
        for p in re.findall(r'(?:data-src|src)="(https://[^"]*acsta\.net/[^"]+)"', part):
            if "empty" not in p and not p.endswith(".svg"):
                poster = p
                break
        info = re.search(r'meta-body-info">(.*?)</div>', part, re.S)
        info = re.sub(r"\s+", " ", text(info.group(1))) if info else ""
        genres = info.split("|")[-1].strip() if "|" in info else ""
        genre = english(genres, terms) if genres else None
        direction = re.search(r'meta-body-direction[^>]*>(.*?)</div>', part, re.S)
        direction = re.sub(r"^(De|Par)\s+", "", re.sub(r"\s+", " ", text(direction.group(1)))) if direction else None
        actors = re.search(r'meta-body-actor[^>]*>(.*?)</div>', part, re.S)
        actors = re.sub(r"^Avec\s+", "", re.sub(r"\s+", " ", text(actors.group(1)))) if actors else None
        orig = re.search(r'Titre original\s*</span>\s*<span[^>]*>(.*?)</span>', part, re.S)
        f = {
            "id": f"{week}_{slug(title)}", "date": release_date(info, week), "title": title,
            "cat": category(genre), "genre": genre, "dir": direction or None,
            "cast": ", ".join((actors or "").split(", ")[:3]) or None,
            "orig": text(orig.group(1)) if orig else None, "poster": poster,
            "press": note(part, "Presse"), "spect": note(part, "Spectateurs"),
            "duration": minutes(info), "ac": int(m.group(1)),
        }
        films.append({k: v for k, v in f.items() if v not in (None, "")})
    return films


def fetch_week(week, terms):
    films, page_no = [], 1
    while page_no <= 6:
        url = f"https://www.allocine.fr/film/agenda/sem-{week}/" + (f"?page={page_no}" if page_no > 1 else "")
        page = get(url)
        time.sleep(PAUSE)
        films += parse(page, week, terms)
        if f"?page={page_no + 1}" not in page:
            break
        page_no += 1
    return films


def assemble():
    # Weeks in order, so a film shown again later (a re-release) keeps its first week.
    seen, films = set(), []
    for path in sorted(WEEKS.glob("*.json")):
        for f in json.loads(path.read_text(encoding="utf-8")):
            keys = {f["id"], f"ac{f['ac']}"} if f.get("ac") else {f["id"]}
            if keys & seen:
                continue
            seen |= keys
            films.append(f)
    films.sort(key=lambda f: (f["date"], f["title"]))
    OUT.write_text(json.dumps({"format": 1, "updatedAt": datetime.date.today().isoformat(), "films": films},
                              ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(films)} films in {OUT.relative_to(ROOT)}")


def main():
    years = [int(a) for a in sys.argv[1:]] or list(range(2015, 2026))
    WEEKS.mkdir(parents=True, exist_ok=True)
    terms = english_terms()
    for week in wednesdays(years):
        path = WEEKS / f"{week}.json"
        if path.exists():
            continue
        try:
            films = fetch_week(week, terms)
        except Exception as e:  # keep going; the week is fetched on the next run
            print(f"{week}: {e}", file=sys.stderr)
            continue
        path.write_text(json.dumps(films, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(f"{week}: {len(films)} films", flush=True)
    assemble()


if __name__ == "__main__":
    main()
