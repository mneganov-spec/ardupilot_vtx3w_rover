-- VTX menu via button CH9, disarmed only
-- All changes staged in variables. Applied to VTX ONLY on SAVE / SAVE+REBOOT.
-- EXIT discards everything. Nothing touches VTX while in menu.

local CH_MENU = 9
local LONG_PRESS = 500
local LOOP_MS = 50

local POWER_STEPS = {25, 250, 500, 1000, 2000, 3000}
local BAND_NAMES  = {"A","B","E","F","R"}

local menu_open = false
local cursor = 1
local items = {"POWER", "BAND", "CHANNEL", "SAVE+REBOOT", "EXIT"}
local dirty = true

-- staged значения (только в памяти, не применяются к VTX)
local sel_pwr_idx = 1
local sel_band = 0
local sel_chan = 0

local btn_down_time = 0
local btn_was_down = false

local function read_button()
    local pwm = rc:get_pwm(CH_MENU)
    if not pwm then return "none" end
    local pressed = (pwm > 1700)
    local event = "none"
    if pressed and not btn_was_down then
        btn_down_time = millis()
        btn_was_down = true
    elseif not pressed and btn_was_down then
        local held = millis() - btn_down_time
        event = (held >= LONG_PRESS) and "long" or "short"
        btn_was_down = false
    end
    return event
end

-- при ОТКРЫТИИ меню — подтянуть текущие значения VTX в staged
local function load_current()
    local p = math.floor(param:get("VTX_POWER") or 0)
    sel_pwr_idx = 1
    for i, v in ipairs(POWER_STEPS) do
        if v >= p then sel_pwr_idx = i break end
    end
    sel_band = math.floor(param:get("VTX_BAND") or 0)
    sel_chan = math.floor(param:get("VTX_CHANNEL") or 0)
end

local function draw()
    local items_short = {"P:", "B:", "CH:", "|S&R|", "|E|"}
    local vals = {
        tostring(POWER_STEPS[sel_pwr_idx]),
        (BAND_NAMES[sel_band+1] or "?"),
        tostring(sel_chan+1),
        "", "", ""
    }
    local line = ""
    for i, name in ipairs(items_short) do
        local mark = (i == cursor) and ">" or " "
        line = line .. mark .. name
        if vals[i] ~= "" then line = line .. vals[i] end
    end
    gcs:send_text(6, line)
end

-- только меняет staged-переменные, VTX НЕ трогает
local function change_value()
    local it = items[cursor]
    if it == "POWER" then
        sel_pwr_idx = sel_pwr_idx + 1
        if sel_pwr_idx > #POWER_STEPS then sel_pwr_idx = 1 end
    elseif it == "BAND" then
        sel_band = sel_band + 1
        if sel_band > 4 then sel_band = 0 end
    elseif it == "CHANNEL" then
        sel_chan = sel_chan + 1
        if sel_chan > 7 then sel_chan = 0 end
    end
end

-- применить staged к VTX и сохранить (вызывается ТОЛЬКО на SAVE)
local function save_all()
    param:set_and_save("VTX_POWER", POWER_STEPS[sel_pwr_idx])
    param:set_and_save("VTX_BAND", sel_band)
    param:set_and_save("VTX_CHANNEL", sel_chan)
    gcs:send_text(6, "VTX: saved")
end

function update()
    if arming:is_armed() then
        if menu_open then menu_open = false end
        return update, LOOP_MS
    end

    local ev = read_button()

    if not menu_open then
        if ev == "short" then
            menu_open = true
            cursor = 1
            load_current()      -- подтянуть текущие значения
            dirty = true
        end
    else
        if ev == "short" then
            cursor = cursor + 1
            if cursor > #items then cursor = 1 end
            dirty = true
        elseif ev == "long" then
            local it = items[cursor]
            if it == "EXIT" then
                menu_open = false
                gcs:send_text(6, "VTX: exit (no changes)")
            elseif it == "SAVE" then
                save_all()
                menu_open = false
            elseif it == "SAVE+REBOOT" then
                save_all()
                gcs:send_text(6, "VTX: reboot")
                vehicle:reboot(false)
            else
                change_value()   -- меняет только staged, VTX молчит
                dirty = true
            end
        end
    end

    if menu_open and dirty then
        draw()
        dirty = false
    end

    return update, LOOP_MS
end

gcs:send_text(6, "VTX menu loaded")
return update, LOOP_MS