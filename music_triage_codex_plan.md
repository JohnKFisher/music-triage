# Music Triage

## Overview

Music Triage is a personal-use iOS companion app for Apple Music focused on rapid, reliable music curation while listening.

The app is intentionally narrow in scope:
- show the currently playing Apple Music track
- allow the user to mark songs as KEEP or DELETE
- reflect those actions into real Apple Music playlists/library state
- optimize for correctness over speed
- optimize for low-attention driving usage

This is NOT:
- a full music player
- a queue browser
- a library manager
- a recommendation engine
- a social app
- an analytics platform

The core principle is:

> Never let the user act on the wrong song.

---

# App Name

Music Triage

---

# Playlist Behavior

## Keepers Playlist
Playlist name:
`Keepers`

Behavior:
- KEEP adds the song to Keepers
- If the song is not already in the Apple Music library, KEEP should also add it to the library
- If the song is already in Music Triage, attempt to remove it from Music Triage

## Music Triage Playlist
Playlist name:
`Music Triage`

Behavior:
- DELETE adds the song to Music Triage
- If the song is currently in Keepers, attempt to remove it from Keepers
- DELETE does NOT remove the song from the Apple Music library automatically in V1

## Playlist Creation
If either playlist does not exist:
- create it automatically

---

# Core UX Philosophy

Music Triage should feel:
- focused
- fast
- reliable
- calm
- stylized
- driving-friendly

It should NOT feel:
- cluttered
- corporate
- settings-heavy
- overly technical
- like a full media player

---

# Primary Use Case

User is:
- listening to Apple Music
- often driving
- rapidly curating songs
- making quick keep/delete decisions

The app should prioritize:
- large interaction targets
- correctness
- confidence
- low cognitive load

---

# Main Screen Layout

Single-screen app.

No tabs.

No navigation hierarchy.

No visible app chrome beyond subtle branding.

## Visual Hierarchy

### Primary
- KEEP button
- DELETE button

### Secondary
- Song title
- Album art

### Tertiary
- Artist name
- Progress bar
- Membership status pills
- Playback controls

---

# Visual Style

Primary target:
- dark mode

Light mode:
- supported but secondary

Style direction:
- custom stylized UI
- cool
- polished
- not stock Apple Settings-looking

The ONLY intentionally silly element:
- cold-launch splash screen

---

# Splash Screen

Only shown on true cold launch.

NOT shown when:
- returning from background
- app switching

Contents:
- image of John K. Fisher making a silly face
- caption:
  `a John K. Fisher joint`

Duration:
- extremely fast
- should not delay usability

---

# Buttons

## KEEP
Visual:
- green-accented
- iconographic
- equal prominence to DELETE

Behavior:
- add to library if needed
- add to Keepers
- attempt removal from Music Triage
- optionally auto-skip afterward

## DELETE
Visual:
- red-accented
- iconographic
- equal prominence to KEEP

Behavior:
- add to Music Triage
- attempt removal from Keepers
- optionally auto-skip afterward

---

# Auto-Skip

Optional toggle:
`Auto-skip after tagging`

Default:
OFF

Behavior:
- after successful KEEP or DELETE
- wait for confirmation animation/haptic
- then skip to next song

---

# Confirmation Feedback

Actions should feel unmistakable.

Feedback should include:
- tasteful animation
- haptic feedback
- subtle color pulse
- confirmation overlay/toast

Repeated taps on already-tagged songs:
- do NOT toggle state
- simply reconfirm visually

Distinct haptics:
- KEEP = softer/affirmative
- DELETE = firmer/heavier

---

# Playback Verification Model

This is the MOST IMPORTANT PART of the app.

The app must prioritize correctness over responsiveness.

## Verification Flow

When a track changes:
1. detect change
2. enter verification state
3. disable actions
4. show subtle spinner
5. confirm stable playback identity
6. enable actions

## Confirmation Signals

Track is considered stable when:
- track ID stable
- title stable
- artist stable
- stable for approximately 1–2 seconds

Artwork changes alone should NOT invalidate confidence.

Playback state changes alone should NOT invalidate confidence.

## During Verification

UI behavior:
- subtle spinner only
- no loud warnings
- buttons disabled

---

# Transition Handling

Apple Music automix/crossfade behavior may cause ambiguity.

During transitions:
- update visuals quickly
- but keep actions disabled until confidence restored

Goal:
- user must NEVER accidentally tag the wrong track

---

# Cached Playback State

If playback disappears temporarily:
- retain last confirmed song visually
- grayscale/fade the UI
- disable actions
- show subtle spinner
- automatically attempt recovery

---

# Membership State

Display subtle pills/icons for:
- KEEPER
- TRIAGED
- UNSORTED

If overlap temporarily exists due to playlist sync timing:
- show accurate real state
- do not hide overlap

Source of truth:
- query Apple Music state directly whenever possible
- avoid stale local assumptions

---

# Progress Bar

Include:
- thin subtle playback progress bar

Purpose:
- subconscious confirmation of active playback state

Should NOT dominate UI.

---

# Playback Controls

Allowed:
- play/pause
- next
- previous

These are secondary utilities only.

Music Triage is NOT a player app.

---

# Orientation

Primary:
- portrait

Landscape:
- not forbidden
- not prioritized

---

# Screen Behavior

Keep screen awake while app open.

Do NOT auto-hide controls.

---

# Action Cooldowns

Prevent accidental double taps.

After successful KEEP/DELETE:
- short cooldown (~1 second)
- temporarily disable repeated action spam

---

# Error Handling

If playlist/library operation fails:
- subtle failure notification
- distinct failure haptic
- temporarily disable actions
- automatically retry/recover if possible

Avoid:
- giant modal dialogs
- scary alerts
- technical jargon

---

# Network Philosophy

Do NOT aggressively micromanage network state.

Attempt actions whenever:
- track identity confidence is sufficient

Even if:
- network state uncertain

Trust Apple Music sync behavior where possible.

---

# Debug Overlay

Allowed but subtle.

Possible contents:
- verification state
- operation latency
- track ID
- playback state

Must remain visually unobtrusive.

---

# Technical Assumptions

Use:
- SwiftUI
- MusicKit
- MediaPlayer framework
- MPMusicPlayerController.systemMusicPlayer

The app should piggyback on:
- whatever Apple Music is currently playing

Supported sources:
- playlists
- albums
- stations
- radio
- Siri playback
- autoplay
- streamed songs
- downloaded songs
- matched/uploaded songs

---

# Track Identity Rules

High confidence:
- track ID
- title
- artist

Low-confidence tracks:
- may allow cautious actions if enough metadata exists
- otherwise disable actions

Never guess blindly.

---

# Scope Control Rules

DO NOT:
- turn this into a full player
- add browsing
- add recommendations
- add social features
- add cloud sync
- add analytics dashboards
- add queue management
- add playlist management UI
- add account systems

This is intentionally:
- narrow
- focused
- weirdly specific
- utility-oriented

---

# Development Phases

# Phase 1 — Mockups

Before major implementation:
- generate multiple visual mockups

Directions:
- Apple Music-inspired
- minimalist dark glass
- retro iPod influence
- utility-focused
- stylized/cool hybrid

Mockups should explore:
- button sizing
- spacing
- typography
- artwork prominence
- confirmation states
- stale/disabled states

---

# Phase 2 — Core Playback Detection

Implement:
- now playing detection
- verification state machine
- stable track confidence model
- recovery handling

Acceptance criteria:
- actions never fire on wrong song during rapid transitions

---

# Phase 3 — Playlist Integration

Implement:
- Keepers playlist creation
- Music Triage playlist creation
- add/remove flows
- membership querying

Acceptance criteria:
- playlist changes reflected correctly in Apple Music

---

# Phase 4 — UX Polish

Implement:
- haptics
- animations
- confirmation overlays
- stale-state visuals
- cooldown handling
- splash screen

---

# Phase 5 — Optional Enhancements

Possible later additions:
- swipe gestures
- Apple Watch support
- direct library deletion if Apple APIs ever allow it
- CarPlay investigation
- settings/preferences UI
- advanced diagnostics

These are NOT V1 priorities.

---

# Final Product Goal

The final app should feel like:

> a weirdly polished personal music curation appliance

Not:
- a startup
- a platform
- a commercial product
- a general-purpose music app
