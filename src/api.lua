-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LGPS = LibGPS
local internal = LGPS.internal
local original = internal.original
local logger = internal.logger

local mapStack = LGPS.class.MapStack:New()

--- Returns true as long as the player exists.
function LGPS:IsReady()
    return DoesUnitExist("player")
end

--- Returns true if the library is currently doing any measurements.
function LGPS:IsMeasuring()
    return internal.meter:IsMeasuring()
end

--- Removes all cached measurement values.
function LGPS:ClearMapMeasurements()
    internal.meter:Reset()
end

--- Removes the cached measurement values for the map that is currently active.
function LGPS:ClearCurrentMapMeasurements()
    internal.meter:ClearCurrentMapMeasurements()
end

--- Returns a table with the measurement values for the active map or nil if the measurements could not be calculated for some reason.
--- The table contains scaleX, scaleY, offsetX, offsetY and mapIndex.
--- scaleX and scaleY are the dimensions of the active map on the Tamriel map.
--- offsetX and offsetY are the offset of the top left corner on the Tamriel map.
--- mapIndex is the mapIndex of the parent zone of the current map.
function LGPS:GetCurrentMapMeasurements()
    return internal.meter:GetCurrentMapMeasurements()
end

--- Returns the mapIndex and zoneIndex of the parent zone for the currently set map.
--- return[1] number - The mapIndex of the parent zone
--- return[2] number - The zoneIndex of the parent zone
--- return[3] number - The zoneId of the parent zone
function LGPS:GetCurrentMapParentZoneIndices()
    local measurement = internal.meter:GetCurrentMapMeasurements()
    local mapIndex = measurement:GetMapIndex()
    local zoneId = measurement:GetZoneId()

    if(zoneId == 0) then
        mapStack:Push()
        SetMapToMapListIndex(mapIndex)
        zoneId = internal.adapter:GetCurrentZoneId()
        measurement:SetZoneId(zoneId)
        mapStack:Pop()
    end

    local zoneIndex = GetZoneIndex(zoneId)
    return mapIndex, zoneIndex, zoneId
end

--- Calculates the measurements for the current map and all parent maps.
--- This method does nothing if there is already a cached measurement for the active map.
--- return[1] boolean - True, if a valid measurement was calculated
--- return[2] SetMapResultCode - Specifies if the map has changed or failed during measurement (independent of the actual result of the measurement)
function LGPS:CalculateMapMeasurements(returnToInitialMap)
    return internal.meter:CalculateMapMeasurements(returnToInitialMap)
end

--- Converts the given map coordinates on the current map into coordinates on the Tamriel map.
--- Returns x and y on the world map or nil if the measurements of the active map are not available.
function LGPS:LocalToGlobal(x, y)
    local measurement = internal.meter:GetCurrentMapMeasurements()
    if(measurement) then
        return measurement:ToGlobal(x, y)
    end
end

--- Converts the given global coordinates into a position on the active map.
--- Returns x and y on the current map or nil if the measurements of the active map are not available.
function LGPS:GlobalToLocal(x, y)
    local measurement = internal.meter:GetCurrentMapMeasurements()
    if(measurement) then
        return measurement:ToLocal(x, y)
    end
end

--- This function zooms and pans to the specified position on the active map.
function LGPS:PanToMapPosition(x, y)
    return internal.adapter:PanToMapPosition(x, y)
end

--- This function sets the current map as player chosen so it won't switch back to the previous map.
function LGPS:SetPlayerChoseCurrentMap()
    return internal.adapter:SetPlayerChoseCurrentMap()
end

--- Sets the best matching root map: Tamriel, Cold Harbour or Clockwork City and what ever will come.
--- Returns SET_MAP_RESULT_FAILED, SET_MAP_RESULT_MAP_CHANGED depending on the result of the API calls.
function LGPS:SetMapToRootMap(x, y)
    local measurement = internal.meter:FindRootMapMeasurementForCoordinates(x, y)
    if(not measurement) then return SET_MAP_RESULT_FAILED end

    return original.SetMapToMapListIndex(measurement:GetMapIndex())
end

--- Repeatedly calls ProcessMapClick on the given global position starting on the Tamriel map until nothing more would happen.
--- Returns SET_MAP_RESULT_FAILED, SET_MAP_RESULT_MAP_CHANGED or SET_MAP_RESULT_CURRENT_MAP_UNCHANGED depending on the result of the API calls.
function LGPS:MapZoomInMax(x, y)
    local result = LGPS:SetMapToRootMap(x, y)

    if (result ~= SET_MAP_RESULT_FAILED) then
        local localX, localY = LGPS:GlobalToLocal(x, y)

        while WouldProcessMapClick(localX, localY) do
            result = original.ProcessMapClick(localX, localY)
            if (result == SET_MAP_RESULT_FAILED) then break end
            localX, localY = LGPS:GlobalToLocal(x, y)
        end
    end

    return result
end

--- Stores information about how we can back to this map on a stack.
function LGPS:PushCurrentMap()
    mapStack:Push()
end

--- Switches to the map that was put on the stack last.
--- Returns SET_MAP_RESULT_FAILED, SET_MAP_RESULT_MAP_CHANGED or SET_MAP_RESULT_CURRENT_MAP_UNCHANGED depending on the result of the API calls.
function LGPS:PopCurrentMap()
    return mapStack:Pop()
end
