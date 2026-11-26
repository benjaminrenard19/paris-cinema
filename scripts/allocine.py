#!/usr/bin/env python3
"""Adds posters, press and audience ratings and running times to data/extras.json,
from AlloCiné's public weekly release pages and film pages.

  python3 scripts/allocine.py agenda 2026-12-02 2026-12-09   # those weeks
  python3 scripts/allocine.py agenda --missing 8             # the 8 weeks with most gaps
  python3 scripts/allocine.py durations 120                  # running times for up to 120 films

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


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "fr-FR,fr;q=0.9"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


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
    else:
        print(__doc__)
