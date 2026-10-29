# Working Changelog

Internal source material for public release notes; keep entries understandable to non-technical users.

## Unreleased

### Added
- [needs review] CarPlay support shows the current song and transport controls, with a song-specific confirmation before KEEP, TRIAGE, or ADD.

### Changed
- Changed the app bundle identifier to `com.sidelarklabs.musictriage`; local preferences do not migrate from the previous app identity.
- Playlist tags no longer try to remove the song from the opposite playlist; known overlap is reported for manual cleanup.
- Tag actions pause when Apple Music cannot verify whether a resolved catalog song is already in the library.

### Fixed
- Bound phone and CarPlay actions to the full observed track reference, including album metadata and playback generation.
- Recheck track identity before writes and keep showing the result for the song whose write completed, even if playback has moved on.
- Verify playback store-ID matches against track metadata and scan all search and playlist pages before making uniqueness or membership claims.
- Retry transient song resolution and refresh membership when an interface becomes active.
- Clear interrupted playback candidates and preserve onboarding completion after sheet dismissal.
- Add an accessibility default action and spoken label for the hold-to-tag controls.

### Reliability / Data Safety
- Removed playlist rebuild cleanup because it could truncate later pages or overwrite concurrent Music edits.

### Internal / Maintenance
- 
