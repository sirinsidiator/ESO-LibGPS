-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local MAJOR, MINOR = "LibGPS3", _LGPS_VERSION_NUMBER or -1
local LGPS = LibStub:NewLibrary(MAJOR, MINOR)
assert(LGPS, "LibGPS3 was loaded more than once. Please ensure that its files are not included from other addons.")
LibGPS = LGPS

local TAMRIEL_MAP_INDEX = 1
local logger = LibDebugLogger.Create(MAJOR)

LGPS.class = {}
LGPS.internal = {
    TAMRIEL_MAP_INDEX = TAMRIEL_MAP_INDEX,
    logger = logger
}
LGPS.LIB_EVENT_STATE_CHANGED = "OnLibGPS3MeasurementChanged"

LGPS.internal.Initialize = function()
    logger:Debug("Initializing LibGPS3...")
    local internal = LGPS.internal
    local TAMRIEL_MAP_INDEX = internal.TAMRIEL_MAP_INDEX

    local mapAdapter = LGPS.class.MapAdapter:New()
    local meter = LGPS.class.TamrielOMeter:New(mapAdapter)
    local waypointManager = LGPS.class.WaypointManager:New(mapAdapter, meter)
    mapAdapter:SetWaypointManager(waypointManager)
    meter:SetWaypointManager(waypointManager)

    internal.mapAdapter = mapAdapter
    internal.meter = meter

    if(mapAdapter:SetMapToMapListIndexWithoutMeasuring(TAMRIEL_MAP_INDEX) == SET_MAP_RESULT_FAILED) then
        error("LibGPS could not switch to the Tamriel map for initialization")
    end

    -- no need to actually measure the world map
    local measurement = LGPS.class.Measurement:New()
    measurement:SetId(mapAdapter:GetCurrentMapIdentifier())
    measurement:SetMapIndex(TAMRIEL_MAP_INDEX)
    meter:SetMeasurement(measurement, true)

    SetMapToPlayerLocation() -- initial measurement so we can get back to where we are currently

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
