# Where We Stand

Use this file as a concise project status snapshot for the current version, what works, known limitations, and next priorities.

## Music Triage

- Version/build: `0.1.0 (1)`
- Overall status: first functional iPhone-first implementation is in the repo and builds for generic iOS.

## What works now

- Single-screen SwiftUI app shell with KEEP / DELETE actions, transport controls, progress strip, membership pills, onboarding sheet, splash overlay, and hidden debug overlay.
- Shared playback verification core with tested strong-ID and fallback-metadata timing rules.
- MusicKit-based playlist resolution, playlist creation, optimistic membership updates, and best-effort opposite-playlist cleanup.
- Auto-skip preference persistence and keep-screen-awake behavior while active playback is running.
- Fifteen first-round mockup concepts are checked in as a preview gallery plus a short review note.

## Partial / not yet proven

- The repo build is verified with a generic `iphoneos` build, not a live iPhone run.
- Real Apple Music playback behavior, permission prompting, playlist writes, and transition safety still need on-device validation.
- Playlist cleanup uses MusicKit best-effort editing and may fail on some user-owned playlists; the primary tag action still succeeds first when possible.

## Known limitations / trust warnings

- This machine’s simulator/CoreSimulator state is unhealthy, so simulator runtime validation was not possible in this session.
- Real device signing still requires a proper Apple developer setup and MusicKit enabled for the App ID.
- The repo is now clean enough to install from Xcode on a personal iPhone, but the first real-device run is still where Apple Music capability and account quirks will surface.

## Recommended next priorities

- Run the app on a real iPhone with Apple Music access enabled and validate the plan’s playback-trust scenarios.
- Choose the preferred visual direction from the 15 checked-in mockup variants, then tighten the production styling accordingly.
- Do a real-phone pass and tighten anything Apple Music permission or MusicKit capability setup still needs in practice.
