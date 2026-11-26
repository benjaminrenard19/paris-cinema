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


THEATERS = DATA / "theaters.json"
REPERTORY = DATA / "repertory.json"
STRINGS = ROOT / "ParisCinema" / "fr.lproj" / "Data.strings"


def english_terms():
    """French genre and country names to the English ones the app translates."""
    out = {}
    for k, v in re.findall(r'^"(.+?)" = "(.+?)";', STRINGS.read_text(encoding="utf-8"), re.M):
        out.setdefault(v.lower(), k)
    out.update({"u.s.a.": "usa", "etats-unis": "usa", "états-unis": "usa", "royaume-uni": "uk",
                "allemagne de l'ouest": "west germany", "u.r.s.s.": "ussr", "science fiction": "sci-fi",
                "epouvante-horreur": "horror", "épouvante-horreur": "horror", "comédie dramatique": "comedy-drama"})
    return out


def english(names, terms, countries=False):
    """"Drame, Comédie" -> "Drama, comedy"; "U.S.A., Italie" -> "USA, Italy"."""
    words = [terms.get(w.strip().lower(), w.strip().lower()) for w in names.split(",") if w.strip()]
    if not words:
        return None
    if countries:
        upper = {"usa", "uk", "ussr"}
        return ", ".join(w.upper() if w in upper else " ".join(x[:1].upper() + x[1:] for x in w.split(" ")) for w in words)
    out = ", ".join(words)
    return out[:1].upper() + out[1:]


def film_page(ac, terms):
    """Poster, year, running time, director, genre, country, ratings and synopsis from a film page."""
    page = get(f"https://www.allocine.fr/film/fichefilm_gen_cfilm={ac}.html")
    e = {}
    info = re.search(r'meta-body-info">(.*?)</div>', page, re.S)
    if info:
        parts = [p.strip() for p in re.sub(r"\s+", " ", text(info.group(1))).split("|")]
        d = minutes(" ".join(parts))
        if d and 30 <= d <= 400:
            e["duration"] = d
        if parts and not re.search(r"\d", parts[-1]):
            e["genre"] = english(parts[-1], terms)
    y = re.search(r'Année de production\s*</span>\s*<span[^>]*>\s*(\d{4})', page)
    if y:
        e["year"] = y.group(1)
    elif info and parts:
        y = re.search(r"\b(18|19|20)\d\d\b", parts[0])
        if y:
            e["year"] = y.group(0)
    m = re.search(r'meta-body-item meta-body-direction[^>]*>(.*?)</div>', page, re.S)
    if m:
        e["dir"] = re.sub(r"^De\s+", "", re.sub(r"\s+", " ", text(m.group(1)))).strip() or None
    m = re.search(r'meta-body-item meta-body-actor[^>]*>(.*?)</div>', page, re.S)
    if m:
        e["cast"] = re.sub(r"^Avec\s+", "", re.sub(r"\s+", " ", text(m.group(1)))).strip() or None
    m = re.search(r'Nationalit[ée]s?\s*</span>(.*?)</div>', page, re.S)
    if m:
        e["origin"] = english(re.sub(r"\s+", " ", text(m.group(1))), terms, countries=True)
    m = re.search(r'class="content-txt\s*">\s*<p class="bo-p">(.*?)</p>', page, re.S)
    if m:
        syn = re.sub(r"\s+", " ", text(m.group(1))).strip()
        if syn and "{" not in syn:
            e["syn"] = syn
    for key, label in (("press", "Presse"), ("spect", "Spectateurs")):
        v = note(page, label)
        if v and 0 < v <= 5:
            e[key] = v
    m = re.search(r'thumbnail-img[^>]*src="(https://[^"]*acsta\.net/[^"]+)"', page)
    if m and "empty" not in m.group(1):
        e["poster"] = m.group(1)
    return {k: v for k, v in e.items() if v}


def repertory(new, limit=80):
    """Adds the classics found on cinema pages to data/repertory.json, then fills in their details."""
    rep = json.loads(REPERTORY.read_text(encoding="utf-8")) if REPERTORY.exists() else {}
    for ac, title in new.items():
        rep.setdefault(f"rep-{ac}", {"ac": ac, "title": title})
    terms = english_terms()
    todo = [fid for fid, e in rep.items() if not e.get("checked")][:limit]
    for fid in todo:
        e = rep[fid]
        try:
            e.update(film_page(e["ac"], terms))
            e["checked"] = datetime.date.today().isoformat()
        except Exception as ex:
            print(f"{e.get('title')}: {ex}", file=sys.stderr)
        time.sleep(PAUSE)
    REPERTORY.write_text(json.dumps(dict(sorted(rep.items())), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"data/repertory.json: {len(rep)} films ({len(new)} seen today, {len(todo)} looked up)")


def parse_theater(page):
    """[(AlloCiné film id, title, [(day, "HH:MM", version)])] from a cinema's public page."""
    import sessions
    out = []
    for part in page.split('class="card entity-card entity-card-list movie-card-theater')[1:]:
        m = re.search(r'fichefilm_gen_cfilm=(\d+)\.html"[^>]*>(.*?)</a>', part, re.S)
        if not m:
            continue
        found = []
        blocks = part.split('class="showtimes-version"')
        for block in blocks[1:] or [part]:
            label = re.search(r'<div class="text">(.*?)</div>', block, re.S)
            ver = sessions.version(text(label.group(1))) if label else None
            for day, hhmm in re.findall(r'data-showtime-time="(\d{4}-\d\d-\d\d)T(\d\d:\d\d)', block):
                found.append((day, hhmm, ver))
        if found:
            out.append((int(m.group(1)), text(m.group(2)), found))
    return out


def theaters():
    """Today's (and some of tomorrow's) sessions from each cinema's public AlloCiné page."""
    import sessions
    col = sessions.Collector(sessions.Films())
    addresses = sessions.cinema_addresses()
    theaters_list = json.loads(THEATERS.read_text(encoding="utf-8"))
    for t in theaters_list:
        if t.get("address"):
            addresses.setdefault(t["name"], t["address"])
    today = datetime.date.today().isoformat()
    done, failed = [], []
    for t in theaters_list:
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
            for ac, title, found in parse_theater(page):
                for day, hhmm, ver in found:
                    col.add(name, day, hhmm, title=title, ac=ac, ver=ver)
        if got:
            done.append(name)
            col.cover(name, today)
        else:
            failed.append(name)
    print(f"{len(done)} cinemas read, {len(failed)} failed {failed if failed else ''}".rstrip())
    col.report("AlloCiné")
    repertory(col.new_rep)
    sessions.merge(col.scraped, col.covered, addresses, col.versions)


BOXOFFICE = DATA / "boxoffice.json"


def parse_boxoffice(page):
    """[[week start "YYYY-MM-DD", admissions that week, total so far]] from a film's public box-office page (France)."""
    import base64
    part = page.split("Box Office France", 1)[-1].split("</table>", 1)[0]
    weeks = []
    for row in re.findall(r"<tr class=\"responsive-table-row\">(.*?)</tr>", part, re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
        if len(cells) < 3:
            continue
        m = re.search(r'class="(ACr[A-Za-z0-9+/=]+)', cells[0])
        start = None
        if m:
            try:
                path = base64.b64decode(m.group(1).replace("ACr", "") + "===").decode("utf-8", "ignore")
                d = re.search(r"sem-(\d{4}-\d\d-\d\d)", path)
                start = d.group(1) if d else None
            except Exception:
                start = None
        nums = [re.sub(r"\D", "", text(c)) for c in cells[1:3]]
        if start and all(nums):
            weeks.append([start, int(nums[0]), int(nums[1])])
    return weeks


def boxoffice(limit=400, recent_weeks=10):
    """France admissions week by week (CBO, via AlloCiné's public box-office pages) into data/boxoffice.json.
    Films out in the last `recent_weeks` weeks are read again every day; older ones once, then monthly if empty."""
    feed = json.loads((DATA / "paris-cinema.json").read_text(encoding="utf-8"))
    bo = json.loads(BOXOFFICE.read_text(encoding="utf-8")) if BOXOFFICE.exists() else {}
    today = datetime.date.today()
    recent = (today - datetime.timedelta(weeks=recent_weeks)).isoformat()
    todo = []
    for f in feed["films"]:
        if not f.get("ac") or f.get("rep") or f["date"] > today.isoformat() or f.get("cat") == "E":
            continue
        e = bo.get(f["id"], {})
        checked = e.get("checked", "")
        if f["date"] >= recent:
            due = checked < today.isoformat()
        elif e.get("weeks"):
            due = not checked
        else:
            due = checked < (today - datetime.timedelta(days=30)).isoformat()
        if due:
            todo.append(f)
    todo.sort(key=lambda f: f["date"], reverse=True)
    done = found = 0
    for f in todo[:limit]:
        try:
            page = get(f"https://www.allocine.fr/film/fichefilm-{f['ac']}/box-office/")
            weeks = parse_boxoffice(page)
            bo[f["id"]] = {"checked": today.isoformat(), "weeks": weeks}
            done += 1
            found += bool(weeks)
        except Exception as ex:
            print(f"{f['title']}: {ex}", file=sys.stderr)
        time.sleep(PAUSE)
        if done % 25 == 0:
            BOXOFFICE.write_text(json.dumps(dict(sorted(bo.items())), ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    BOXOFFICE.write_text(json.dumps(dict(sorted(bo.items())), ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"data/boxoffice.json: {done} films read, {found} with admissions ({len(todo) - done} left for next time)")


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
    elif cmd == "boxoffice":
        boxoffice(int(sys.argv[2]) if len(sys.argv) > 2 else 400)
    else:
        print(__doc__)
