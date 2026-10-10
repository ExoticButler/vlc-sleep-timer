--[[ Sleep Timer for VLC -- background ticker.

     This is the half of the Sleep Timer plugin that keeps time. It must run as
     a VLC Lua *interface* script, because only interface scripts get their own
     thread plus vlc.misc.mwait(); extension scripts (the menu/dialog half, in
     lua/extensions/sleeptimer.lua) are only ever called back by VLC and so
     cannot count down on their own.

     The two halves talk through three string variables on the libvlc object:

       sleeptimer-deadline  os.time() value at which to pause ("" = no timer)
       sleeptimer-beat      os.time() of the last tick, so the extension can
                            tell whether this script is actually running
       sleeptimer-fired     os.time() at which a timer last expired

     Enable with:  vlc --extraintf=luaintf --lua-intf=sleeptimer
     or permanently, in ~/.config/vlc/vlcrc:  extraintf=luaintf
                                              lua-intf=sleeptimer
]]

local V_DEADLINE = "sleeptimer-deadline"
local V_BEAT     = "sleeptimer-beat"
local V_FIRED    = "sleeptimer-fired"
local TICK_US    = 500000   -- 0.5 s: accurate enough, and cancels feel instant

local libvlc = vlc.object.libvlc()

-- Create the shared variables unless they already exist: vlc.var.create() also
-- *sets* the value, which would wipe a timer armed before this script started.
local function ensure(name)
    if vlc.var.get(libvlc, name) == nil then
        vlc.var.create(libvlc, name, "")
    end
end

local function get(name)
    local v = vlc.var.get(libvlc, name)
    if v == nil or v == "" then return nil end
    return v
end

local function set(name, value)
    vlc.var.set(libvlc, name, value or "")
end

local function osd(text)
    -- Fails harmlessly when there is no video output to draw on.
    pcall(vlc.osd.message, text, nil, "top-right", 4000000)
end

local function fire()
    set(V_DEADLINE, "")
    set(V_FIRED, tostring(os.time()))
    local status = vlc.playlist.status()
    if status == "playing" then
        -- vlc.playlist.pause() toggles, so only call it while actually playing.
        vlc.playlist.pause()
        vlc.msg.info("[sleeptimer] timer expired: playback paused")
        osd("Sleep timer: paused")
    else
        vlc.msg.info("[sleeptimer] timer expired, but status is " .. status)
    end
end

ensure(V_DEADLINE)
ensure(V_BEAT)
ensure(V_FIRED)
vlc.msg.info("[sleeptimer] background timer running")

while true do
    set(V_BEAT, tostring(os.time()))

    local deadline = tonumber(get(V_DEADLINE) or "")
    if deadline and os.time() >= deadline then
        fire()
    end

    -- mwait() raises "Interrupted." when VLC tears the interface down, which is
    -- how this loop ends; without the pcall it would be logged as a script error.
    if not pcall(vlc.misc.mwait, vlc.misc.mdate() + TICK_US) then break end
end

vlc.msg.info("[sleeptimer] background timer stopped")
