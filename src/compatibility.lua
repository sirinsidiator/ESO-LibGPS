-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local MAJOR, MINOR = "LibGPS2", 16
local lib = LibStub:NewLibrary(MAJOR, MINOR)
assert(lib, "LibGPS2 compatibility layer was loaded more than once. Please ensure that its files are not included from other addons.")

local LGPS = LibGPS
local logger = LGPS.internal.logger

--- Unregister handler from older libGPS ( < 3)
EVENT_MANAGER:UnregisterForEvent("LibGPS2_SaveWaypoint", EVENT_PLAYER_DEACTIVATED)
EVENT_MANAGER:UnregisterForEvent("LibGPS2_RestoreWaypoint", EVENT_PLAYER_ACTIVATED)

--- Unregister handler from older libGPS ( <= 5.1)
EVENT_MANAGER:UnregisterForEvent("LibGPS2_Init", EVENT_PLAYER_ACTIVATED)

--- Unregister handler from older libGPS, as it is now managed by LibMapPing ( >= 6)
EVENT_MANAGER:UnregisterForEvent("LibGPS2_UnmuteMapPing", EVENT_MAP_PING)

if (lib.Unload) then
    -- Undo action from older libGPS ( >= 5.2)
    lib:Unload()
    if (lib.suppressCount > 0) then
        logger:Warn("There is a measurement in progress before loading is completed.")

        local LMP = LibStub("LibMapPing")
        EVENT_MANAGER:UnregisterForUpdate("LibGPS2_Finalize")
        while lib.suppressCount > 0 do
            LMP:UnsuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
            lib.suppressCount = lib.suppressCount - 1
        end
    end
end

function lib:IsReady()
    return LGPS:IsReady()
end

function lib:IsMeasuring()
    return LGPS:IsMeasuring()
end

function lib:ClearMapMeasurements()
    return LGPS:ClearMapMeasurements()
end

function lib:ClearCurrentMapMeasurements()
    return LGPS:ClearCurrentMapMeasurements()
end

function lib:GetCurrentMapMeasurements()
    return LGPS:GetCurrentMapMeasurements()
end

function lib:GetCurrentMapParentZoneIndices()
    local mapIndex, zoneIndex = LGPS:GetCurrentMapParentZoneIndices()
    return mapIndex, zoneIndex
end

function lib:CalculateMapMeasurements(returnToInitialMap)
    return LGPS:CalculateMapMeasurements(returnToInitialMap)
end

function lib:LocalToGlobal(x, y)
    local measurement = LGPS.internal.meter:GetCurrentMapMeasurements()
    if(measurement) then
        return measurement:ToGlobal(x, y), measurement:GetMapIndex()
    end
end

function lib:GlobalToLocal(x, y)
    return LGPS:GlobalToLocal(x, y)
end

function lib:ZoneToGlobal(mapIndex, x, y)
    lib:GetCurrentMapMeasurements()
    -- measurement done in here:
    SetMapToMapListIndex(mapIndex)
    x, y, mapIndex = lib:LocalToGlobal(x, y)
    return x, y, mapIndex
end

function lib:PanToMapPosition(x, y)
    return LGPS:PanToMapPosition(x, y)
end

function lib:SetPlayerChoseCurrentMap()
    return LGPS:SetPlayerChoseCurrentMap()
end

function lib:SetMapToRootMap(x, y)
    return LGPS:SetMapToRootMap(x, y)
end

function lib:MapZoomInMax(x, y)
    return LGPS:MapZoomInMax(x, y)
end

function lib:PushCurrentMap()
    return LGPS:PushCurrentMap()
end

function lib:PopCurrentMap()
    return LGPS:PopCurrentMap()
end

LGPS.internal.Initialize()
