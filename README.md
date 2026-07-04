# Music Triage

Music Triage is a personal iPhone app for quickly marking the currently playing Apple Music song as something to keep, triage, or add to the library without acting on the wrong track.

It is intentionally narrow: it is not a player, not a library browser, and not a general music-management app. It is a small companion for an Apple Music listening workflow where the safest action is sometimes to wait until the current track identity is trusted.

For more from Sidelark Labs, visit <https://sidelarklabs.com>.

## Current Status

Music Triage is a mostly complete personal project at version `0.1.0 (1)`.

The practical install path is still Xcode on a real iPhone. There is no polished packaged release flow yet, and the core Apple Music behavior still depends on real-device testing, Apple Music access, subscription state, and MusicKit-capable signing.

## What It Does

- Watches the currently playing Apple Music track.
- Keeps tagging actions disabled until the app trusts the current track identity.
- Sends trusted library tracks to the `Keepers` playlist with `KEEP`.
- Sends trusted library tracks to the `Music Triage` playlist with `DELETE`.
- Shows `ADD` for trusted Apple Music catalog tracks that are not yet in the library.
- Adds non-library catalog tracks to the library without also sending them to `Keepers`.
- Disables `DELETE` for tracks that are not already in the library.
- Tries best-effort cleanup of the opposite playlist after a successful tag.
- Supports transport controls, auto-skip, a scrubbable progress strip, membership pills, onboarding, and a portrait-first one-screen iPhone layout.

## Core Rule

The app is built around one rule:

> Never let the user act on the wrong song.

That rule matters during crossfades, pauses, metadata lag, and now-playing transitions. Music Triage should hesitate instead of confidently writing the wrong song to a playlist.

## Running On iPhone

1. Open `Music Triage.xcodeproj` in Xcode.
2. Connect an iPhone and choose it as the run destination.
3. In the `Music Triage` target, open `Signing & Capabilities`.
4. Set your Team.
5. Keep the bundle identifier as `com.jkfisher.musictriage` unless Xcode requires a unique identifier for your account.
6. Make sure the App ID has the `MusicKit` app service enabled in the Apple Developer portal.
7. If Xcode offers to add the MusicKit capability for the target, accept it.
8. Build and run on the phone.

The app uses `NSAppleMusicUsageDescription` and waits to ask for Apple Music access until you try to tag a song.

## Testing

The shared verification core can be tested without running the iPhone app:

```sh
swift test
```

Meaningful end-to-end validation still requires a real iPhone with Apple Music access.

## Repository Shape

- `MusicTriageApp/` contains the SwiftUI iPhone app, MusicKit integration, playlist writes, and app UI.
- `Sources/MusicTriageCore/` contains the pure Swift playback-verification and action-state logic.
- `Tests/MusicTriageCoreTests/` covers the core trust rules outside the full app runtime.
- `docs/WHERE_WE_STAND.md` is the concise project status snapshot.
- `docs/DECISIONS.md` records durable project decisions.

## Known Limitations

- Simulator is not enough to prove the core Apple Music behavior.
- `DELETE` does not remove a song from the Apple Music library in this version; it sends the song to the `Music Triage` playlist.
- Playlist cleanup is best-effort and may fail even when the primary tag action succeeds.
- Landscape support is intentionally disabled for now.
- App Store distribution, notarized packaging, and public release flow are not set up.

## AI Assistance

This project was built with heavy AI assistance using tools like Codex. The product direction, workflow decisions, and testing priorities are John's.
