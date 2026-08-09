# AnterSurf Mobile

Privacy-first browser for Android — Flutter port of AnterSurf 27 "Starship Explorer".

## Features

- **Multi-tab browsing** with swipeable tab strip, close/reopen tabs
- **Omnibox** with search suggestions (DuckDuckGo default, Google, Bing, Brave, Yahoo, Ecosia, custom engine)
- **New Tab Page** with clock, date, greeting, logo, and top-sites speed dial grid
- **Tracking Radar** — live per-tab network request feed with privacy score
- **AnterGet downloads** — curl/libcurl-based download manager (Chrome-mobile-style page) with pause, resume (HTTP Range), cancel, retry, open, progress, speed and ETA, plus parallel download queue
- **Bookmarks & History** — local SQLite storage, no cloud
- **Settings** — search engine, theme (dark/light/system), accent color, corner radius, startup behavior, font size, tracking protection levels, DNT, cookie blocking, location policy, suggestions, UI toggles, clear browsing data
- **Find in page**, confirm-on-close, session restore (last session / home page / new tab)
- Local-only: bookmarks, history, downloads, and top sites stored in encrypted-on-device SQLite

## Structure

```
lib/
  main.dart                  # entry point
  app_theme.dart             # theme engine (dark/light, accent, radius)
  controllers/
    browser_controller.dart  # tabs, webviews, navigation, radar, find
  models/
    browser_tab.dart
    bookmark.dart
    history_entry.dart
    download_task.dart
  screens/
    browser_screen.dart      # main browser shell
    ntp_screen.dart          # new tab page
    settings_screen.dart
    side_panel_screen.dart   # bookmarks / history
    downloads_screen.dart    # full Chrome-style downloads page (AnterGet)
    radar_screen.dart
  services/
    settings_service.dart    # persisted settings (shared_preferences)
    app_database.dart        # SQLite (bookmarks/history/downloads/top sites)
    search_service.dart      # engines + suggestion API
    anterget_service.dart    # curl/libcurl download engine (queue, range chunks, resume)
  widgets/
    omni_bar.dart
    tab_strip.dart
    bottom_toolbar.dart
    top_sites.dart
```

## Requirements

- Flutter SDK (3.19+ recommended) with Android toolchain
- Android Studio / Android SDK (compileSdk 34)

## Build

```bash
cd antersurf-mobile
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## Run

```bash
flutter run            # on a connected device/emulator
flutter build apk      # debug APK
```

## Notes

- **AnterGet engine**: every download is transferred by libcurl (`flutter_curl`) in a background isolate. Files are fetched in 1 MiB ranged chunks (bounded memory), pauses resume from the exact byte using `Range` headers, and progress/speed/ETA are computed from received bytes — mirroring the desktop AnterGet which drives the `curl` CLI. Completed files live in `AnterSurf Downloads/` on the device and can be opened with the system file viewer.
- Search suggestions use the active engine's suggestion endpoint (DuckDuckGo by default).
- No telemetry, no accounts, no cloud sync — same privacy posture as the desktop build.
