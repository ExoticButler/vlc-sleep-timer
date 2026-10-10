# VLC Sleep Plugin

Pauses playback after a delay you choose, from a menu in VLC.

Adds **View → Sleep Timer** to VLC, which gives you a submenu of presets and a
small window:

```
Pausing at 01:12 (in 30 min)        <- live status; click to open the window
Pause in 15 min / 30 min / 45 min / 1 hour / 1h30 / 2 hours
+15 min                             <- extend a running timer
Cancel timer
Open Sleep Timer window
```

The window adds a preset dropdown (5–120 min) and a free-text "or minutes:"
field. Arming, extending and cancelling are each confirmed on screen.

Delays are wall-clock: a 30 minute timer pauses 30 minutes from now, even if you
pause by hand in between. That is why the UI always shows the clock time the
timer will fire at.

Written for VLC 3.0 (tested against 3.0.23).

## Layout

| File | Installs to | Role |
| --- | --- | --- |
| `lua/extensions/sleeptimer.lua` | `~/.local/share/vlc/lua/extensions/` | menu and window |
| `lua/intf/sleeptimer.lua` | `~/.local/share/vlc/lua/intf/` | counts down, pauses playback |
| `tests/mock_test.lua` | — | drives the extension against a mock VLC |

## Install

```sh
./install.sh            # copy both scripts into VLC's user directory
./install.sh --link     # symlink them instead, for development
```

Then enable the interface half, which is what actually keeps time. Either add to
`~/.config/vlc/vlcrc`:

```ini
extraintf=luaintf
lua-intf=sleeptimer
```

or start VLC with `vlc --extraintf=luaintf --lua-intf=sleeptimer`. Restart VLC
afterwards. If you want another Lua interface at the same time (the web UI, say),
use the chain form: `extraintf=luaintf{intf=sleeptimer}:luaintf{intf=http}`.

If the interface half is not running, the window says so instead of accepting a
timer that would never fire.

## How it works, and why it is two scripts

A VLC *extension* only runs when VLC calls into it, and the Lua API extensions
are given has no timer and no sleep — `vlc.misc` (which has `mwait`) is
registered for interfaces only, see `modules/lua/extension.c` in VLC. Looping
inside a callback is not viable either: every extension callback is under a
10 second watchdog (`WATCH_TIMER_PERIOD`) that offers to kill the extension, and
VLC's shutdown joins the extension thread, so a long wait would stall VLC's exit.

Interface scripts do get their own thread, so the countdown lives there. The two
halves share three string variables on the libvlc object:

| Variable | Written by | Meaning |
| --- | --- | --- |
| `sleeptimer-deadline` | extension | `os.time()` value to pause at (`""` = no timer) |
| `sleeptimer-beat` | interface | `os.time()` of the last tick, i.e. "I am running" |
| `sleeptimer-fired` | interface | `os.time()` a timer last expired |

The interface script ticks twice a second, so cancelling feels immediate and
accuracy is sub-second. `vlc.misc.mwait()` is interruptible, so the loop ends by
raising `Interrupted.` when VLC tears the interface down — the `pcall` around it
turns that into a clean exit rather than a logged script error.

Two VLC details worth knowing before editing these files:

- `vlc.playlist.pause()` is `playlist_TogglePause()`, so it is only called when
  `vlc.playlist.status()` is `"playing"`.
- VLC scans extensions in a Lua state with **no standard library** — no `pcall`,
  `os`, `string` or `table`. Top-level code and `descriptor()` must stick to
  literals; the full library is only there once the extension is activated.

## Tests

```sh
cd tests && lua5.1 mock_test.lua
```

34 checks over arming, presets, custom and garbage input, snooze, cancel, menu
ids, stale-interface detection, and close vs. deactivate.

The interface half is best tested in VLC itself, which needs no GUI:

```sh
vlc -vv --aout=dummy --vout=dummy --extraintf=luaintf --lua-intf=sleeptimer some.mp3
```

and watch for `[sleeptimer]` lines in the log.

## Uninstall

```sh
rm ~/.local/share/vlc/lua/extensions/sleeptimer.lua
rm ~/.local/share/vlc/lua/intf/sleeptimer.lua
```

and remove the two `vlcrc` lines above.
