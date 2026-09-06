# Design: History Detail — SCATT Target + Per-Shot Replay

**Date**: 2026-09-06
**Branch**: `PreProduction3_Design_Adjust`
**Approved via**: Visual companion mockup v3 (Hybrid + SCATT Replay)

## Goal

Redesign the session detail screen (History tab) following the SCATT reference
(`scatt_frame_1_96.jpg`), with a per-shot trajectory replay played back on the
target itself — progressive trace drawing under a moving dot.

## Layout (approved mockup v3)

Vertical column, top to bottom:

1. **Header** — back button, session title, delete (unchanged)
2. **Tab bar** — 3 tabs: `TARGET` (new, default) | `SHOT DATA` | `ANALYSIS`
3. **Score row** — left: SCORE of selected shot (large); right: MATCH TOTAL
   (session average, smaller)
4. **Target area** — concentric-ring target (SCATT style), replay trace drawn
   on it: HOLD (red `0xFFFF4444`) → PRESS (yellow `0xFFFFFF44`) → RECOIL
   (cyan `0xFF44FFFF`), with a moving dot. When not playing, the full trace
   is shown with the dot resting at its last position.
5. **Selected-shot card** — "SHOT n" + total score + phase breakdown
   (HOLD · PRESS · RECOIL)
6. **Playback controls** — Play/Pause toggle, seek scrubber, elapsed time
   (e.g. `1.7s`), reset button
7. **Shot selector** — horizontal row of circular chips (shot number);
   selected chip highlighted with score color. Persist across tabs, as today.

Tabs 2 and 3 reuse existing content without change:
- `SHOT DATA` → `_ShotDetailPanel` (3-phase chart) as-is
- `ANALYSIS` → `AnalysisTab` (raw-IMU trajectory replay) as-is

## New Widget: `TargetReplayView`

File: `ssa_app/lib/widgets/target_replay_view.dart`

Replaces `ReplayShotWidget` (which is deleted; its replay role is fully
absorbed). Structure:

- **State**: play/pause flag, playback progress (0..1), derived dot position
  and segment index from `ShotTraceGeometry`
- **Target painter**: 5 concentric rings, ring colors from STSYS theme
  surfaces; geometry auto-scaled by `ShotTracePath.maxDeviation` so (0,0)
  is the ideal-aim center — same math as the existing painters
- **Trace painter**: progressive colored segments; full trace when stopped,
  partial up to current progress when playing
- **Controls**: `AnimationController` (2500 ms per shot, same as current
  replay) + `Timer` at 16 ms tick driving progress; scrubber allows seeking
  both directions while playing or paused
- **Playback duration**: 2500 ms (unchanged from current replay)

## Data Flow

`SessionDetailScreen` (has `SessionLog`) → selected `ShotResult` →
`ShotTraceGeometry.fromShot(shot)` → ordered points + phase boundaries →
`TargetReplayView` renders and animates. No database or provider changes.

## Theme

STSYS identity only: `#FFB693` primary accent for controls/score highlights,
existing surface palette for rings/background. Mockup's SCATT green is
indicative only, not adopted.

## Error / Edge Cases

- Shot with no phase traces (`holdX` etc. null/empty): target shows rings +
  "NO TRACE DATA FOR THIS SHOT" message, controls disabled
- Single-point trace: dot jumps to the point, no path drawing
- Tab switch away: widget disposed, timer/controller cleaned up (standard
  `dispose()`)

## Testing

- **Unit**: `TargetReplayView` state logic — progress mapping to point index
  and phase, seek clamp, reset behavior (extracted pure helpers where possible)
- **Widget**: 3-tab bar renders and switches; default tab is TARGET; score
  row shows selected-shot score and session average; tapping a chip selects
  the shot and updates score row + target; empty-trace shot shows fallback
- **Regression**: existing geometry and session-detail layout tests keep
  passing; `ReplayShotWidget` references removed

## Out of Scope

- SCATT's series/qualification grouping (single flat shot list, as today)
- Live-fire capture changes, database schema changes
- ANALYSIS tab (raw IMU replay) behavior changes
