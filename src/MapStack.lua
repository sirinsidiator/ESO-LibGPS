-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LGPS = LibGPS
local internal = LGPS.internal
local original = internal.original
local logger = internal.logger
local TAMRIEL_MAP_INDEX = LGPS.internal.TAMRIEL_MAP_INDEX
local tremove = table.remove

local MapStack = ZO_Object:Subclass()
LGPS.class.MapStack = MapStack

function MapStack:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function MapStack:Initialize()
    self.stack = {}
end

function MapStack:Push()
    local wasPlayerLocation = DoesCurrentMapMatchMapForPlayerLocation()
    local targetMapTileTexture = internal.mapAdapter:GetCurrentMapIdentifier()
    local currentMapFloor, currentMapFloorCount = GetMapFloorInfo()
    local currentMapIndex = GetCurrentMapIndex()
    local zoom = internal.mapAdapter:GetCurrentZoom()
    local offsetX, offsetY = internal.mapAdapter:GetCurrentOffset()

    local mapStack = self.stack
    mapStack[#mapStack + 1] = {
        wasPlayerLocation,
        targetMapTileTexture,
        currentMapFloor, currentMapFloorCount,
        currentMapIndex,
        zoom,
        offsetX, offsetY
    }
end

function MapStack:Pop()
    local mapStack = self.stack
    local data = tremove(mapStack, #mapStack)
    if(not data) then
        logger:Debug("Pop map failed. No data on map stack.")
        return SET_MAP_RESULT_FAILED
    end

    local wasPlayerLocation, targetMapTileTexture, currentMapFloor, currentMapFloorCount, currentMapIndex, zoom, offsetX, offsetY = unpack(data)
    local currentTileTexture = internal.mapAdapter:GetCurrentMapIdentifier()
    if(currentTileTexture == targetMapTileTexture) then
        return SET_MAP_RESULT_CURRENT_MAP_UNCHANGED
    end

    local result = SET_MAP_RESULT_FAILED
    if(wasPlayerLocation) then
        result = original.SetMapToPlayerLocation()

    elseif(currentMapIndex ~= nil and currentMapIndex > 0) then -- set to a zone map
        result = original.SetMapToMapListIndex(currentMapIndex)

    else -- here is where it gets tricky
        logger:Debug("Try to navigate back to " .. targetMapTileTexture)
        -- first we try to get more information about our target map
        local target = internal.meter:GetMeasurement(targetMapTileTexture)
        if(not target) then -- always just return to player map if we cannot restore the previous map.
            logger:Debug(string.format("No measurement for \"%s\". Returning to player location.", targetMapTileTexture))
            return original.SetMapToPlayerLocation()
        end

        local rootMap = internal.meter:GetRootMapMeasurement(target:GetMapIndex())
        if(not rootMap or target:GetMapIndex() == TAMRIEL_MAP_INDEX) then -- zone map has no mapIndex (e.g. Eyevea or Hew's Bane on first PTS patch for update 9)
            local x, y = target:GetCenter()
            rootMap = internal.meter:FindRootMapMeasurementForCoordinates(x, y)
            if(not rootMap) then
                logger:Debug(string.format("No root map found for \"%s\". Returning to player location.", target:GetId()))
                return original.SetMapToPlayerLocation()
            end
        end

        -- switch to the parent zone
        logger:Debug("switch to the parent zone " .. GetMapNameByIndex(rootMap:GetMapIndex()))
        result = original.SetMapToMapListIndex(rootMap:GetMapIndex())
        if(result == SET_MAP_RESULT_FAILED) then return result end

        -- try to click on the center of the target map
        local x, y = rootMap:ToLocal(target:GetCenter())
        if(not WouldProcessMapClick(x, y)) then
            logger:Debug(string.format("Cannot process click at %s/%s on root map \"%s\" in order to get to \"%s\". Returning to player location instead.", tostring(x), tostring(y), rootMap:GetId(), target:GetId()))
            return original.SetMapToPlayerLocation()
        end

        result = original.ProcessMapClick(x, y)
        if(result == SET_MAP_RESULT_FAILED) then return result end

        -- switch to the sub zone if needed
        currentTileTexture = internal.mapAdapter:GetCurrentMapIdentifier()
        if(currentTileTexture ~= targetMapTileTexture) then
            logger:Debug("switch to the sub zone " .. targetMapTileTexture)
            local current = internal.meter:GetMeasurement(currentTileTexture)
            if(not current) then
                logger:Debug(string.format("No measurement for \"%s\". Returning to player location.", currentTileTexture))
                return original.SetMapToPlayerLocation()
            end

            -- determine where on the zone map we have to click to get to the sub zone map
            -- get local coordinates of target map center
            local x, y = current:ToLocal(target:GetCenter())
            if(not WouldProcessMapClick(x, y)) then
                logger:Debug(string.format("Cannot process click at %s/%s on zone map \"%s\" in order to get to \"%s\". Returning to player location instead.", tostring(x), tostring(y), current:GetId(), target:GetId()))
                return original.SetMapToPlayerLocation()
            end

            result = original.ProcessMapClick(x, y)
            if(result == SET_MAP_RESULT_FAILED) then return result end
        end

        -- switch to the correct floor (e.g. Elden Root)
        if (currentMapFloorCount > 0) then
            logger:Debug("switch to floor " .. currentMapFloor)
            result = original.SetMapFloor(currentMapFloor)
        end

        if (result ~= SET_MAP_RESULT_FAILED) then
            logger:Debug("set zoom and offset")
            internal.mapAdapter:SetCurrentZoom(zoom)
            internal.mapAdapter:SetCurrentOffset(offsetX, offsetY)
        end
    end

    return result
end
