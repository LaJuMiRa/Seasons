# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

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
