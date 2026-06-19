--[[ VTX CRSF Menu ]]--

local crsf_helper = require('crsf_helper')
local MAV_SEVERITY = crsf_helper.MAV_SEVERITY
local CRSF_COMMAND_STATUS = crsf_helper.CRSF_COMMAND_STATUS

local POWER_STEPS = {25, 250, 500, 1000, 2000, 3000}
local BAND_NAMES  = {"A", "B", "E", "F", "R"}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local function pwr_to_idx(mw)
    local best, bi = 1e9, 1
    for i, v in ipairs(POWER_STEPS) do
        local d = math.abs(v - mw)
        if d < best then best, bi = d, i end
    end
    return bi
end

local cur_pwr_mw   = tonumber(param:get('VTX_POWER'))    or 25
local cur_band_idx = (tonumber(param:get('VTX_BAND'))    or 0) + 1
local cur_chan     = (tonumber(param:get('VTX_CHANNEL')) or 0) + 1

local sel_pwr_idx  = pwr_to_idx(cur_pwr_mw)
local sel_band_idx = clamp(cur_band_idx, 1, #BAND_NAMES)
local sel_chan      = clamp(cur_chan, 1, 8)

gcs:send_text(MAV_SEVERITY.INFO, string.format(
    "VTX init: %dmW B:%s CH:%d", POWER_STEPS[sel_pwr_idx], BAND_NAMES[sel_band_idx], sel_chan))

local function cb_power(new_value)
    for i, v in ipairs(POWER_STEPS) do
        if tostring(v) == new_value then
            sel_pwr_idx = i
            gcs:send_text(MAV_SEVERITY.INFO, "VTX pwr sel: " .. new_value .. "mW")
            break
        end
    end
end

local function cb_band(new_value)
    for i, v in ipairs(BAND_NAMES) do
        if v == new_value then
            sel_band_idx = i
            gcs:send_text(MAV_SEVERITY.INFO, "VTX band sel: " .. new_value)
            break
        end
    end
end

local function cb_channel(new_value)
    local n = tonumber(new_value)
    if n then
        sel_chan = clamp(n, 1, 8)
        gcs:send_text(MAV_SEVERITY.INFO, "VTX ch sel: " .. tostring(sel_chan))
    end
end

-- nonzero = reboot is pending at this millis() timestamp
local reboot_at = 0

-- Cold-boot safety net: 10 s after startup re-write VTX_FREQ=0 so ArduPilot
-- recalculates and re-sends SET_FREQUENCY even if the first attempt was ignored.
local startup_apply_done = false

local function cb_save(command_action)
    if command_action == CRSF_COMMAND_STATUS.START then
        if arming:is_armed() then
            gcs:send_text(MAV_SEVERITY.WARNING, "VTX: disarm to save")
            return CRSF_COMMAND_STATUS.READY, "Disarm!"
        end
        local pwr  = POWER_STEPS[sel_pwr_idx]
        local band = sel_band_idx - 1  -- ArduPilot VTX_BAND is 0-based
        local chan  = sel_chan - 1      -- ArduPilot VTX_CHANNEL is 0-based
        gcs:send_text(MAV_SEVERITY.INFO, string.format(
            "VTX save: %dmW B:%s(%d) CH:%d(%d)",
            pwr, BAND_NAMES[sel_band_idx], band, sel_chan, chan))
        param:set_and_save('VTX_POWER',   pwr)
        param:set_and_save('VTX_BAND',    band)
        param:set_and_save('VTX_CHANNEL', chan)
        -- Reset VTX_FREQ so set_defaults() recalculates it from BAND/CHANNEL
        -- instead of using the stale AKK startup frequency (5473 MHz) to override them.
        param:set_and_save('VTX_FREQ',    0)
        -- Schedule reboot 700ms later so flash writes complete and
        -- ELRS receives the COMMAND response before reset.
        reboot_at = millis() + 700
        return CRSF_COMMAND_STATUS.PROGRESS, "Saving..."
    end
    return CRSF_COMMAND_STATUS.READY, "Execute"
end

local power_opts = {}
for _, v in ipairs(POWER_STEPS) do power_opts[#power_opts + 1] = tostring(v) end

local menu_definition = {
    name = 'VTX Control',
    items = {
        { type = 'SELECTION', name = 'Power',   options = power_opts,
          default = sel_pwr_idx, unit = "mW", callback = cb_power },
        { type = 'SELECTION', name = 'Band',    options = BAND_NAMES,
          default = sel_band_idx, callback = cb_band },
        { type = 'SELECTION', name = 'Channel', options = {"1","2","3","4","5","6","7","8"},
          default = sel_chan, callback = cb_channel },
        { type = 'COMMAND',   name = 'Save & Reboot', callback = cb_save },
    }
}

-- Wrap crsf_helper's event loop to insert our deferred-reboot check.
local crsf_fn  -- forward declaration (captured as upvalue by loop())

local function loop()
    if reboot_at > 0 and millis() >= reboot_at then
        reboot_at = 0
        gcs:send_text(MAV_SEVERITY.INFO, "VTX: rebooting...")
        vehicle:reboot(false)
        return loop, 200  -- won't reach here after reset
    end
    if not startup_apply_done and millis() > 10000 then
        startup_apply_done = true
        param:set_and_save('VTX_FREQ', 0)  -- force re-derive from BAND/CHANNEL → re-sends SET_FREQUENCY
    end
    local nf, nd = crsf_fn()
    crsf_fn = nf or crsf_fn
    return loop, nd or 20
end

local crsf_delay
crsf_fn, crsf_delay = crsf_helper.register_menu(menu_definition)

return loop, crsf_delay
