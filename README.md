# Snail Mail (蜗牛竞速) — iOS Portrait Remake

An independent SwiftUI + SpriteKit remake of **蜗牛竞速 / Snail Mail**, the 2005
Reflexive arcade racer where a turbo-charged snail blasts along an intergalactic
highway delivering mail past salt crystals, blue meteorites and slugs.

Everything on screen is drawn from code. The road, the snail, the pickups, the
space backdrop and the whole UI are procedural sprites and SwiftUI shapes, so
the project ships **no art extracted from the retail game**. The remake is
built for a portrait phone: the pseudo-3D road, the vertical postal meter and
the mode menu are all laid out for one hand.

The one thing that *does* come from the retail data file is the campaign's
balance data. `SnailMail.dat` stores its scripts behind a byte-wise XOR with a
256-byte repeating key, and once peeled back it is a plain 601-entry archive:
per-level speed, hazard probabilities, parcel counts, route length, backdrop and
fringe colour for the arcade levels, plus the tutorial and challenge tuning.
Those numbers (and the level/galaxy names that go with them) are what the
campaign screen and `LevelConfig` now use. No textures, audio or other assets
are extracted — only the small configuration scripts.

The same scripts carry the words the original prints around a race: each level's
`GalaxyText:` briefing (Turbo's log entry, or an "IPS WARNING" notice about the
gaps and ramps ahead) and the opening-crawl and credits text, all of which the
remake shows on its own screens.

The soundtrack is generated at runtime with `AVAudioEngine` (a looping
chiptune plus shoot / collect / hit / boost effects), so there are no bundled
audio files either — the app bundle contains no images or sounds at all.

## Screenshots

| Menu | Tutorial | Time Trial | Challenge |
| --- | --- | --- | --- |
| ![menu](docs/screenshots/menu.png) | ![tutorial](docs/screenshots/tutorial.png) | ![speed](docs/screenshots/speed.png) | ![challenge](docs/screenshots/challenge.png) |

| Galaxy map | Briefing | Results |
| --- | --- | --- |
| ![galaxy](docs/screenshots/galaxy.png) | ![briefing](docs/screenshots/briefing.png) | ![results](docs/screenshots/results.png) |

| Help | Options | High Scores |
| --- | --- | --- |
| ![help](docs/screenshots/help.png) | ![options](docs/screenshots/options.png) | ![highscores](docs/screenshots/highscores.png) |

| Intro | Credits |
| --- | --- |
| ![intro](docs/screenshots/intro.png) | ![credits](docs/screenshots/credits.png) |

## Gameplay

- Steer the snail horizontally by dragging anywhere on the screen.
- The highway scrolls toward you. Dodge **salt grains**, **blue meteorites**,
  **slugs** and **gaps in the road** to keep the postal meter alive.
- Weapons auto-fire while you hold; shooting hazards clears them for score.
- Pickups:
  - **Parcel** — counts toward the delivery quota
  - **Heart** — repairs the postal meter
  - **Power-up ring** — the only way up the weapon ladder: blaster → laser →
    rocket launcher. Rings past the top tier pay out in points (green)
  - **Blast ring** — detonates nearby hazards (gold)
  - **Slow ring** — drags the snail down (violet)

## Modes

The 2005 PC build shipped four modes, and this remake keeps exactly those:

- **教学 Tutorial** — guided, damage-free. On-screen prompts walk through
  steering, firing, collecting parcels, grabbing upgrade rings and delivering
  to the post office.
- **战役 Postal** — the original campaign (its level files are the
  `Arcade*.txt` set): ten galaxies of five stars each,
  played from a galaxy map. Every star uses its own tuning from the retail data
  file, so the early teaching levels are gentle and "40 Gph" through "100 Gph"
  ramp the speed, salt, garbage and slug density right up.
- **时速 Time Trial** — a shorter route at high speed; reach the post office
  and the clock is the score.
- **挑战 Challenge** — a long, densely seeded survival highway. The retail
  level file marks it `Random:yes`, so its 51-piece pool is drawn as a shuffled
  deck and laid out differently every run.

The later mobile port's *Practice* and *Pro Challenge* are not part of this
build, so they are left out.

### Around a race

Picking a star on the galaxy map shows that level's **briefing** first — the
`GalaxyText:` paragraph the retail build prints before a route, "CLICK TO
CONTINUE" and away. The menu also carries the original's side screens: **Help**,
**Options** (music and sound-effect levels), **High Scores** (the Postal and
Challenge tables, with the original's "Enter your name here!" prompt when a run
makes the board), the **Intro** crawl and the **Credits**. Postal runs are tuned
by the start screen's **Select Speed** and **Select Difficulty** rows, which
scale each level's own numbers.

## Track data

The campaign, tutorial and challenge courses are the retail game's own tracks
rather than invented ones. `SnailMail.dat` ships everything XOR-obfuscated with
a 256-byte key; undoing that exposes a plain archive of level scripts
(`LEVELS/*.txt`), track pieces (`SEGMENTS/*.txt`) and artwork. Each level file
lists a pool of segments and a row budget, and each segment is a stack of
eight-cell rows where a cell is road, wall, off-road or a hazard — salt,
meteors, slugs, turrets, pits, rings and parcels. `tools/import_tracks.py`
converts those scripts into `Game/TrackData.swift`, and `TrackBuilder` plays
them back: the same segment order, the same length, and every hazard in the
lane the original put it in. Bends come from the piece's `Path=` family and
the drift of the drivable band across its rows, with the slow drift removed so
a long bend never walks the road off the screen.

Only this configuration data is used — no textures, sprites or audio are read
from the archive. All artwork and sound in the game are generated by our own
code.

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

Playable portrait remake of the retail four modes — Tutorial, Postal (the
ten-galaxy / 50-star campaign), Time Trial and Challenge — with procedural art,
procedural audio and a guided tutorial. Around a race it keeps the original's
side screens: the per-level `GalaxyText:` briefing before each star, Help,
Options, saved Postal and Challenge high-score boards (with the "Enter your name
here!" prompt) and the intro crawl and credits. A perfect run pays the original's
50,000-point bonus. Next steps: richer enemy behaviour and the retail voice-over
cues.

---
Snail Mail is a trademark of its respective owners. This is an independent,
non-commercial fan remake with original code and original procedural art.
