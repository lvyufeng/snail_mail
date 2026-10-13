# Snail Mail (蜗牛竞速) — iOS Portrait Remake

An independent SwiftUI + SpriteKit remake of **蜗牛竞速 / Snail Mail**, the 2005
Reflexive arcade racer where a turbo-charged snail blasts along an intergalactic
highway delivering mail past salt crystals, blue meteorites and slugs.

Everything on screen is drawn from code. The road, the snail, the pickups, the
space backdrop and the whole UI are procedural sprites and SwiftUI shapes, so
the project ships **no art extracted from the retail game**. The remake is
built for a portrait phone: the pseudo-3D road, the vertical postal meter and
the mode menu are all laid out for one hand.

The soundtrack is generated at runtime with `AVAudioEngine` (a looping
chiptune plus shoot / collect / hit / boost effects), so there are no bundled
audio files either — the app bundle contains no images or sounds at all.

## Screenshots

| Menu | Tutorial | Practice |
| --- | --- | --- |
| ![menu](docs/screenshots/menu.png) | ![tutorial](docs/screenshots/tutorial.png) | ![practice](docs/screenshots/practice.png) |

| Speed | Challenge | Pro Challenge |
| --- | --- | --- |
| ![speed](docs/screenshots/speed.png) | ![challenge](docs/screenshots/challenge.png) | ![pro](docs/screenshots/pro.png) |

## Gameplay

- Steer the snail horizontally by dragging anywhere on the screen.
- The highway scrolls toward you. Dodge **salt grains**, **blue meteorites**,
  **slugs** and **gaps in the road** to keep the postal meter alive.
- Weapons auto-fire while you hold; shooting hazards clears them for score.
- Pickups:
  - **Parcel** — counts toward the delivery quota
  - **Heart** — repairs the postal meter
  - **Ring** — upgrades the weapon tier toward rockets (green), detonates
    nearby hazards (gold) or slows you (violet)

## Modes

The original mobile build shipped four modes, and this remake keeps them,
with an extra mobile-only Pro Challenge:

- **教学 Tutorial** — guided, damage-free. On-screen prompts walk through
  steering, firing, collecting parcels, grabbing upgrade rings and delivering
  to the post office.
- **练习 Practice** — free driving at a relaxed pace; hazards are seeded but
  do no damage, so you can learn the road.
- **时速 Speed** — a shorter route at high speed; reach the post office and
  the clock is the score.
- **挑战 Challenge** — a long, densely seeded survival highway.
- **挑战+ Pro Challenge** — the mobile Pro mode: the fastest speed and the
  heaviest hazard density.

## Art direction

One shared palette and drawing style runs through the menu, HUD, results and
the in-game sky: a flat cartoon-neon look with bold dark outlines, saturated
fills, a deep-space purple gradient, a ringed planet and drifting stars. The
menu backdrop and the in-game sky are generated from the same code
(`UI/Theme.swift` for SwiftUI, `Game/Sprites.swift` for SpriteKit), and the menu
mascot is drawn from the same coordinates as the racer itself, so the whole
game reads as a single product.

## Audio

`Game/Sound.swift` synthesises everything with `AVAudioEngine` into in-memory
PCM buffers: a looping four-bar chiptune plus `shoot`, `collect`, `upgrade`,
`hit`, `boost`, `select`, `win` and `lose` cues. It fails silently if audio is
unavailable, and the menu and HUD both expose a mute toggle.

## Requirements

- Xcode 26+ / iOS 17+ deployment target
- **Portrait** iPhone or iPad (locked to `UIInterfaceOrientationPortrait`)

## Build & Run

```bash
open SnailMail.xcodeproj
# or from the command line:
xcodebuild -project SnailMail.xcodeproj -scheme SnailMail \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

## Project Layout

```
SnailMail/
  Sources/
    App/    App entry point + root view
    Game/   GameModel, GameScene (loop/spawn/collisions), Sprites (procedural art)
    UI/     Menu, HUD, Game wrapper, result overlay, Theme (shared art kit)
  Assets.xcassets
docs/
  screenshots/
```

## Status

Playable portrait remake with the original's four modes plus Pro Challenge,
procedural art, procedural audio and a guided tutorial. Next steps: a 50-level
Postal campaign with per-planet progression, richer enemy behaviour and saved
high scores.

---
Snail Mail is a trademark of its respective owners. This is an independent,
non-commercial fan remake with original code and original procedural art.
