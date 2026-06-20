--[[ Status CRSF Menu ]]--
--
-- Shows Mode / Armed / Battery / Sats / Distance-to-home / Waypoint progress
-- as INFO items in CRSF Configuration.
-- Copy to /APM/scripts/status_crsf.lua on the FC SD card. No firmware rebuild.

local crsf_helper = require('crsf_helper')

local ROVER_MODES = {
    [0]  = "Manual",
    [1]  = "Acro",
    [3]  = "Steering",
    [4]  = "Hold",
    [5]  = "Loiter",
    [6]  = "Follow",
    [7]  = "Simple",
    [10] = "Auto",
    [11] = "RTL",
    [12] = "SmrtRTL",
    [15] = "Guided",
    [16] = "Init",
}

local item_mode  = { type = 'INFO', name = 'Mode',    info = '...' }
local item_armed = { type = 'INFO', name = 'Armed',   info = '...' }
local item_batt  = { type = 'INFO', name = 'Batt',    info = '...' }
local item_sats  = { type = 'INFO', name = 'Sats',    info = '...' }
local item_dist  = { type = 'INFO', name = 'DistHome', info = '...' }
local item_wp    = { type = 'INFO', name = 'WP',      info = '...' }

local function update_status()
    -- Mode
    local m = vehicle:get_mode()
    item_mode.info = ROVER_MODES[m] or ("M" .. tostring(m))

    -- Armed
    item_armed.info = arming:is_armed() and "YES" or "no"

    -- Battery voltage (instance 0)
    local v = battery:voltage(0)
    item_batt.info = (v and v > 0) and string.format("%.1fV", v) or "?"

    -- Satellites
    item_sats.info = tostring(gps:num_sats(0) or 0)

    -- Distance to home
    if ahrs:home_is_set() then
        local pos = ahrs:get_position()  -- returns nil if no fix yet
        if pos then
            local home = ahrs:get_home()
            local d = pos:get_distance(home)
            if d < 1000 then
                item_dist.info = string.format("%dm", math.floor(d + 0.5))
            else
                item_dist.info = string.format("%.1fkm", d / 1000)
            end
        else
            item_dist.info = "no pos"
        end
    else
        item_dist.info = "no home"
    end

    -- Waypoint progress
    local idx   = mission:get_current_nav_index()
    local total = mission:num_commands()
    if total and total > 0 then
        item_wp.info = tostring(idx) .. "/" .. tostring(total)
    else
        item_wp.info = "-"
    end
end

local menu_definition = {
    name  = 'Status',
    items = { item_mode, item_armed, item_batt, item_sats, item_dist, item_wp },
}

local crsf_fn
local function loop()
    update_status()
    local nf, nd = crsf_fn()
    crsf_fn = nf or crsf_fn
    return loop, nd or 500
end

local crsf_delay
crsf_fn, crsf_delay = crsf_helper.register_menu(menu_definition)

if crsf_fn == nil then
    gcs:send_text(3, "Status CRSF: register_menu failed")
    return
end

gcs:send_text(6, "Status CRSF: menu registered OK")
return loop, crsf_delay
