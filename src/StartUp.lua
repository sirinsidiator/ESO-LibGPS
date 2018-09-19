-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local MAJOR, MINOR = "LibGPS3", _LGPS_VERSION_NUMBER or -1
local LGPS = LibStub:NewLibrary(MAJOR, MINOR)
assert(LGPS, "LibGPS3 was loaded more than once. Please ensure that its files are not included from other addons.")
LibGPS = LGPS

local TAMRIEL_MAP_INDEX = 1
local LIB_IDENTIFIER_FINALIZE = "LibGPS3_Finalize"
local logger = LibDebugLogger.Create(MAJOR)

LGPS.class = {}
LGPS.internal = {
    TAMRIEL_MAP_INDEX = TAMRIEL_MAP_INDEX,
    original = {},
    logger = logger
}
LGPS.LIB_EVENT_STATE_CHANGED = "OnLibGPS3MeasurementChanged"

local function HookSetMapToFunction(funcName, returnToInitialMap, skipSecondCall)
    local orgFunction = _G[funcName]
    LGPS.internal.original[funcName] = orgFunction
    _G[funcName] = function(...)
        local result = orgFunction(...)
        if(result ~= SET_MAP_RESULT_MAP_FAILED and not LGPS:GetCurrentMapMeasurements()) then
            logger:Debug(funcName)

            local success, mapResult = LGPS:CalculateMapMeasurements(returnToInitialMap)
            if(mapResult ~= SET_MAP_RESULT_CURRENT_MAP_UNCHANGED) then
                result = mapResult
            end

            if(skipSecondCall) then return end
            orgFunction(...)
        end

        -- All stuff is done before anyone triggers an "OnWorldMapChanged" event due to this result
        return result
    end
end

LGPS.internal.Initialize = function()
    logger:Debug("Initializing LibGPS3...")
    local internal = LGPS.internal
    local original = internal.original
    local TAMRIEL_MAP_INDEX = internal.TAMRIEL_MAP_INDEX

    local mapAdapter = LGPS.class.MapAdapter:New()
    local meter = LGPS.class.TamrielOMeter:New()
    local mapStack = LGPS.class.MapStack:New()
    local waypointManager = LGPS.class.WaypointManager:New()

    internal.mapAdapter = mapAdapter
    internal.meter = meter
    internal.mapStack = mapStack
    internal.waypointManager = waypointManager

    HookSetMapToFunction("SetMapToQuestCondition")
    HookSetMapToFunction("SetMapToQuestStepEnding")
    HookSetMapToFunction("SetMapToQuestZone")
    HookSetMapToFunction("SetMapToMapListIndex")
    HookSetMapToFunction("SetMapToPlayerLocation", false)
    HookSetMapToFunction("ProcessMapClick", true, true) -- Returning is done via clicking already
    HookSetMapToFunction("SetMapFloor", true)

    meter:RegisterRootMap(1) -- Tamriel
    meter:RegisterRootMap(GetMapIndexByZoneId(347)) -- Coldhabour
    meter:RegisterRootMap(GetMapIndexByZoneId(980)) -- Clockwork City
    meter:RegisterRootMap(GetMapIndexByZoneId(1027)) -- Artaeum
    -- Any future extra dimensional map here

    if (original.SetMapToMapListIndex(TAMRIEL_MAP_INDEX) == SET_MAP_RESULT_FAILED) then
        error("LibGPS could not switch to the Tamriel map for initialization")
    end

    -- no need to actually measure the world map
    local measurement = LGPS.class.Measurement:New()
    measurement:SetId(mapAdapter:GetCurrentMapIdentifier())
    measurement:SetMapIndex(TAMRIEL_MAP_INDEX)
    meter:SetMeasurement(measurement, true)

    SetMapToPlayerLocation() -- initial measurement so we can get back to where we are currently

    local function FinalizeMeasurement()
        EVENT_MANAGER:UnregisterForUpdate(LIB_IDENTIFIER_FINALIZE)
        mapAdapter:UnsuppressWaypoint()
        waypointManager:RefreshMapPinIfNeeded()
        meter:SetMeasuring(false)
    end

    local function HandlePingEvent(pingType, pingTag, x, y, isPingOwner)
        if(not isPingOwner or pingType ~= MAP_PIN_TYPE_PLAYER_WAYPOINT or not meter:IsMeasuring()) then return end
        -- we delay our handler until all events have been fired and so that other addons can react to it first in case they use IsMeasuring
        EVENT_MANAGER:UnregisterForUpdate(LIB_IDENTIFIER_FINALIZE)
        EVENT_MANAGER:RegisterForUpdate(LIB_IDENTIFIER_FINALIZE, 0, FinalizeMeasurement)
    end
    mapAdapter:RegisterPingHandler(HandlePingEvent)

    EVENT_MANAGER:RegisterForEvent(MAJOR, EVENT_ADD_ON_LOADED, function(event, name)
        if(name ~= "LibGPS") then return end
        EVENT_MANAGER:UnregisterForEvent(MAJOR, EVENT_ADD_ON_LOADED)
        meter:InitializeSaveData()
        logger:Debug("Saved Variables loaded")
    end)

    SLASH_COMMANDS["/libgpsreset"] = function()
        meter:Reset()
        d("All LibGPS measurements have been cleared")
    end

    logger:Debug("Initialization complete")
end
