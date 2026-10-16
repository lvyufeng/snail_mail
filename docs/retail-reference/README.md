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