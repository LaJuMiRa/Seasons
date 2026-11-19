# Architecture

Seasons is a Swift package with two targets and two test targets.

| Target | Platform | Contents |
|---|---|---|
| `SeasonsCore` | any (Foundation only, no AppKit, no Metal) | particles, ledges (height fields), ledge layout from window geometry, cursor wiping, slide-off, wind, intensity, seasons, flowers, render batch (sprites and pile mesh), effect parameter tables |
| `Seasons` | macOS 14+ | app lifecycle, status menu, settings, overlay windows, Metal renderer, window and Dock detection, power and lock monitoring, login item, localization |
| `SeasonsCoreTests` | any | collision, accumulation, wiping, slide-off, removal, determinism, layout, seasons, flowers |
| `SeasonsAppTests` | macOS | status menu actions and settings persistence |

## Data flow

```
WindowTracker (CGWindowList, background queue, 8–30 Hz)
        │ global window rects (Quartz coords)
        ▼
OverlayManager ── DockLocator (visibleFrame + Dock prefs)
        │ per screen
        ▼
OverlayController ── converts to screen-local, y-up coordinates
        │ ScreenGeometry
        ▼
LedgeLayout.compute ──► [LedgeSpec] ──► SimulationWorld.updateLedges
                                              │
CADisplayLink tick ─► SimulationWorld.step(dt, mouse, intensity)
                                              │
                      SimulationWorld.buildRenderBatch ─► MetalRenderer
```

`AppModel` holds the `Settings` (persisted in UserDefaults) and derives the visible scene (manual choice or season). `SystemMonitor` reports lock, sleep, screen saver and fast-user-switching states plus the frame rate for the current power source.

## Decisions

### Rendering: Metal with procedural shaders (not SpriteKit)

- **Performance:** all particles are drawn in one instanced draw call (48 bytes per sprite), and piles in one triangle draw. SpriteKit would add a scene graph, per-node overhead and its own update loop, while the simulation already lives in `SeasonsCore`.
- **Portability:** the core produces a plain `RenderBatch` (sprite instances and pile vertices). A Windows or Linux port only has to draw those two arrays with Direct3D, OpenGL or Vulkan. SpriteKit would tie the look to Apple platforms.
- **No assets:** every shape (flake, two leaf types, rain streak, petal, water bead, splash, stem, five flower heads) is a signed distance function in the fragment shader, anti-aliased with `fwidth`.
- **No Xcode needed:** the shader source is a Swift string compiled at launch with `MTLDevice.makeLibrary(source:)`. The Command Line Tools do not include the `metal` compiler, so precompiled `.metallib` files would require Xcode. Compilation takes a few milliseconds at startup.
- Frames are driven by `CADisplayLink` (macOS 14) with a preferred frame-rate range. MTKView's internal loop is off.

### Simulation model

- **Coordinates:** screen-local points, origin bottom-left, y up. One `SimulationWorld` per screen.
- **Particles** relax toward a terminal velocity (`drag`) plus wind and sway. This first-order model behaves like gravity with air resistance: thrown particles rise, slow down and fall again. It is stable for any frame time up to 50 ms.
- **Ledges** are 1D height fields with 3 pt cells along the screen bottom, the Dock top and visible window top edges. Landing particles add their area with a triangular kernel, so a pile is never a single stack. Each frame applies angle-of-repose relaxation (per-effect slope) and diffusion smoothing. A per-cell cap (maximum height × a smooth 0.78–1.0 wave) keeps piles from overflowing and gives full piles an uneven top. Open ends shed mass that falls off as particles.
- **Cursor:** inside a 52 pt radius, airborne particles get pushed outward plus 55% of the cursor velocity. On piles, the cursor carves a circle: 40% of the removed mass is pushed to the side, 60% is thrown up as particles.
- **Moving windows:** ledges are matched by window ID. A move shifts the pile against the motion (inertia, slides off the trailing end) and sheds a fraction that grows with speed, faster when the window is pulled down. Removed windows drop their pile. If a window disappears within 1.5 s after a Space switch, its pile is stashed and restored when the window returns.
- **Occlusion:** an edge is visible only where no window in front (or the Dock or menu bar) covers it. Hidden cells keep their mass but neither render nor collect.
- **Determinism:** all randomness comes from a seeded SplitMix64 generator. Same seed plus same inputs give identical results (tested).
- **Configuration:** every look-and-feel number per effect (size, speed, sway, spin, wind, gusts, drag, density, colours, pile heights, slope, smoothing, melt rate) lives in `Sources/SeasonsCore/EffectCatalog.swift`.

### Other choices

| Topic | Decision | Reason |
|---|---|---|
| Window level | `.statusBar` (25) | Above the Dock (20) and normal windows, so snow lies visibly on the Dock. Below the screen saver. |
| Effect switch | clears piles | A snow pile cannot sensibly turn into leaves. |
| "Pile up on windows and Dock" off | screen bottom still collects | The bottom edge is the minimum the effect needs to look right. |
| Melt | one-shot; ends when piles and air are empty | Matches "accumulation disappears slowly". |
| Summer in automatic mode | nothing, or rain if "Rain in Summer" is on | Spec: "Sommer aus/optional Regen". |
| Hemisphere | northern | Target user; the core supports the southern hemisphere already. |
| Dock length | estimated from Dock prefs: (tiles × (tile size + 4) + separators × 14 + 20) pt | No public API exposes it; the Dock's own windows cover the whole screen. |
| Side or hidden Dock | no Dock ledge; flowers on the screen bottom | No horizontal top edge to grow from. |
| Bundle ID | `com.laurenzrauscher.Seasons` | |
| Localization | `en.lproj`/`de.lproj` `Localizable.strings`, English keys | `.strings` work without Xcode's String Catalog compiler. |

## Permissions

Tested on macOS 27.0.1 (MacBook Air M2) from a process **without** Screen Recording permission (`CGPreflightScreenCaptureAccess() == false`): `CGWindowListCopyWindowInfo` returned bounds, layer, owner name and PID for windows of other apps. `kCGWindowName` was missing. Apple restricts only window titles (since macOS 10.15), so the window features need no permission.

Robustness: if the API returns nil, or 16 polls in a row return no foreign windows, the tracker reports "unavailable". Seasons then keeps the screen-bottom and Dock ledges, and the menu offers a button that calls `CGRequestScreenCaptureAccess()` and opens the Screen Recording pane. Titles and contents are never read, stored or sent.

## Performance budget and measurements

Budget: well under 10% of one core at medium intensity, about 50 MB of RAM, no growth over time.

Measured with `ps` CPU-time deltas over 20–30 s, release build, snow at medium intensity, macOS 27.0.1, MacBook Air M2:

| Setup | CPU (one core) | RSS |
|---|---|---|
| Built-in display (2880×1864), 30 fps (battery) | 5.0% | 45 MB |
| Built-in display, 60 fps (power adapter) | 8.5% | 50 MB |
| Built-in plus external display (144 Hz), 30 fps | 9.0–9.4% | 50–54 MB |
| Two displays, 60 fps | 15.9% | 50 MB |
| Two displays, amount "Off" (idle, nothing moving) | 1.0% | 46 MB |

`sample` shows that simulation and batch building take about 2% of a core. The rest is frame presentation (Core Animation, Metal driver, WindowServer IPC) and costs roughly the same per frame regardless of particle count. A test with half-resolution drawables gave no saving. The cost therefore scales with **frames × screens**, which is why:

- rendering stops completely when nothing moves (after 45 quiet frames). A 10 Hz check wakes it when the pointer comes near a pile or a window moves;
- 30 fps on battery, 20 fps in Low Power Mode, 60 fps on the power adapter;
- window polling stops while paused, suspended or with accumulation off, and drops from 30 Hz to 8 Hz when no window has moved for 0.6 s.

Memory: particle counts are capped per effect (260–2,600 per screen), and buffers are reused (capacity grows in powers of two, never per frame). Removing a display tears down its window, display link and GPU buffers. A multi-hour leak test was **not** run.

## Testing

- `swift test` runs both test targets: 34 core tests (43 cases) and 8 menu tests (15 cases).
- `Seasons --render-preview <folder>` renders each effect on a synthetic desktop with the real Metal pipeline (also with a cursor sweep). It was used to check the look without Screen Recording permission.
