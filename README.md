# Orbitals

A native iPhone and iPad instrument for **Space Age Orbital Dynamics: Decomposing the Frequencies**. SwiftUI owns the interface, Metal draws the phosphor plots, and Core Haptics gives controls tactile detents and feedback. No web view, network service, or third-party runtime is required.

## Open and run

Open `Orbitals.xcodeproj` in **Xcode 27**, choose the **Orbitals** scheme and an iOS 27 simulator, then Run. The minimum deployment target is iOS/iPadOS 27.0. Development signing is configured for the connected iPhone's existing team. Version 1.0 (7), including luminous CMY gradient connections and tracks, anchored AR for all five views and the white time-cylinder present ring, was signed, installed and launched on the iPhone 15 Pro Max running iOS 27.2. Surface tracking and camera alignment still need hands-on device validation. On another developer's machine, select the appropriate team under Signing & Capabilities. Distribution signing and App Store submission are not configured.

The generated project is included alongside `project.yml`. Regenerate after adding sources with `xcodegen generate` (XcodeGen is only a development tool, not an app dependency). The app contains a generated phosphor oscilloscope icon; its source image and generation prompt are in `Documentation/Icon`. `make-icon.swift` preserves the earlier programmatic icon design.

## Features retained

| Instrument | Native behavior |
| --- | --- |
| Spatial scope | Continuous circle-to-sphere morph, projected 4D hypersphere, 4D plane rotations, mesh, axes, connections, trails and glow |
| Time cylinder | Actual recorded past, luminous white present ring, conditional future, six coordinate planes, time inspection and free camera rotation |
| Time torus | Projected 4D cross-sections wrapped into a complete torus, with a bounded visual closure joining the rear window edges |
| Orbital tracks | Fixed closed tracks, racing nodes, live shape edits, plus periodic simulated-loop programs |
| Retcon torus | Current equations rewrite both past and future in a separate branch; original history remains as blue ghosts with same-instant displacement comparisons |

- Three independent or linked cyan, magenta and yellow channels (A, B and C).
- Bright connecting lines blend continuously between their two CMY endpoints. Closed orbital tracks and spatial motion guides cycle through CMY with seamless color joins; particles and recorded traces retain their individual channel colors. The same shader treatment applies in AR.
- Orbit, pendulum, precession, Lissajous and breathing motions.
- Speed, amplitude, frequency, phase, radius, 4D rotations, camera, mesh, axes, connections, trails, persistence and glow controls.
- Play/pause, exact 1/60-second step, clear trails, clear archive, reset and four experiment presets.
- Three simulated-loop presets and custom duration, laps, pace, excitation, radius, rotation and modulation depth.
- Coordinate and Euclidean distance readouts, historical inspection, retcon ghost strength and rewrite phase.
- Native glass buttons and dials, sliders, toggles, menus and control sheets. VoiceOver adjustable controls, keyboard camera rotation, Dynamic Type and Reduce Motion support.
- Full-screen popouts for every visualization, with focal-anchored pinch zoom, two-finger pan, one-finger rotation, optional one-finger Move mode and double-tap reset. Camera framing carries between the dashboard and full screen and remains independent for each view.
- Optional adjustable-strength haptics for actions and quantized detents. Physical tactile quality must be checked on a supported iPhone; Simulator does not reproduce it.

Choose **5D** to reveal all five visualization tabs. Tap the outward arrows beside a plot title to expand it. Drag inside a plot to rotate, use two fingers to move, pinch to zoom, or double tap to reset. In full screen, the hand button enables one-finger Move mode; the view menu switches instruments without leaving the canvas. Zoom buttons and VoiceOver actions provide alternatives to multi-touch. Zoom spans 25–600%. Scroll the dashboard from the surrounding panel gutter. The persistent **top-left Dials button** opens Motion Control from any scroll position and from every full-screen view. Flight controls remain accessible from the top-right sliders button. On a wide iPad window, geometry and display controls sit beside the instrument.

Motion Control keeps **Reset dials** and **Reset alignment** pinned at the bottom. Reset dials restores the selected channel's original motion, rate, amplitude, frequency and phase; with Link enabled it restores all three to that selected channel's defaults. Reset alignment restores all five cameras' standard framing, rotation and zoom. The plot's **Align** button resets just that view. These actions preserve the clock and recorded history. **Zero all phase offsets**, in the harmonic menu, sets all φ values to zero without changing the other dials; unlike motion types need not occupy the same position.

## Anchored AR

In any full-screen visualization, tap **AR**, allow camera access, and scan a textured table, floor or wall. ARKit's coaching overlay guides surface detection. Aim the center reticle at a detected surface and tap **Place here**, or tap that surface directly. The shape stays anchored as you walk around it. Pinch to resize, twist with two fingers to rotate, or use the size buttons. **Move anchor** keeps the existing placement visible while you choose another surface; the actions menu can reset size and rotation or scan a new space.

All five views use the same live Metal phosphor renderer and motion settings in AR. The view picker and Dials shortcut remain available; pause freezes the simulation while camera tracking continues. The AR presentation has its own size and orientation, so leaving it restores the instrument's existing camera framing. Four-dimensional shapes remain projections into 3D, and the fifth dimension remains simulation time.

World tracking requires a supported physical iPhone or iPad; Simulator displays an explanatory fallback. Camera denial has a Settings recovery action. Tracking interruptions preserve the session's anchor for relocalization; anchors are session-only and are discarded when AR closes. No camera images, room maps or anchors are saved or uploaded. The transparent emissive line overlay does not use depth occlusion, so it can remain visible through people or furniture.

The camera background uses RealityKit, surface detection and poses use ARKit, and the existing Metal geometry is transformed by the anchor and calibrated camera matrices. [Apple's placement and interaction guidance](https://developer.apple.com/documentation/arkit/placing-objects-and-handling-3d-interaction) and [AR coaching overlay](https://developer.apple.com/documentation/ARKit/ARCoachingOverlayView) inform the workflow.

## Harmonic starting points

Six editable starters appear at the top of Motion Control: Unison, Counterphase, Three-phase, Jovian resonance, Slow beats and Lissajous harmonics. Loading one starts a fresh recording at time zero, sets all three channels, and turns off Link and simulated-loop modulation. It preserves dimensions, camera framing and play/pause state.

The circular starters set speed to 1× and amplitude to zero, so their phase relations lie on a common equatorial circle even in higher dimensions. This amplitude controls latitude and fourth-dimensional excursion in Orbit mode, not the circle radius. Unison deliberately overlaps the three nodes. The Jovian starter uses 0.4/0.2/0.1 Hz and phases 180°/0°/0°, illustrating the 4:2:1 rate relationship. Slow beats uses 0.12/0.13/0.14 Hz, so neighboring phases realign every 100 seconds. Lissajous uses amplitude 0.85 with 2:3 coordinate harmonics. These are scaled kinematic illustrations; they do not model gravity, real orbital radii or oscillator coupling. Scientific references and descriptions are available in Field notes:

- [NASA: Ganymede and orbital resonance](https://science.nasa.gov/jupiter/jupiter-moons/ganymede/facts/)
- [MIT: Three-phase systems](https://ocw.mit.edu/courses/6-622-power-electronics-spring-2023/mit6_622_s23_lec212.pdf)
- [OpenStax: Superposition and interference](https://openstax.org/books/college-physics-2e/pages/16-10-superposition-and-interference)
- [MIT: Lissajous figures and the Bowditch pendulum](https://wikis.mit.edu/confluence/pages/viewpage.action?pageId=43457493)

Motion selection uses explicit buttons with selected states and explanations. When **Mesh & motion paths** is enabled, Spatial scope adds luminous dashed gradient guides sampled from the complete current trajectory. The guides remain visible while paused and at zero speed. Solid channel-colored trails remain the actual recorded movement. Guides cache the curve shape, so rate changes do not rebuild it. A zero-amplitude or zero-speed explanation makes these limiting cases explicit.

## Reading the dials

Flight controls opens expanded. Each dial has a persistent accent, Greek symbol and brief explanation; channel identity remains cyan, magenta or yellow in the channel selector and editing indicator.

| Dial | Accent | Meaning |
| --- | --- | --- |
| κ Speed | Amber | Multiplies the base frequency |
| α Amplitude | Blue | Sets size, swing or depth, depending on the motion |
| ν Frequency | Mint | Base cycles per second at 1× speed |
| φ Phase | Violet | Offsets angles within the motion |

The base oscillator angle is `q = 2πνκt`. These symbols are app notation; phase is an angular offset, not a uniform time shift for every motion. The in-app Field notes explain mode-specific amplitude effects, including its lack of visible effect for a flat 2D orbit. At accessibility text sizes, the dials use a single column.

## Mathematics and time semantics

The Swift core is ported directly from the existing dashboard. Coordinates use `Double`; the Metal renderer uses `Float` only for displayed geometry. Four spatial dimensions are shown **through projection**. “5D” means four spatial coordinates plus simulation time, not five spatial dimensions or physical time travel. The motion equations are kinematic studies rather than a gravitational spacecraft simulator.

Recording uses a 60 Hz simulation-time grid and retains 30 seconds. Changes to physical parameters start a new segment; archived samples never change. Paused edits affect the current model and forecasts while preserving past evidence. Retcon reconstructs a separate branch at the original timestamps. Its blue ghosts are the actual archive. A short rear interpolation closes the time-window display; numerical values remain actual recorded or modeled coordinates.

The simulated loop affects orbital tracks only. Its integer harmonics and integrated nonnegative pace repeat exactly at the chosen period. On radius reduction, optical spatial trails clear to keep old points from crossing the new projection eye plane; recorded timeline history remains intact.

## Efficiency

- Only the selected Metal canvas renders. Opening full screen removes the embedded renderer until dismissal. Fully offscreen plots skip geometry generation, drawable acquisition and GPU commands while simulation time/readouts continue.
- Three reusable 2 MiB GPU buffers, analytic line/circle antialiasing and glow, and cached mesh/track geometry.
- 60 fps normally; 30 fps in Low Power Mode or serious/critical thermal state. Readouts update at 10 Hz.
- Paused instrument views draw only when controls, camera or size change. AR keeps rendering camera poses while the simulation is paused. Background/inactive scenes stop simulation and rendering, with no wall-clock catch-up on return.
- Haptic patterns are cached, detents are quantized and rate-limited, and the engine shuts down when idle or backgrounded.
- Motion settings, selected view, loop configuration and feedback preferences save locally. A new app launch starts a fresh clock and recording.

## Verification

Run Product → Test, or use the `Orbitals` scheme with `xcodebuild test`. `OrbitalsTests` covers geometry, projection, immutable history, retcon semantics, exact closed loops, cameras, anchored zoom and pan, playback and lifecycle. `OrbitalsUITests` covers transport, all five rotatable popouts, pinch/pan/reset, camera preservation, control editing and Field notes.

The initial native core passed 500 direct parity cases against the dashboard's JavaScript, with maximum absolute error `7.8e-16`. Build and simulator results are recorded in `VERIFICATION.md`.

## Design references

Apple's HIG separates Liquid Glass navigation/controls from the content layer; Orbitals keeps plots dark and high contrast. Native controls inherit the installed iOS 27 Liquid Glass appearance.

- [Materials and Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)
- [Coordinating native gesture recognizers](https://developer.apple.com/documentation/uikit/coordinating-multiple-gesture-recognizers)


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
