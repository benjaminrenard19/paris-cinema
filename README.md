# Sloth Cinema 🦥

Every film released in Paris cinemas since January 2026, week by week, plus an iPhone app to browse them, keep favourites, plan your week at the cinema, and rate what you've seen.

- `data/`: the film database. There is one file per French cinema week (Wednesday to Tuesday) in `data/weeks/`, plus producers and synopses (`details.json`), showtimes (`showtimes.json`), links to official posters (`posters.json`) and the Paris cinemas the app lists (`cinemas.json`).
- `data/extras.json`: posters, critics and audience ratings and running times, read from AlloCiné's public pages by `scripts/allocine.py`.
- `data/showtimes.json`: session times, refreshed every morning from two kinds of source:
  - the cinemas' own websites, by `python3 scripts/sessions.py sites`: UGC's 11 Paris cinemas (ugc.fr), Le Grand Rex, Le Grand Action, Le Balzac and Studio 28 from their pages, and Max Linder, Luminor, Le Louxor, Les 7 Parnassiens, Les 5 Caumartin and Elysées Lincoln by opening their pages in headless Chrome (they fill in the times in the browser). They list every day the cinema has published, normally up to next Tuesday (the new week comes out on Monday or Tuesday), plus special screenings further ahead. Every page is tried up to 5 times;
  - each cinema's public AlloCiné page, by `python3 scripts/allocine.py theaters` (71 cinemas and their codes in `data/theaters.json`, including the Latin Quarter independents, Pathé, mk2 and Gaumont Disney Village), which gives today and tomorrow.
  Each session records its version when the source gives it: VF, VO or VOST (`"ver"` in `showtimes.json`).
- `data/repertory.json`: the classics and older films the independent cinemas show, found on their AlloCiné pages, with poster, year, director, running time, ratings and synopsis from each film's public page. They appear in the app's "Showing this week" list and in search, not in the weekly releases.
  Pathé, mk2, Le Champo, Reflet Médicis, Escurial, Saint-André des Arts and Christine load their times from booking services that can't be read page by page, so they come through AlloCiné (today and tomorrow). Past days are dropped.
- `data/boxoffice.json`: France admissions week by week for each film (CBO Box-Office, from AlloCiné's public box-office pages), read by `python3 scripts/allocine.py boxoffice`. The app uses them for "early bird" stats: how early you saw a film compared with everyone in France.
- `data/paris-cinema.json`: everything combined into one file. This is the file the app downloads. It is built by `scripts/build.py`.
- `ParisCinema/` and `ParisCinema.xcodeproj`: the SwiftUI iPhone app.

Claude adds new weeks every Tuesday evening, once cinemas have published the new week's programme, and refreshes showtimes, posters, ratings and running times every morning before 7. Listings come from AlloCiné's weekly release calendar. Synopses are short summaries in Claude's own words.

## The app

| Tab | What it does |
| --- | --- |
| **Films** | Opens on every film you can see this week (new releases and classics), starting at the filters. Scroll up for the stage and "This week"; switch to "Releases by week" to browse week by week, with a poster slideshow. Sort by name, critics, audience or average rating, or running time. Films you've seen can be hidden (My profile). Pull down to check for new films. |
| **Film page** | Poster, critics and audience ratings (with their average), synopsis, cast, producers, and links to the trailer (original version with French subtitles), AlloCiné and Paris showtimes. Tap the poster to see it full screen; tap or swipe for other posters, running time and ratings, the story, and the cast and producers. Mark the film as watched (any past date) and rate it out of 5. |
| **Plan to watch** | Choose the cinema, then the day (a green dot shows the days it plays there, or open the calendar), then the time. Each time shows VF, VO or VOST, with your preferred version first (or only, if it's a must). "Today at your cinemas" lists today's screenings at your starred cinemas. |
| **Invite** | From a film page or a plan in My week: a picture of the poster with the day, time and cinema, and "Would you join me…?" with the address, to send in Messages, WhatsApp or any app. |
| **Calendar** | In Settings, turn on "Save plans to my calendar" and pick a calendar. Confirmed plans are added, moved and removed automatically. For Google Calendar, add your Google account in iPhone Settings › Apps › Calendar › Calendar Accounts first. |
| **My week** | The week from Wednesday to Tuesday, day by day: which film, when and where. Add a film to any day, confirm provisional plans, and plan your favourites. |
| **Notifications** | After a confirmed plan, the app asks how the film was. Every week (Tuesday 20:00 by default, change it in Settings) a notification opens a slideshow of the new releases. For each of your cinemas (starring one adds it), choose Off, New films (a film you haven't seen starts there) or Film changes (for one-film cinemas like the Max Linder). |
| **My list** | Your favourites grouped by year. Tap a year to fold or unfold it; long years show 6 films and a "Show all" button. Each year shows films watched and, in brackets, watched plus still planned, for example 25 (28). |
| **Watched** | Your watched films by year, with ratings and your average. Add or edit films you saw elsewhere, with their poster. **Import from a screen recording**: record your screen while scrolling a list in another film app; the app reads each title, year and your stars on the phone, matches them with its films, and adds them without a cinema (you can add it later). |
| **Tutorial** | Shown on first launch, can be skipped at any time and shown again from Settings. |
| **Cinemas** | A map and a list of 80 Paris cinemas, with a search bar to add them to My cinemas. Tap a cinema for its films, sorted like the Films page, with the sessions left today; 🎉 when you've seen them all. |

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

New versions of the app install themselves: every time you press ▶, Xcode first gets the latest version from GitHub (a pre-action in the shared "ParisCinema" scheme), keeping your signing team. If a build fails just after an update that added new files, press ▶ once more. The pre-action's log is `.git/sloth-cinema-pull.log`.

When the build is for an iPhone, a post-action then installs the same build on your other connected iPhones too (the names in `SLOTH_PHONES`, by default "iPhone de Ben" and "iPhone de Camille Devisme"; log in `~/Library/Logs/SlothCinema-install.log`). Each one needs a cable, or the same Wi-Fi with **Connect via network** ticked, and must be unlocked.

If the folder is on a Desktop that iCloud syncs, right-click it in Finder and choose **Keep Downloaded**. Otherwise macOS can move git's files to iCloud when the disk is nearly full, and updates fail.

To update by hand instead:

```sh
cd ~/Desktop/paris-cinema && git pull --rebase --autostash
```

New films, posters and showtimes don't need Xcode at all: the app downloads them by itself.

### Automatic installs from the Mac

To have the Mac install each new version (and renew the free 7-day signing) without pressing ▶, run once in Terminal:

```sh
cd ~/Desktop/paris-cinema && git pull --rebase --autostash && bash scripts/mac/install-autoinstall.sh
```

Every hour, `scripts/mac/autoinstall.sh` pulls the repo and, when the app changed or every 5 days, builds it with `xcodebuild` and installs it with `xcrun devicectl`. It needs the Mac awake and logged in, Xcode signed in to your Apple ID, and the iPhone on a cable or on the same Wi-Fi with **Connect via network** ticked in **Xcode › Window › Devices and Simulators** (unlocked when the install runs). The log is in `~/Library/Logs/SlothCinema-autoinstall.log`. To stop it: `bash scripts/mac/install-autoinstall.sh --remove`.

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
