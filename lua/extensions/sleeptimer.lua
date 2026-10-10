--[[ Sleep Timer for VLC -- menu and dialog.

     Pauses playback after a delay you pick, from View > Sleep Timer (a submenu
     of presets) or from its own small window.

     Counting down is done by the companion interface script,
     lua/intf/sleeptimer.lua, which must be enabled for timers to fire:

         vlc --extraintf=luaintf --lua-intf=sleeptimer

     or permanently, in ~/.config/vlc/vlcrc:  extraintf=luaintf
                                              lua-intf=sleeptimer

     (A VLC extension only runs when VLC calls one of the functions below, and
     the Lua API it is given has no timer and no sleep, so it cannot do the
     waiting itself. The two halves share state through string variables on the
     libvlc object; see the header of the interface script.)

     Delays are wall-clock: a 30 minute timer pauses 30 minutes from now, even
     if you pause by hand in between. The window and the menu both show the
     clock time the timer will fire at.
]]

local V_DEADLINE   = "sleeptimer-deadline"
local V_BEAT       = "sleeptimer-beat"
local V_FIRED      = "sleeptimer-fired"
local BEAT_MAX_AGE = 5          -- the ticker beats twice a second
local PRESETS      = { 5, 10, 15, 20, 30, 45, 60, 90, 120 }  -- window dropdown
local MENU_PRESETS = { 15, 30, 45, 60, 90, 120 }             -- View submenu
local SNOOZE       = 15         -- minutes added by the "+15 min" button

local libvlc, dlg, w_status, w_preset, w_custom, w_hint
local refresh                   -- forward declaration

local SETUP_HINT = "Timers will not fire: the background timer is not running. "
               .. "Start VLC with --extraintf=luaintf --lua-intf=sleeptimer, "
               .. "or set extraintf=luaintf and lua-intf=sleeptimer in vlcrc."

function descriptor()
    return {
        title = "Sleep Timer",
        version = "1.0",
        shortdesc = "Pause playback after a set time",
        description = "<h1>Sleep Timer</h1>"
                   .. "Pauses playback after a delay you choose.",
        capabilities = { "menu", "playing-listener" },
    }
end

-- ---------------------------------------------------------------- shared state

local function vlcobj()
    if not libvlc then libvlc = vlc.object.libvlc() end
    return libvlc
end

-- vlc.var.create() also sets the value, so only create what is missing: the
-- interface script may already have armed state in there.
local function ensure_vars()
    local o = vlcobj()
    for _, name in ipairs({ V_DEADLINE, V_BEAT, V_FIRED }) do
        if vlc.var.get(o, name) == nil then vlc.var.create(o, name, "") end
    end
end

local function get(name)
    local v = vlc.var.get(vlcobj(), name)
    if v == nil or v == "" then return nil end
    return v
end

local function set(name, value)
    ensure_vars()
    vlc.var.set(vlcobj(), name, value or "")
end

local function deadline()
    return tonumber(get(V_DEADLINE) or "")
end

-- Is the interface script that does the counting actually loaded?
local function ticker_alive()
    local beat = tonumber(get(V_BEAT) or "")
    return beat ~= nil and math.abs(os.time() - beat) <= BEAT_MAX_AGE
end

-- ----------------------------------------------------------------- formatting

local function fmt_delay(minutes)
    if minutes < 60 then return string.format("%d min", minutes) end
    local hours, rest = math.floor(minutes / 60), minutes % 60
    if rest == 0 then
        return hours == 1 and "1 hour" or string.format("%d hours", hours)
    end
    return string.format("%dh%02d", hours, rest)
end

local function fmt_left(seconds)
    if seconds < 60 then return string.format("%d s", seconds) end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return string.format("%d min", minutes) end
    return string.format("%dh%02dm", math.floor(minutes / 60), minutes % 60)
end

local function status_text()
    local d = deadline()
    if d then
        local left = d - os.time()
        if left < 0 then left = 0 end
        return string.format("Pausing at %s (in %s)", os.date("%H:%M", d), fmt_left(left))
    end
    local fired = tonumber(get(V_FIRED) or "")
    if fired and (os.time() - fired) < 3600 then
        return string.format("Sleep timer paused playback at %s", os.date("%H:%M", fired))
    end
    return "No sleep timer set"
end

local function notify(text)
    vlc.msg.info("[sleeptimer] " .. text)
    pcall(vlc.osd.message, text, nil, "top-right", 3000000)
end

-- --------------------------------------------------------------------- actions

local function arm(minutes)
    ensure_vars()
    if not minutes or minutes <= 0 then
        notify("Sleep timer: please give a number of minutes")
        return
    end
    if not ticker_alive() then
        vlc.msg.warn("[sleeptimer] " .. SETUP_HINT)
        notify("Sleep timer: background timer is not running")
        refresh()
        return
    end
    local when = os.time() + math.floor(minutes * 60 + 0.5)
    set(V_FIRED, "")
    set(V_DEADLINE, tostring(when))
    notify(string.format("Sleep timer set: pausing at %s", os.date("%H:%M", when)))
    refresh()
end

local function cancel()
    if deadline() then
        set(V_DEADLINE, "")
        notify("Sleep timer cancelled")
    end
    refresh()
end

local function snooze()
    local d = deadline()
    if not d then return arm(SNOOZE) end
    d = d + SNOOZE * 60
    set(V_DEADLINE, tostring(d))
    notify(string.format("Sleep timer extended: pausing at %s", os.date("%H:%M", d)))
    refresh()
end

-- ---------------------------------------------------------------------- dialog

local function on_preset()
    arm(tonumber(w_preset:get_value()))
end

local function on_custom()
    local text = w_custom:get_text()
    local minutes = tonumber(text and text:match("^%s*([%d%.]+)%s*$") or "")
    if not minutes then
        notify("Sleep timer: '" .. tostring(text) .. "' is not a number of minutes")
        return
    end
    arm(minutes)
end

local function create_dialog()
    dlg = vlc.dialog("Sleep Timer")
    w_status = dlg:add_label(status_text(), 1, 1, 3, 1)

    dlg:add_label("Pause in:", 1, 2, 1, 1)
    w_preset = dlg:add_dropdown(2, 2, 1, 1)
    for _, minutes in ipairs(PRESETS) do
        w_preset:add_value(fmt_delay(minutes), minutes)
    end
    dlg:add_button("Start", on_preset, 3, 2, 1, 1)

    dlg:add_label("or minutes:", 1, 3, 1, 1)
    w_custom = dlg:add_text_input("", 2, 3, 1, 1)
    dlg:add_button("Start", on_custom, 3, 3, 1, 1)

    dlg:add_button("+" .. SNOOZE .. " min", snooze, 1, 4, 1, 1)
    dlg:add_button("Cancel timer", cancel, 2, 4, 1, 1)
    dlg:add_button("Refresh", function() refresh() end, 3, 4, 1, 1)

    w_hint = dlg:add_label("", 1, 5, 3, 1)
    refresh()
    dlg:show()
end

-- The window cannot update itself (VLC never calls an extension on a timer), so
-- it is refreshed on every action, on play/pause, and by the Refresh button.
refresh = function()
    if not dlg then return end
    w_status:set_text(status_text())
    w_hint:set_text(ticker_alive() and "" or SETUP_HINT)
    dlg:update()
end

local function show_dialog()
    if not dlg then
        create_dialog()
    else
        refresh()
        dlg:show()
    end
end

-- ------------------------------------------------------------- VLC entry points

function activate()
    ensure_vars()
    create_dialog()
end

-- Closing the window keeps the extension (and any running timer) alive; it can
-- be reopened from View > Sleep Timer.
function close()
    if dlg then dlg:hide() end
end

function deactivate()
    set(V_DEADLINE, "")
    if dlg then
        dlg:delete()
        dlg = nil
    end
end

function playing_changed()
    refresh()
end

function menu()
    local items = { status_text() }
    for _, minutes in ipairs(MENU_PRESETS) do
        table.insert(items, "Pause in " .. fmt_delay(minutes))
    end
    table.insert(items, "+" .. SNOOZE .. " min")
    table.insert(items, "Cancel timer")
    table.insert(items, "Open Sleep Timer window")
    return items
end

-- Menu ids are the indexes of the table returned by menu().
function trigger_menu(id)
    local n = #MENU_PRESETS
    if id == 1 then show_dialog()
    elseif id <= 1 + n then arm(MENU_PRESETS[id - 1])
    elseif id == 2 + n then snooze()
    elseif id == 3 + n then cancel()
    else show_dialog() end
end
