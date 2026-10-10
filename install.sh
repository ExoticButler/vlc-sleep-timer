#!/usr/bin/env bash
# Install the Sleep Timer scripts into VLC's per-user Lua directories.
#   ./install.sh          copy the scripts
#   ./install.sh --link   symlink them instead (for development)
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/vlc/lua"
vlcrc="${XDG_CONFIG_HOME:-$HOME/.config}/vlc/vlcrc"

install_cmd=(cp -f)
[[ "${1:-}" == "--link" ]] && install_cmd=(ln -sfn)

for part in extensions intf; do
    mkdir -p "$dest/$part"
    "${install_cmd[@]}" "$src/lua/$part/sleeptimer.lua" "$dest/$part/sleeptimer.lua"
    echo "installed $dest/$part/sleeptimer.lua"
done

if grep -qx 'extraintf=luaintf' "$vlcrc" 2>/dev/null \
   && grep -qx 'lua-intf=sleeptimer' "$vlcrc" 2>/dev/null; then
    echo "vlcrc already enables the background timer; restart VLC to pick up changes."
else
    cat <<'MSG'

One more step: the countdown runs in a Lua interface, which must be enabled.
Add these lines to ~/.config/vlc/vlcrc (replacing the commented-out versions):

    extraintf=luaintf
    lua-intf=sleeptimer

or start VLC with: vlc --extraintf=luaintf --lua-intf=sleeptimer
MSG
fi
