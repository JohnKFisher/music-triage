# Where We Stand

Use this file as a concise project status snapshot for the current version, what works, known limitations, and next priorities.

## Music Triage

- Version/build: `0.1.0 (1)`
- Overall status: CarPlay integration code now extends the iPhone workflow with a native companion screen, alongside its launch screen, app icon, and one-screen Neon Horizon layout.
- Distribution direction: personal use for now; personal experience will determine whether to pursue a public release later.

## What works now

- Single-screen SwiftUI app shell with hold-to-tag KEEP / DELETE actions, compact transport controls, compact auto-skip control, a scrubbable progress strip, membership pills, onboarding sheet, splash overlay, dismissible hidden debug overlay, and a non-letterboxed launch path on real iPhones.
- Shared playback verification core with tested strong-ID and fallback-metadata timing rules.
- MusicKit-based playlist resolution and creation. `KEEP` and `DELETE` add to the target playlist without rebuilding or removing entries from the opposite playlist.
- Catalog-to-library ID mapping, full-page membership scans, strict metadata checks, and disabled tag actions until library status can be verified.
- Trusted Apple Music catalog tracks that are not yet in the library now switch the left action to yellow `ADD`; that path adds the song to the library only, while library tracks keep the existing green `KEEP` to Keepers behavior and `DELETE` stays disabled for non-library tracks.
- Auto-skip preference persistence and keep-screen-awake behavior while active playback is running.
- Native CarPlay scene registration with a compact current-track/action list and existing system-player transport controls.
- CarPlay tagging actions require a second confirmation for the displayed song, then recheck the currently verified track before writing.
- Fifteen first-round mockup concepts are checked in as a preview gallery plus a short review note.
- App icon assets and launch storyboard now compile into the iPhone target.
- The live layout now puts transport controls above the membership pill row and removes the header tagline for a tighter top section.

## Partial / not yet proven

- A generic iOS build with code signing disabled succeeds. CarPlay runtime validation has not been run.
- CarPlay requires a provisioning profile that contains the approved audio entitlement; cold launch, locked-phone access, and simultaneous iPhone/CarPlay lifecycle behavior still need device validation.
- Earlier interface fixes were driven by a real iPhone report plus screenshots rather than direct device control from this machine.
- Real Apple Music playback behavior, permission prompting, playlist writes, and transition safety still need another on-device validation pass after this fix set.
- Songs may remain in both tagging playlists; known overlap is reported and manual cleanup is left to the user.
- The current fix set has not been built or tested on an iPhone or CarPlay display. Signing, entitlement, and MusicKit account behavior still need device validation.

## Known limitations / trust warnings

- This machine’s simulator/CoreSimulator state is unhealthy, so simulator runtime validation was not possible in this session.
- Real device signing still requires a proper Apple developer setup, the MusicKit app service, and the approved CarPlay Audio capability in the App ID and provisioning profile.
- Xcode automatic signing needs a provisioning profile with the approved CarPlay Audio capability before a signed install; Apple Music access and account quirks also need another device pass.
- The generic build still shows one benign Swift concurrency warning around the auto-skip toggle binding; an attempted cleanup triggered a Swift 6.3.1 compiler crash, so the safer temporary state is to keep the warning.
- Landscape mode is intentionally disabled for now and should be treated as a deferred redesign area rather than a supported layout.

## Recommended next priorities

- Build and install on iPhone, then validate the new CarPlay scene in CarPlay Simulator and on a real vehicle display.
- With the iPhone locked and Music Triage inactive, verify track refresh, authorization handling, confirmation invalidation on track change, playlist writes, and scene disconnect/reconnect behavior.
- Reinstall on the iPhone and verify the live control stack: transport, auto-skip, membership pill, and full KEEP/DELETE actions.
- Verify the new deliberate hold-to-tag interaction, stronger haptics, red DELETE success toast, scrubbable progress bar, and portrait-only behavior.
- Verify catalog-to-library status for catalog-only, library, unknown, and unavailable relationship responses, plus playlist membership when entries span multiple pages.
- Run the app on a real iPhone with Apple Music access enabled and validate the plan’s playback-trust scenarios across normal playback changes.
- Tighten anything Apple Music permission or MusicKit capability setup still needs in practice after that second phone pass.
