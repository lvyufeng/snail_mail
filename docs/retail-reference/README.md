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

## Driving the build: what was and was not established

An earlier note here claimed the build "cannot be driven on this host". That was
**wrong**, and the way it was wrong is worth keeping.

The evidence for it was that Wine's own `notepad` rendered but stayed empty
under every `xdotool` injection method. A later run of the same test on the same
host typed `HELLO` successfully — the difference was which window had focus, not
whether input arrives. `xev` confirms the X server does deliver injected events
(one ButtonPress and three KeyPress for a click and a keystroke).

What is actually true: the build can be driven *sometimes*, and the failures are
practical rather than fundamental —

- The game's window is moved by the window manager between runs. Clicks aimed at
  where it was land outside it. Read `xdotool getwindowgeometry` immediately
  before clicking, or move the window to `0,0` and drop the WM.
- With the window settled, **keyboard** input clearly reaches the game: repeated
  `space` advanced the opening crawl, and `Return` moved on from a screen. That
  is how the intro and briefing captures were taken.
- **Mouse** input at the main menu was not made to work in the time spent.
  Clicks produce a hover highlight but do not activate the item. Whether that is
  Wine's DirectInput path, the missing WM, or the coordinates still being off is
  not known — it was not run down.

So: gameplay could not be reached for observation, and the fall recovery in the
remake remains unverified against the original. Anyone continuing should aim at
the menu-click problem specifically, and should not re-derive the notepad test —
it proves nothing either way.

## Coverage audit

A pass over the retail data against the remake, for anything shipped but not
carried across. Everything below was checked and found whole:

- **Audio** — 6/6 music, 36/36 effects, 112/112 voice clips (the 113th file is
  `_voice`, an index, not a clip).
- **Galaxy art** — 17/17 maps.
- **Levels** — 50 of the 51 arcade files. `ARCADE000.TXT` is deliberately left
  out: it is named `Test` and its galaxy text reads "Use 7,8,9,0 to change
  unlocked levels", which is a development level, not content.
- **Level fields** — Speed, Salt and Slug are all present and carried over;
  the remake's `trash` is the parcel quota, which the retail states as
  `Parcels`/`Quota` rather than a `Trash` key.
- **Grid glyphs** — every glyph the retail grids use is handled. `P`/`p` have no
  case of their own because they only ever appear alongside a `Path=` attribute
  (`@pppPPppp@ Path=Dip`), marking the shape of the road rather than a prop.
  `NoFall` and `No Fall` both occur in the retail, in different files, and both
  are read.

Gaps that are real but were left deliberately, and why:

- **Speed feedback** — the three speed penalties (`ringSlow` x0.6, `asteroid`
  x0.5, `barrier` x0.35) mean a run spends most of its time accelerating and
  then losing it again; top speed is rarely reached. This matches the retail's
  own level tunings and its help text, so it was left alone.
- **Camera** — there is no field-of-view shift with speed and no camera rig
  beyond the fixed `cameraHeight`, because changing the field of view would
  move the road's fan-out, which is aligned against measured retail frames.
  Impacts do knock the frame about instead.

## Driving the build: why input was refused

The build reads the mouse and keyboard through **DirectInput 8**, not ordinary
window messages, and that is the whole of the difficulty. From `WINEDEBUG=+dinput`
on a running copy:

- It creates both devices (keyboard `{6f1d2b60…}`, mouse `{6f1d2b61…}`) and
  polls `GetDeviceState` continuously — 17,040 calls in a few minutes.
- The **mouse** is grabbed `DISCL_EXCLUSIVE | DISCL_FOREGROUND`; the
  **keyboard** is grabbed `DISCL_FOREGROUND`.

`DISCL_FOREGROUND` means Wine only reports device state while the window is the
one the window manager considers active. With no window manager, or with the
window never activated, nothing is delivered — which looks exactly like "input
does not work" and is easy to mistake for a Wine problem.

The proof that the input path itself is healthy: Wine's own `notepad`, which
takes plain window messages instead, accepts typed text reliably on the same
host under the same injection (`xdotool type`), showing `Ln 1, Col 7` after
`QWERTY`. The difference is DirectInput versus messages, not X versus Wine.

What is needed to get in:

1. Xvfb plus a window manager — **metacity**, not openbox, which lacks
   `_NET_ACTIVE_WINDOW`.
2. `xdotool windowactivate --sync` on the game window, so `_NET_ACTIVE_WINDOW`
   actually points at it.
3. Click using the coordinates in the *whole screen*, not the window: the
   game's own 640x480 viewport sits at an offset inside the 1024x768 display,
   and the window manager moves it between runs. Re-read
   `xdotool getwindowgeometry` before every click, or pin the window and stop
   the manager moving it.

With that, a click on New Game does land — the opening crawl was reached this
way. Reaching a *level* did not follow: the menu's own item hit boxes could not
be pinned down from the outside, because the highlight reacts to pointer motion
but the commit does not follow from the same injected click. That remains
unresolved, and it is the one thing still needed to watch the original play.
