# Sloth Cinema 🦥

Every film released in Paris cinemas since January 2026, week by week, plus an iPhone app to browse them, keep favourites, plan your week at the cinema, and rate what you've seen.

- `data/`: the film database. There is one file per French cinema week (Wednesday to Tuesday) in `data/weeks/`, plus producers and synopses (`details.json`), showtimes (`showtimes.json`), links to official posters (`posters.json`) and 29 Paris cinemas (`cinemas.json`).
- `data/paris-cinema.json`: everything combined into one file. This is the file the app downloads. It is built by `scripts/build.py`.
- `ParisCinema/` and `ParisCinema.xcodeproj`: the SwiftUI iPhone app.

Claude updates the data every Tuesday evening, once cinemas have published the new week's programme. Listings come from AlloCiné's weekly release calendar. Synopses are short summaries in Claude's own words.

## The app

| Tab | What it does |
| --- | --- |
| **Films** | Browse week by week with official posters. Tap the star at the top right of any film to add it to your favourites. Filter by category or favourites, and search the whole year. Pull down to check for new films. |
| **Film page** | Poster, synopsis, cast, producers, and links to the trailer (original version with French subtitles), AlloCiné and Paris showtimes. Mark the film as watched (any past date), rate it out of 5, and plan when to go. |
| **My week** | The week from Wednesday to Tuesday, day by day: which film, when and where. Add a film to any day, confirm provisional plans, and plan your favourites. |
| **Notifications** | About 2 h 30 after a confirmed plan starts, the app asks how the film was. Rate it if you went, or pick a new day if you didn't. |
| **My list** | Your favourites grouped by year. Each year shows films watched and, in brackets, watched plus still planned, for example 25 (28). |
| **Watched** | Your watched films by year, with ratings and your average. Add or edit films you saw elsewhere. |
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

To bring over the favourites, watched films and plans you made on the Claude page: on the page, tap **Export for iPhone app** and save the file to iCloud Drive. In the app, tap **⟳** on the Films tab and choose **Import**.

## Updating the data by hand

Edit or add a week file in `data/weeks/`, then run:

```sh
python3 scripts/build.py
```

The script rebuilds `data/paris-cinema.json` and the copy built into the app (`ParisCinema/paris-cinema.json`). Film IDs are `date_slug-of-title`, the same as on the Claude page, so favourites and ratings carry across.

## Credits

- Film listings and poster links come from AlloCiné. The posters are loaded from AlloCiné's servers and are not stored in this repo.
- The sloth on the app icon is from [Twemoji](https://github.com/jdecked/twemoji), licensed under CC-BY 4.0.
