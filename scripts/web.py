"""Builds the browser version of Sloth Cinema: docs/index.html (served by GitHub Pages).
It downloads data/paris-cinema.json from GitHub when opened, so it never needs rebuilding for new films.
Run again only after changing scripts/web_template.html or the French genre names."""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
strings = (ROOT / "ParisCinema" / "fr.lproj" / "Data.strings").read_text(encoding="utf-8")
terms = dict(re.findall(r'^"(.+?)" = "(.+?)";', strings, re.M))
html = (ROOT / "scripts" / "web_template.html").read_text(encoding="utf-8")
out = ROOT / "docs"
out.mkdir(exist_ok=True)
(out / "index.html").write_text(html.replace("__TERMS__", json.dumps(terms, ensure_ascii=False)), encoding="utf-8")
(out / ".nojekyll").write_text("", encoding="utf-8")
print(f"docs/index.html written ({len(terms)} French terms)")
