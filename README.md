# Steam Remote Play - Docker mod for steam

This mod makes Steam Remote Play (streaming from the container to the Steam
Link app, a Steam Deck or another PC) work with
[linuxserver/steam](https://github.com/linuxserver/docker-steam). The image
itself is built for playing in the browser; out of the box Remote Play has no
LAN connection, crashes with hardware encoding on NVIDIA, ignores
controllers and streams Big Picture's menus as a black screen.

The mod does nothing until you set `REMOTEPLAY=true`. Without it the
container behaves exactly as without the mod.

## Usage

Set these environment variables on the steam container:

```
DOCKER_MODS=ghcr.io/joly0/docker-mods:steam-remoteplay
REMOTEPLAY=true
```

Several mods are separated with `|`.

With `REMOTEPLAY=true`, Steam starts in Big Picture inside
[gamescope](https://github.com/ValveSoftware/gamescope) (the compositor of
SteamOS), so Remote Play streams the composited screen, menus included, and
encodes it on the GPU. In the browser, Steam then shows in Big Picture as a
window of the streaming size.

### Container settings

A mod cannot change these; set them in the container template / compose file.

For Remote Play:

| Setting | Why |
|---|---|
| Own LAN IP (macvlan, e.g. Unraid `br0`/`eth0`) or `network_mode: host` | Remote Play finds the host by LAN broadcast and connects directly. Behind Docker's NAT bridge it falls back to Valve's relay, which times out. |
| NVIDIA GPU passed through as for the image (`--gpus all` / `--runtime nvidia`) | Hardware encoding (NVENC). |

For controllers (all four together):

| Setting | Why |
|---|---|
| Device `/dev/uinput` | Steam turns the client's controller into a virtual gamepad. |
| Volume `/dev/input:/dev/input` (a bind mount, **not** a device) | The virtual gamepad appears in the host's `/dev/input` after the container started; a device entry is only a snapshot. |
| `--device-cgroup-rule="c 13:* rmw"` | Lets the container open input devices created later. |
| `NO_GAMEPAD=true` | Turns off the browser gamepads. Their interposer hides real controllers from Steam and games, and without it the image would create its virtual browser gamepads inside the mounted, i.e. the host's, `/dev/input`. |

In Steam, keep **Settings > Remote Play > Advanced Host Options > Enable
hardware encoding** on.

### Optional variables

| Variable | Default | Meaning |
|---|---|---|
| `GAMESCOPE_RESOLUTION` | `auto` | Size Steam renders and streams at. `auto`: the screen of the last connected client, applied from the next Steam start on (1920x1080 until a client has connected). `WxH` for a fixed size, e.g. `2520x1080` for a 21:9 phone. |
| `REMOTEPLAY_NVIDIA_LIB32` | (unset) | Container path of the host's 32-bit NVIDIA libraries, if you mount them (Unraid: host `/usr/lib` read-only to e.g. `/host-lib32`). Without it the mod downloads the matching NVIDIA driver once (about 420 MB, first start only) and keeps its 32-bit libraries in `/config/.cache/steam-remoteplay`. |

## What it does at container start (with `REMOTEPLAY=true`)

- installs gamescope, PipeWire, WirePlumber, mangoapp and Steam's 32-bit
  PipeWire client libraries
- shows an FPS counter (FPS only, in the chosen corner) when Steam's
  **Settings > In Game > In-game FPS counter** is on; Steam's own counter
  does not draw inside gamescope
- replaces Debian's gamescope with a build of the same version that also
  streams the overlay layers the screen shows (FPS counter, Steam's
  performance information, notifications; upstream gamescope streams only
  the game or Big Picture), and for versions before 3.16.31 carries the
  upstream fixes against black frames and swapped colours from
  [gamescope #2271](https://github.com/ValveSoftware/gamescope/pull/2271)
- links the 32-bit NVIDIA libraries Steam's 32-bit encoder needs (the NVIDIA
  container runtime only provides 64-bit ones; without them Steam picks VAAPI
  and crashes with hardware encoding on)
- makes `/dev/uinput` usable and adds the Steam user to the host's input
  group, when those devices are passed in
- with `NO_GAMEPAD`: stops the Steam launcher from preloading the
  browser-gamepad interposer and sets `SDL_JOYSTICK_DISABLE_UDEV=1`
- stops the desktop from maximizing every window (the stream takes
  gamescope's window size) and starts Steam in Big Picture inside gamescope
- keeps gamescope's window at the streaming size, also while no browser is
  connected (the web UI desktop is then only 1024x768), through a labwc key
  binding that resizes only gamescope's window

## Limitations

- Tested on NVIDIA (RTX 4060 Ti, driver 595) with the Steam Link app on
  Android. AMD and Intel are untested.
- With the 32-bit NVIDIA libraries in place, 32-bit OpenGL games run on the
  NVIDIA GPU instead of Mesa.
- Browser gamepads are off while `NO_GAMEPAD` is set.
- The resolution is fixed while Steam runs: gamescope cannot change Steam's
  render size live, so `auto` follows a new client only after Steam
  restarts. SteamOS behaves the same way.
