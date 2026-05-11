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
