# Decisions

Use this file as a concise decision log for project-specific architectural, behavioral, tooling, and scope decisions.

## 2026-05-10 — App uses a shared pure-Swift core plus an iOS shell
Status: approved

The playback verification state machine and action/membership models live in a shared `Sources/MusicTriageCore` module so they can be tested with `swift test` outside simulator/device workflows. The iOS app target compiles those same sources directly and keeps Apple-framework integration in the app layer.

## 2026-05-10 — V1 tagging keeps a strict write boundary
Status: approved

`KEEP` and `DELETE` only unlock after the now-playing state becomes trusted, and fallback metadata-only tracks stay disabled unless the app can resolve a unique song safely enough to write. This preserves the core promise over broad source coverage.

## 2026-05-10 — Fixed playlist names with remembered IDs
Status: approved

V1 uses fixed playlist names (`Keepers` and `Music Triage`), chooses one exact-match playlist deterministically when duplicates exist, and remembers that stable playlist ID for future writes. Custom naming is explicitly deferred.

## 2026-05-11 — On-device tagging stays enabled when enrichment fails
Status: approved

If Music Triage can safely resolve the current song itself, tagging stays available even when library-membership or playlist-membership enrichment fails. Those secondary lookup misses should degrade pills and helper text, not block the core action path.

## 2026-05-11 — iPhone builds use native launch and icon assets
Status: approved

The app now ships with a real launch storyboard and asset-catalog app icon instead of relying on a resource-only shell. This avoids real-device compatibility letterboxing and blank icons on modern iPhones.

## 2026-05-11 — Production UI drops the clickwheel influence
Status: approved

The live app UI now leans back toward pure Neon Horizon and no longer uses the retro clickwheel-style transport cluster. The transport and auto-skip controls are compact utility elements so the whole tagging screen fits on one iPhone screen with KEEP and DELETE still visually dominant.

## 2026-05-11 — Tagging now requires a deliberate hold
Status: approved

KEEP and DELETE now require a roughly 0.25 second press instead of a light tap. This still reduces accidental tagging while keeping the interaction faster and less fatiguing than the original 0.5 second hold.

## 2026-05-11 — Progress bar can scrub playback and landscape is temporarily disabled
Status: approved

The now-playing progress strip is now an active scrubber, and the app is portrait-only for the time being. Landscape support is intentionally paused rather than redesigned in place.

## 2026-05-11 — Non-library Apple Music tracks add to library but do not hit Keepers
Status: approved

When the app can safely resolve a currently playing Apple Music catalog track that is not yet in the user’s library, the left action becomes yellow `ADD` and only adds the song to the library. Library tracks keep the existing green `KEEP` behavior that writes to Keepers, and `DELETE` remains intentionally disabled for non-library tracks.

## 2026-10-29 — CarPlay shares the verified companion workflow
Status: approved

The CarPlay scene uses the same `AppModel`, current system music player, verification engine, and MusicKit write path as iPhone. It presents a short native list with track status, transport controls, and KEEP / TRIAGE / ADD actions. Tagging in CarPlay requires confirmation tied to the displayed full track reference and a fresh playback verification before writing. CarPlay never prompts for Apple Music permission; initial access setup happens on iPhone while parked. Scene activity is tracked separately so CarPlay does not keep the iPhone display awake.

## 2026-10-29 — Personal use informs any public release
Status: approved

Music Triage is currently a personal-use app and is not intended for App Store distribution. The owner will use the app personally to decide whether a public app is worth pursuing later.

## 2026-10-29 — Tagging pauses when library status is unverified
Status: approved; supersedes the 2026-05-11 enrichment-failure decision

When the app can resolve a song but cannot verify whether it is in the user's Apple Music library, tagging actions stay disabled until a retry or safe fallback confirms the status. Catalog and library identifiers must be mapped through MusicKit's library relationship; they are not assumed to be interchangeable.

## 2026-10-29 — Playlist tagging does not auto-remove the opposite entry
Status: approved

`KEEP` and `DELETE` add the song to their destination playlist and leave any entry in the other playlist alone. MusicKit does not expose an atomic single-entry removal, and rebuilding a playlist can overwrite concurrent edits. The app reports known overlap and leaves manual cleanup to the user.

## 2026-10-29 — Use the Sidelark Labs bundle identifier
Status: approved

The iOS bundle identifier is `com.sidelarklabs.musictriage`. This replaces `com.jkfisher.musictriage` and creates a separate app identity; app-specific preferences are not migrated, while the Apple Music playlists remain available and are rediscovered by name.
