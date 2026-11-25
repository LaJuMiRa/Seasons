# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-25

### Added

- Separate options "Pile Up on Windows" and "Pile Up on Dock", and "Pointer Pushes Effects Away" (turn off to keep the cursor from bouncing or carving anything).
- "Hide Effects in Apps": the effects disappear while a chosen app is in front (#4).

### Changed

- Compact menu: rarely used switches moved into a new "Options" submenu, the main menu went from about 30 to 14 rows.
- Several displays share one wind, and effects fly across the edge between neighbouring displays instead of ending at the edge (#3).
- Piles follow the rounded corners of windows and the Dock instead of floating over them.
- Wiping fast with the cursor now leaves a soft, natural edge instead of a bar.
- On battery and in Low Power Mode the overlay renders at 1x instead of Retina resolution (less GPU load, #2).

### Fixed

- Snow on a window stays hidden behind a window that opens above it instead of showing through.

## [1.1.0] - 2026-11-20

### Added

- Option "Only on Desktop, Not Over Full-Screen Apps": hides the effects on each screen while it shows a full-screen app (off by default).

## [1.0.0] - 2026-11-19

### Added

- Menu bar app with a click-through overlay on every display, on all Spaces and next to full-screen apps.
- Effects: snow, autumn leaves, rain (splashes, water films, puddles) and cherry blossoms; flowers growing along the Dock, combinable with any effect.
- Piles on the screen bottom, the Dock and visible window tops, with angle-of-repose spreading and per-edge maximum heights.
- Pointer interaction: pushes particles, carves piles and throws material up; bends and sweeps away flowers.
- Snow slides off moving windows and falls when a window closes or minimizes; piles survive Space switches.
- Automatic effect by season, with optional rain in summer.
- Amount levels: Off, Light, Medium, Heavy, Variable. Pause, Clear Now, and a Melt Away switch.
- Hard maximum pile height per edge (snow: 30 pt on the screen bottom, 24 pt on the Dock, 20 pt on windows).
- Options: pile up on windows and Dock, hide in screenshots and screen sharing, launch at login.
- English and German localization.
- Power saving: pauses on lock, sleep, screen saver and occlusion, and when idle; 30 fps on battery and 20 fps in Low Power Mode.
- `build.sh`, `release.sh`, GitHub release workflow and Homebrew cask template.
