// Top-level build file for the Kastrava Android app (native Kotlin/WebView).
// This is a separate project from the Electron desktop builds — Electron
// cannot produce APKs, so Android ships as its own app with the same brand,
// search defaults, tracker blocking approach and Premium license server.
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
