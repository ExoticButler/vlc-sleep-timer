-- Mock VLC extension host for lua/extensions/sleeptimer.lua.
--
-- VLC only activates extensions from its GUI, so this stands in for VLC: it
-- fakes the vlc.* API the extension uses (libvlc variables, dialog widgets,
-- OSD, playlist) and a fixed clock, then drives the extension the way VLC
-- would and checks the shared state it writes.
--
--   cd tests && lua5.1 mock_test.lua
local NOW = 1700000000
local real_time = os.time
os.time = function(t) if t then return real_time(t) end return NOW end

local store, log, osd = {}, {}, {}
local LIBVLC = setmetatable({}, {__tostring = function() return "libvlc" end})

local function widget(kind, text)
    local w = { kind = kind, text = text or "", values = {}, value = nil }
    function w:set_text(t) self.text = t end
    function w:get_text() return self.text end
    function w:add_value(t, id) table.insert(self.values, {t, id}); if self.value == nil then self.value = id end end
    function w:get_value() return self.value end
    return w
end

local dialog = nil
vlc = {
    object = { libvlc = function() return LIBVLC end },
    var = {
        create = function(o, n, v) assert(o == LIBVLC, "wrong object"); store[n] = v end,
        get = function(o, n) assert(o == LIBVLC, "wrong object"); return store[n] end,
        set = function(o, n, v) assert(o == LIBVLC, "wrong object")
                                assert(store[n] ~= nil, "set before create: " .. n); store[n] = v end,
    },
    msg = { info = function(m) table.insert(log, m) end,
            warn = function(m) table.insert(log, "WARN " .. m) end,
            err  = function(m) table.insert(log, "ERR " .. m) end },
    osd = { message = function(m) table.insert(osd, m) end },
    playlist = { status = function() return "playing" end },
    dialog = function(title)
        local d = { title = title, widgets = {}, updates = 0, shown = 0 }
        function d:add_label(t) local w = widget("label", t); table.insert(self.widgets, w); return w end
        function d:add_dropdown() local w = widget("dropdown"); table.insert(self.widgets, w); return w end
        function d:add_text_input(t) local w = widget("input", t); table.insert(self.widgets, w); return w end
        function d:add_button(t, f) local w = widget("button", t); w.click = f; table.insert(self.widgets, w); return w end
        function d:update() self.updates = self.updates + 1 end
        function d:show() self.shown = self.shown + 1 end
        function d:hide() self.hidden = true end
        function d:delete() self.deleted = true end
        dialog = d
        return d
    end,
}

-- Loads the extension from this checkout (override with SLEEPTIMER_LUA).
local script = os.getenv("SLEEPTIMER_LUA")
              or (os.getenv("PWD") or ".") .. "/../lua/extensions/sleeptimer.lua"
dofile(script)

local failures = 0
local function check(name, cond, extra)
    if cond then print("  ok   " .. name)
    else failures = failures + 1; print("  FAIL " .. name .. (extra and ("  -> " .. tostring(extra)) or "")) end
end
local function button(label)
    for _, w in ipairs(dialog.widgets) do if w.kind == "button" and w.text == label then return w end end
    error("no button named " .. label)
end
local function status() return dialog.widgets[1].text end
local function hint() return dialog.widgets[#dialog.widgets].text end

print("descriptor / menu shape")
local d = descriptor()
check("title", d.title == "Sleep Timer")
check("has menu capability", d.capabilities[1] == "menu")
activate()
check("dialog created and shown", dialog ~= nil and dialog.shown == 1)
check("vars created", store["sleeptimer-deadline"] == "" and store["sleeptimer-beat"] == "")

print("ticker missing -> refuses to arm, shows hint")
button("Start").click()                      -- preset dropdown default (5 min)
check("no deadline armed", store["sleeptimer-deadline"] == "", store["sleeptimer-deadline"])
check("hint shown", hint():find("background timer is not running") ~= nil, hint())
check("status unchanged", status() == "No sleep timer set", status())

print("ticker alive -> arming works")
store["sleeptimer-beat"] = tostring(NOW)
button("Start").click()                      -- 5 min preset
check("deadline = now + 5 min", store["sleeptimer-deadline"] == tostring(NOW + 300), store["sleeptimer-deadline"])
check("hint cleared", hint() == "", hint())
check("status shows clock time", status():find("^Pausing at ") ~= nil, status())
check("status shows remaining", status():find("in 5 min") ~= nil, status())

print("custom minutes")
dialog.widgets[6].text = "45"                -- the text input
button("Start", 2)
for _, w in ipairs(dialog.widgets) do if w.kind == "button" and w.text == "Start" and w.click then end end
local starts = {}
for _, w in ipairs(dialog.widgets) do if w.kind == "button" and w.text == "Start" then table.insert(starts, w) end end
check("two Start buttons", #starts == 2, #starts)
starts[2].click()
check("custom 45 min armed", store["sleeptimer-deadline"] == tostring(NOW + 45 * 60), store["sleeptimer-deadline"])
dialog.widgets[6].text = "abc"
starts[2].click()
check("garbage input ignored", store["sleeptimer-deadline"] == tostring(NOW + 45 * 60), store["sleeptimer-deadline"])
check("garbage input warned", osd[#osd]:find("not a number") ~= nil, osd[#osd])

print("snooze / cancel")
button("+15 min").click()
check("snooze adds 15 min", store["sleeptimer-deadline"] == tostring(NOW + 60 * 60), store["sleeptimer-deadline"])
button("Cancel timer").click()
check("cancel clears timer", store["sleeptimer-deadline"] == "", store["sleeptimer-deadline"])
check("status back to idle", status() == "No sleep timer set", status())

print("menu + trigger_menu")
local m = menu()
check("menu is a 1..n array", #m == 10, #m)
check("menu[1] is the status line", m[1] == "No sleep timer set", m[1])
check("menu[2] is 15 min", m[2] == "Pause in 15 min", m[2])
check("menu[7] is 2 hours", m[7] == "Pause in 2 hours", m[7])
check("menu[8] is snooze", m[8] == "+15 min", m[8])
check("menu[9] is cancel", m[9] == "Cancel timer", m[9])
trigger_menu(2)
check("menu id 2 arms 15 min", store["sleeptimer-deadline"] == tostring(NOW + 15 * 60), store["sleeptimer-deadline"])
trigger_menu(7)
check("menu id 7 arms 2 hours", store["sleeptimer-deadline"] == tostring(NOW + 120 * 60), store["sleeptimer-deadline"])
trigger_menu(9)
check("menu id 9 cancels", store["sleeptimer-deadline"] == "", store["sleeptimer-deadline"])
trigger_menu(6)
check("menu id 6 arms 90 min", store["sleeptimer-deadline"] == tostring(NOW + 90 * 60), store["sleeptimer-deadline"])
local before = dialog.shown
trigger_menu(10)
check("menu id 10 reopens window", dialog.shown == before + 1, dialog.shown)

print("fired state, stale beat, close/deactivate")
store["sleeptimer-deadline"] = ""
store["sleeptimer-fired"] = tostring(NOW - 120)
playing_changed()                                -- VLC refreshes the window on pause
check("reports the firing time", status():find("paused playback at") ~= nil, status())
store["sleeptimer-beat"] = tostring(NOW - 60)   -- ticker died
trigger_menu(3)
check("stale beat refuses to arm", store["sleeptimer-deadline"] == "", store["sleeptimer-deadline"])
store["sleeptimer-beat"] = tostring(NOW)
trigger_menu(3)
check("armed again once ticker returns", store["sleeptimer-deadline"] == tostring(NOW + 1800), store["sleeptimer-deadline"])
close()
check("close only hides", dialog.hidden == true and dialog.deleted == nil)
deactivate()
check("deactivate clears the timer", store["sleeptimer-deadline"] == "", store["sleeptimer-deadline"])
check("deactivate deletes the dialog", dialog.deleted == true)

print(failures == 0 and "\nALL CHECKS PASSED" or ("\n" .. failures .. " CHECK(S) FAILED"))
os.exit(failures == 0 and 0 or 1)
