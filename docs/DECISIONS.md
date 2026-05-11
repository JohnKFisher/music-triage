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
