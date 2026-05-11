# Where We Stand

Use this file as a concise project status snapshot for the current version, what works, known limitations, and next priorities.

## Music Triage

- Version/build: `0.1.0 (1)`
- Overall status: first functional iPhone-first implementation is in the repo, now with a native launch screen, a real app icon, and a tighter one-screen Neon Horizon layout for real iPhones.

## What works now

- Single-screen SwiftUI app shell with hold-to-tag KEEP / DELETE actions, compact transport controls, compact auto-skip control, a scrubbable progress strip, membership pills, onboarding sheet, splash overlay, dismissible hidden debug overlay, and a non-letterboxed launch path on real iPhones.
- Shared playback verification core with tested strong-ID and fallback-metadata timing rules.
- MusicKit-based playlist resolution, playlist creation, optimistic membership updates, and best-effort opposite-playlist cleanup.
- Trusted Apple Music catalog tracks that are not yet in the library can still use `KEEP`; that path adds the song to the library and Keepers while leaving `DELETE` disabled by design.
- Auto-skip preference persistence and keep-screen-awake behavior while active playback is running.
- Fifteen first-round mockup concepts are checked in as a preview gallery plus a short review note.
- App icon assets and launch storyboard now compile into the iPhone target.
- The live layout now puts transport controls above the membership pill row and removes the header tagline for a tighter top section.

## Partial / not yet proven

- The repo build is verified with a generic `iphoneos` build, and the current fixes were driven by one real iPhone report plus screenshots rather than by direct device control from this machine.
- Real Apple Music playback behavior, permission prompting, playlist writes, and transition safety still need another on-device validation pass after this fix set.
- Playlist cleanup uses MusicKit best-effort editing and may fail on some user-owned playlists; the primary tag action still succeeds first when possible.

## Known limitations / trust warnings

- This machine’s simulator/CoreSimulator state is unhealthy, so simulator runtime validation was not possible in this session.
- Real device signing still requires a proper Apple developer setup and MusicKit enabled for the App ID.
- The repo is now clean enough to install from Xcode on a personal iPhone, but Apple Music capability and account quirks can still surface on the next device pass.
- The generic build still shows one benign Swift concurrency warning around the auto-skip toggle binding; an attempted cleanup triggered a Swift 6.3.1 compiler crash, so the safer temporary state is to keep the warning.
- Landscape mode is intentionally disabled for now and should be treated as a deferred redesign area rather than a supported layout.

## Recommended next priorities

- Reinstall this build on the iPhone and verify the whole live control stack is visible at once: transport, auto-skip, membership pill, and full KEEP/DELETE actions.
- Verify the new deliberate hold-to-tag interaction, stronger haptics, red DELETE success toast, scrubbable progress bar, and portrait-only behavior.
- Run the app on a real iPhone with Apple Music access enabled and validate the plan’s playback-trust scenarios across normal playback changes.
- Tighten anything Apple Music permission or MusicKit capability setup still needs in practice after that second phone pass.
