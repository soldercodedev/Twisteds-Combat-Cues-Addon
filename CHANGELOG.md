# Changelog

All notable changes to Twisteds Combat Cues are recorded here.

## [1.2.0-beta.2] - 2026-07-12

Compatibility pass for **WoW Midnight (12.0.7)** and its new "secret value" system,
plus several fixes uncovered while testing in instanced content.

### Fixed
- **Midnight "secret value" errors.** Restricted values that Blizzard now returns in
  combat/instances (unit range, threat, scroll-frame metrics) can no longer be compared
  or math'd by addon code. Every such read is now guarded, so cues and the UI no longer
  throw *"attempt to compare / perform numeric conversion on a secret value."*
- **Cue Manager scrolling was broken on every page except Getting Started.** The mouse
  wheel, scrollbar, and thumb-drag relied on `GetVerticalScrollRange()`, which becomes a
  secret value once a page has shown restricted data. Scroll extents are now derived from
  frame heights, so scrolling works on all pages again.
- **Focus call-out (Party/Raid chat) silently failed in combat.** It was being sent from
  inside the protected execution of the secure `/focus` action, where chat is blocked.
  The message is now deferred one frame so it sends as ordinary code, in or out of combat.
- **Marker palette show/hide is now remembered across reloads.** Closing it with Escape
  used to be ignored, so it would reappear on the next `/reload`.

### Changed
- **Range cues now use exact distance.** "Healer/Tank in range" and the range conditions
  use `UnitDistanceSquared` (which stays readable where `UnitInRange` goes secret), so
  they keep working in dungeons, raids, and scenarios. A small combat-reach compensation
  is applied so "40 yd" matches the game's real (edge-to-edge) range.

### Added
- **"Tank in range" diagnostic row**, alongside the existing healer readout. Range
  readouts now show live yardage.
- **In-app changelog** — a "What's New" page in the sidebar renders the bundled
  changelog (generated from `CHANGELOG.md` at package time).
- **Discord community link** in the manager footer (opens a copy dialog with the
  invite, since addons can't open a browser).

### Removed
- **Focus call-out target-name wildcards (`%t` / `%target`).** The focus's name is a
  secret value in combat/instances, so it's no longer read. The `{rt}` marker wildcard
  remains; any `%t`/`%target` left in existing messages is stripped automatically.

## [1.2.0-beta.1] - 2026-07-11

- Initial public beta.
