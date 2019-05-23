-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LIB_IDENTIFIER = "LibGPS3"

assert(not _G[LIB_IDENTIFIER], LIB_IDENTIFIER .. " is already loaded")

local lib = {}
_G[LIB_IDENTIFIER] = lib

lib.internal = {
    class = {},
    logger = LibDebugLogger(LIB_IDENTIFIER),
    chat = LibChatMessage(LIB_IDENTIFIER, "LGPS"),
    TAMRIEL_MAP_INDEX = 1,
}

function lib.internal:Initialize()
    local class = self.class
    local logger = self.logger

    logger:Debug("Initializing LibGPS3...")
    local internal = lib.internal
    local TAMRIEL_MAP_INDEX = internal.TAMRIEL_MAP_INDEX

    local mapAdapter = class.MapAdapter:New()
    local meter = class.TamrielOMeter:New(mapAdapter)
    local waypointManager = class.WaypointManager:New(mapAdapter, meter)
    mapAdapter:SetWaypointManager(waypointManager)
    meter:SetWaypointManager(waypointManager)

    internal.mapAdapter = mapAdapter
    internal.meter = meter

    if(mapAdapter:SetMapToMapListIndexWithoutMeasuring(TAMRIEL_MAP_INDEX) == SET_MAP_RESULT_FAILED) then
        error("LibGPS could not switch to the Tamriel map for initialization")
    end

    -- no need to actually measure the world map
    local measurement = class.Measurement:New()
    measurement:SetId(mapAdapter:GetCurrentMapIdentifier())
    measurement:SetMapIndex(TAMRIEL_MAP_INDEX)
    meter:SetMeasurement(measurement, true)

    SetMapToPlayerLocation() -- initial measurement so we can get back to where we are currently

    EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER, EVENT_ADD_ON_LOADED, function(event, name)
        if(name ~= "LibGPS") then return end
        EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER, EVENT_ADD_ON_LOADED)
        meter:InitializeSaveData()
        logger:Debug("Saved Variables loaded")
    end)

    SLASH_COMMANDS["/libgpsreset"] = function()
        meter:Reset()
        self.chat:Print("All measurements have been cleared")
    end

    logger:Debug("Initialization complete")
end
