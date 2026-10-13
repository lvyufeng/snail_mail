# Snail Mail (蜗牛竞速) — iOS Remake

A SwiftUI + SpriteKit re-imagining of **Snail Mail**, the 2004 Sandlot Games /
Reflexive arcade racer where Turbo the snail delivers intergalactic mail across
the planets, dodging hazards and collecting upgrades.

The game is a from-scratch SwiftUI + SpriteKit remake. Rendering uses a
pseudo-3D outrun-style road (diamond checkerboard track, fringed walls, star
field) that evolves the look of the original 2004 release, and the UI reuses
extracted textures from the user's own copy of the game (title/menu backdrops,
the postal damage gauge, parcel icon, progress bar and sprite art).

> The bundled art files are extracted from the retail game and remain the
> property of their original rights holders. Remove them or replace them with
> your own art before distributing this project publicly.

## Gameplay

- You steer Turbo horizontally by dragging.
- The world scrolls toward you; dodging **salt grains** (white crystals) and
  **blue meteorites** keeps your hull (health) alive.
- Weapons auto-fire; shooting hazards also clears them.
- Pickups:
  - `+` **Repair** — restores health
  - `»` **Boost** — temporary speed surge
  - `▲` **Ammo** — upgrades the weapon toward the rocket tier
- Reach the destination planet before health runs out to deliver the mail.

## Modes

- **Postal** — the delivery campaign loop
- **Challenge** — survival gauntlet
- **Time Trial** — race the clock

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
    UI/     Menu, HUD, Game wrapper, result overlay
  Resources/  Track, HUD and menu textures extracted from the retail game
  Assets.xcassets
```

## Status

Playable portrait remake matching the original's four modes. Next steps:
per-planet level progression driven by the original `LEVELS/*.TXT` segment
grids, richer enemy behaviour, sound, and saved high scores.

---
Snail Mail is a trademark of its respective owners. This is an independent,
non-commercial fan remake with original code and art.
