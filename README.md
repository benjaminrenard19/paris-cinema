# Sloth Cinema 🦥

Every film released in Paris cinemas since January 2026, week by week, plus an iPhone app to browse them, keep favourites, plan your week at the cinema, and rate what you've seen.

- `data/`: the film database. There is one file per French cinema week (Wednesday to Tuesday) in `data/weeks/`, plus producers and synopses (`details.json`), showtimes (`showtimes.json`), links to official posters (`posters.json`) and the Paris cinemas the app lists (`cinemas.json`).
- `data/extras.json`: posters, critics and audience ratings and running times, read from AlloCiné's public pages by `scripts/allocine.py`.
- `data/showtimes.json`: session times, refreshed every morning from two kinds of source:
  - the cinemas' own websites, by `python3 scripts/sessions.py sites`: UGC's 11 Paris cinemas (ugc.fr), Le Grand Rex, Le Grand Action, Le Balzac and Studio 28. These list every day the cinema has published, normally up to next Tuesday (the new week comes out on Monday or Tuesday), plus special screenings further ahead;
  - each cinema's public AlloCiné page, by `python3 scripts/allocine.py theaters` (cinemas and codes in `data/theaters.json`), which gives today and tomorrow everywhere else, including Pathé, mk2 and Gaumont Disney Village.
  Pathé, mk2, Le Louxor, Max Linder, Luminor, Le Champo, Reflet Médicis, Escurial, Saint-André des Arts, Christine, Les 7 Parnassiens and Elysées Lincoln load their times in the browser from booking services rather than in the page, so they come through AlloCiné. Past days are dropped.
- `data/paris-cinema.json`: everything combined into one file. This is the file the app downloads. It is built by `scripts/build.py`.
- `ParisCinema/` and `ParisCinema.xcodeproj`: the SwiftUI iPhone app.

Claude adds new weeks every Tuesday evening, once cinemas have published the new week's programme, and refreshes showtimes, posters, ratings and running times every morning before 7. Listings come from AlloCiné's weekly release calendar. Synopses are short summaries in Claude's own words.

## The app

| Tab | What it does |
| --- | --- |
| **Films** | Browse week by week with official posters, running times and ratings. Sort a week by name (A–Z or Z–A), critics, audience or average rating, or running time. Tap the star at the top right of any film to add it to your favourites. Pull down to check for new films. |
| **Film page** | Poster, critics and audience ratings (with their average), synopsis, cast, producers, and links to the trailer (original version with French subtitles), AlloCiné and Paris showtimes. Tap the poster to see it full screen; tap or swipe for other posters, running time and ratings, the story, and the cast and producers. Mark the film as watched (any past date) and rate it out of 5. |
| **Plan to watch** | Choose the cinema, then the day (a green dot shows the days it plays there, or open the calendar), then the time. "Today at your cinemas" lists today's screenings at your starred cinemas. |
| **Calendar** | In Settings, turn on "Save plans to my calendar" and pick a calendar. Confirmed plans are added, moved and removed automatically. For Google Calendar, add your Google account in iPhone Settings › Apps › Calendar › Calendar Accounts first. |
| **My week** | The week from Wednesday to Tuesday, day by day: which film, when and where. Add a film to any day, confirm provisional plans, and plan your favourites. |
| **Notifications** | About 2 h 30 after a confirmed plan starts, the app asks how the film was. Rate it if you went, or pick a new day if you didn't. |
| **My list** | Your favourites grouped by year. Tap a year to fold or unfold it; long years show 6 films and a "Show all" button. Each year shows films watched and, in brackets, watched plus still planned, for example 25 (28). |
| **Watched** | Your watched films by year, with ratings and your average. Add or edit films you saw elsewhere, with their poster. |
| **Tutorial** | Shown on first launch, can be skipped at any time and shown again from Settings. |
| **Cinemas** | A map and a list of Paris cinemas. Star your cinemas so they come first, sort by distance from you or from a place, and find any other cinema on Apple Maps. |

The app downloads `data/paris-cinema.json` from this repo when you open it, so new weeks appear without rebuilding the app. Your favourites, ratings and plans stay on your phone and are never uploaded.

## Install on your iPhone

You need a Mac with Xcode 16 or later, and an iPhone on iOS 17 or later.

1. Download this repo: **Code › Download ZIP**, then unzip it. Or clone it.
2. Open Xcode once, accept the extra components, and make sure **iOS** is installed. Add your Apple ID in **Xcode › Settings › Accounts**.
3. Double-click `ParisCinema.xcodeproj`. Click the blue **ParisCinema** project, select the **ParisCinema** target, open **Signing & Capabilities**, and choose your **Personal Team**.
   - If the bundle identifier is refused, change it to something unique.
4. Connect the iPhone with a cable and tap **Trust**. Turn on **Settings › Privacy & Security › Developer Mode**; the iPhone restarts.
5. Choose the iPhone in Xcode's device menu and press **▶**.
6. On the iPhone, go to **Settings › General › VPN & Device Management** and trust your developer certificate. Then open **Cinéma Paris**.

With a free Apple ID, the app stops opening after 7 days. Plug the iPhone in and press ▶ again; your lists are kept.

New versions of the app install themselves: every time you press ▶, Xcode first gets the latest version from GitHub (a pre-action in the shared "ParisCinema" scheme), keeping your signing team. If a build fails just after an update that added new files, press ▶ once more. To update by hand instead:

```sh
cd ~/Desktop/paris-cinema && git pull --rebase --autostash
```

New films, posters and showtimes don't need Xcode at all: the app downloads them by itself.

To bring over the favourites, watched films and plans you made on the Claude page: on the page, tap **Export for iPhone app** and save the file to iCloud Drive. In the app, tap **⟳** on the Films tab and choose **Import**.

## Updating the data by hand

Edit or add a week file in `data/weeks/`, then run:

```sh
python3 scripts/build.py
```

The script rebuilds `data/paris-cinema.json` and the copy built into the app (`ParisCinema/paris-cinema.json`). Film IDs are `date_slug-of-title`, the same as on the Claude page, so favourites and ratings carry across.

## Credits

- Film listings, ratings and poster links come from AlloCiné. The posters are loaded from AlloCiné's servers and are not stored in this repo.
- When AlloCiné has no poster, the app looks one up in Apple's iTunes film catalogue.
- The sloth on the app icon is from [Twemoji](https://github.com/jdecked/twemoji), licensed under CC-BY 4.0.
