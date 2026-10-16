# Running the retail build

Notes from getting the **original 2004 retail build** (`SnailMail.exe`, Sandlot
Games / RealNetworks) to run, so fidelity work can be checked against the real
thing instead of against a description of it.

**Its art is deliberately not checked in here.** Those frames are the retail
build's own copyrighted artwork and this repository is public; the project
already keeps retail art out of the bundle (`-retailart` is off by default), so
the same rule applies. What is committed is the *method* — how to get the
original running, and the fact that it misreports its own startup failure — so
the frames can be reproduced locally by anyone who needs them.

## What it looks like when it runs

The build opens a 852×689 window under Wine (the game picks this itself). In
order: a title/Briefing pane reading "SNAIL MAIL — Episode 1: A New Recruit"
followed by story pages; then the main menu — New Game / High Scores / Options /
Credits / Exit — over a rendered backdrop; then the pseudo-3D road, which
visibly widens from roughly 40% of the frame width near the horizon to about
75% at the bottom edge.

## How it was run

The build is a **32-bit x86 Windows PE from November 2004** using DirectDraw,
Direct3D 8 and DirectInput. Two things stop it on a modern machine, and the
first one reports itself misleadingly.

1. A current Wine is needed — Ubuntu 20.04's stock Wine 5.0 (2020) is too old
   for this title; WineHQ 10.6 runs it.
2. `BASS_Init` must succeed. With no sound device the build fails its audio
   setup and shows this dialog:

   > Snail Mail failed to start.
   > Please make sure you have at least a 32 Meg 3D Hardware Accelerated Card
   > and the latest DirectX drivers.

   **That message is wrong.** It is a single generic failure string the
   executable reuses at roughly ten unrelated startup checks. The check that
   actually fails when there is no audio device reaches
   `0x44b190` → `LoadLibrary("Bass.dll")` → `BASS_Init`, from the caller at
   `0x407ab4`, returning through `0x407ab9`. Giving Wine a null PulseAudio sink
   is enough; **no binary patching is needed.**

A minimal recipe, on x86_64 Ubuntu with an X server:

```sh
# audio: BASS_Init needs a device
pulseaudio --start --exit-idle-time=-1 --load="module-null-sink sink_name=dummy"

# display: a window manager is required or the game never maps its window
Xvfb :97 -screen 0 1024x768x24 &
DISPLAY=:97 metacity --replace &
DISPLAY=:97 WINEARCH=win32 wine SnailMail.exe
```

`openbox` also works for starting the game, but its window does not answer
`_NET_ACTIVE_WINDOW`, so `xdotool windowactivate` fails and the menu will not
take input. `metacity` does answer it.

## Caveats

- The build needs its own data (`SnailMail.dat`) and the extracted content
  directories beside the executable; a bare `.exe` will not run.

## What running it confirmed

With the build actually running, the remake's fidelity claims could be checked
against the real thing rather than against the retail *data* files alone. The
textual checks are exact and need no interpretation:

| Check | Result |
|---|---|
| Opening crawl vs `INTRO/Intro.txt` | **7/7** screens word-for-word |
| Credits vs `INTRO/Credits.txt` | **12/12** screens word-for-word |
| Level names, by `source` | **50/50** |
| Level `Speed` / `Length` / `Salt` / `Trash` | **0** mismatches in 50 |
| Road palettes vs `TRACK0-3.tga` | all four track tones match |
| Road base colour | retail `#C0913E` vs remake `#C07C30`, 95% of the way |

The geometric check is the one worth writing down, because it is the number the
project argued about. Read off the running build's frame: the road reaches
**80.0%** of the viewport width at the bottom edge, and extrapolating its width
to zero puts its vanishing point at **46%** of the frame height. That is
**1.49% of width per 1% of height** — "a ratio a little above 1.5", which is
what `GameScene`'s camera comment claims. The remake measures **1.44** on the
same reading (80.8% at the bottom, vanishing point at 44%), a ratio of 0.97×.
So the camera height of 1000, chosen from this ratio, is right.

One divergence found here, since fixed: the retail Help screen is a bitmap
(`BACKGROUNDS/HELP_A.TGA`) that lists ten pickups with one-line explanations —

    Packages: Collect for points.      White Rings:  Powerup Turbo.
    Asteroids: Hurt and slow Turbo.    Red Rings:    Slow Turbo down.
    Salt: Hurt Turbo.                  Yellow Rings: Blow up enemies.
    Slugs: Kill Turbo.                 Jet Pack:     Fly across gaps.
    Hearts: Restore your postal meter. Jump Pod:     Bounce off these.

The remake replaces this with touch instructions, which is right — the retail
text ends "Steer with Mouse. Press Left Button to Fire. Press ESC to Pause
Game" — but it covered only nine of the ten. **Jump Pod** was missing even
though `EntityKind.trampoline` is implemented and bounces harder than a ramp
(`launch(power: 1.5)` against `1.0`); the Help screen raised ramps and jetpacks
under "GAPS" and never mentioned it, so nothing told a player what the `(((`
pads do. A "JUMP POD" entry was added under the retail screen's own label.
## Known limitation: the build cannot be driven on this host

The build runs, renders and animates, but **it cannot be given input** on the
machine this was worked out on, so screenshots are limited to what it shows on
its own — the intro, the briefing pages and the menu. Reaching gameplay, and
therefore anything that needs a pit or a collision to be observed, is not
possible there.

The cause is not the game. Wine's own `notepad` renders correctly under the
same X server and takes focus, but typing into it by every injection method
tried — `xdotool type`, `xdotool key`, and `xdotool type --window` — leaves the
document empty, and its status bar stays on "Ln 1, Col 1". Wine receives mouse
*motion* (the menu highlights as the pointer passes over an item) but not the
button or key events, which points at Wine's XInput path rather than at
anything the game does. It needs a host whose X server delivers injected input
to Wine, or a different injection route.
