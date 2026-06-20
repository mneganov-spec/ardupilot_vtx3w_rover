--[[ GPS Status CRSF Menu ]]--
--
-- Shows live GPS fix/sats/HDOP in the CRSF Configuration menu alongside VTX Control.
-- No firmware rebuild needed — copy to /APM/scripts/gps_crsf.lua on the FC SD card.
--
-- Dynamic update mechanism: crsf_helper stores a Lua reference to each item_def table.
-- Updating item.info in our loop is picked up on the next PARAMETER_READ from ELRS.

gcs:send_text(6, "GPS CRSF: loading...")

local crsf_helper = require('crsf_helper')

local FIX_NAMES = {
    [0] = "NoGPS",
    [1] = "NoFix",
    [2] = "2D",
    [3] = "3D",
    [4] = "DGPS",
    [5] = "RTK-Flt",
    [6] = "RTK-Fix",
}

-- Item tables as upvalues: crsf_helper holds references to these, so
-- changes to .info here are reflected in the next PARAMETER_READ response.
local item_fix  = { type = 'INFO', name = 'Fix',  info = '...' }
local item_sats = { type = 'INFO', name = 'Sats', info = '...' }
local item_hdop = { type = 'INFO', name = 'HDOP', info = '...' }

local function update_gps()
    local st   = gps:status(0)   or 0
    local sats = gps:num_sats(0) or 0
    local hdop = gps:get_hdop(0) or 9999

    item_fix.info  = FIX_NAMES[st] or ("Fix:" .. tostring(st))
    item_sats.info = tostring(sats)
    item_hdop.info = string.format("%.2f", hdop / 100)
end

local menu_definition = {
    name  = 'GPS Status',
    items = { item_fix, item_sats, item_hdop },
}

local crsf_fn
local function loop()
    if crsf_fn == nil then
        -- register_menu failed; retry once, then give up
        gcs:send_text(3, "GPS CRSF: menu reg failed, retrying")
        crsf_fn = crsf_helper.register_menu(menu_definition)
        if crsf_fn == nil then
            gcs:send_text(3, "GPS CRSF: giving up")
            return -- stop rescheduling
        end
    end
    update_gps()
    local nf, nd = crsf_fn()
    crsf_fn = nf or crsf_fn
    return loop, nd or 200
end

local crsf_delay
crsf_fn, crsf_delay = crsf_helper.register_menu(menu_definition)

if crsf_fn == nil then
    gcs:send_text(3, "GPS CRSF: register_menu returned nil, will retry in loop")
    return loop, 5000  -- retry after 5s
end

gcs:send_text(6, "GPS CRSF: menu registered OK")
return loop, crsf_delay
