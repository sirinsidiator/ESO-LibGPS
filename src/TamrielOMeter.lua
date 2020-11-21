-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibGPS3
local internal = lib.internal
local Measurement = internal.class.Measurement
local MapStack = internal.class.MapStack

local logger = internal.logger
local mabs = math.abs

local TAMRIEL_MAP_INDEX = internal.TAMRIEL_MAP_INDEX
local BLACKREACH_ROOT_MAP_INDEX = internal.BLACKREACH_ROOT_MAP_INDEX
local SCALE_INACCURACY_WARNING_THRESHOLD = 1e-3
local DEFAULT_TAMRIEL_SIZE = 2500000
local MAP_CENTER = 0.5

local TamrielOMeter = ZO_Object:Subclass()
internal.class.TamrielOMeter = TamrielOMeter

function TamrielOMeter:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function TamrielOMeter:Initialize(adapter)
    self.adapter = adapter
    self.mapStack = MapStack:New(self, adapter)
    self.measurements = {}
    self.savedMeasurements = {}
    self.rootMaps = {}
    self.measuring = false

    self:RegisterRootMap(BLACKREACH_ROOT_MAP_INDEX) -- BlackReach
    self:RegisterRootMap(TAMRIEL_MAP_INDEX) -- Tamriel
    self:RegisterRootMap(GetMapIndexByZoneId(347)) -- Coldhabour
    self:RegisterRootMap(GetMapIndexByZoneId(980)) -- Clockwork City
    self:RegisterRootMap(GetMapIndexByZoneId(1027)) -- Artaeum
    -- Any future extra dimensional map here
end

function TamrielOMeter:Reset()
    logger:Info("Removing all measurements")
    ZO_ClearTable(self.measurements)
end

function TamrielOMeter:SetWaypointManager(waypointManager)
    self.waypointManager = waypointManager
end

function TamrielOMeter:RegisterRootMap(mapIndex)
    logger:Debug("Register root map", self.adapter:GetFormattedMapName(mapIndex))
    self.rootMaps[mapIndex] = false
end

function TamrielOMeter:GetRootMapMeasurement(mapIndex)
    return self.rootMaps[mapIndex]
end

function TamrielOMeter:GetMeasurement(id)
    return self.measurements[id]
end

function TamrielOMeter:SetMeasurement(measurement, isRootMap)
    self.measurements[measurement:GetId()] = measurement
    if(isRootMap) then
        self.rootMaps[measurement:GetMapIndex()] = measurement
    end
end

function TamrielOMeter:SetMeasuring(measuring)
    local changed = (self.measuring ~= measuring)
    self.measuring = measuring
    if(changed) then
        CALLBACK_MANAGER:FireCallbacks(lib.LIB_EVENT_STATE_CHANGED, measuring)
    end
end

function TamrielOMeter:IsMeasuring()
    return self.measuring
end

function TamrielOMeter:GetReferencePoints()
    local x1, y1 = self.adapter:GetPlayerPosition()
    local x2, y2 = self.waypointManager:GetPlayerWaypoint()
    return x1, y1, x2, y2
end

function TamrielOMeter:ClearCurrentMapMeasurement()
    local mapId = self.adapter:GetCurrentMapIdentifier()
    local measurement = self:GetMeasurement(mapId)

    if(measurement and measurement.mapIndex ~= TAMRIEL_MAP_INDEX) then
        logger:Info("Removing current map measurements")
        self.measurements[measurement:GetId()] = nil
        self.rootMaps[measurement.mapIndex] = false
    end
end

function TamrielOMeter:GetCurrentMapMeasurement()
    local mapId = self.adapter:GetCurrentMapIdentifier()
    local measurement = self:GetMeasurement(mapId)

    if (not measurement) then
        -- try to calculate the measurement if they are not yet available
        self:CalculateMapMeasurement()
    end

    return self.measurements[mapId]
end

function TamrielOMeter:TryCalculateRootMapMeasurement(rootMapIndex)
    local mapId = GetMapIdByIndex(rootMapIndex)
    local measurement = self:GetMeasurement(mapId)
    if(not measurement) then
        -- calculate the measurements of map without worrying about the waypoint
        local offsetX, offsetY, scaleX, scaleY = self.adapter:GetUniversallyNormalizedMapInfo(mapId)
        local zoneIndex = select(4, GetMapInfoById(mapId))
        local zoneId = GetZoneId(zoneIndex)

        local measurement = Measurement:New()
        measurement:SetId(mapId)
        measurement:SetMapIndex(rootMapIndex)
        measurement:SetZoneId(zoneId)
        measurement:SetScale(scaleX, scaleY)
        measurement:SetOffset(offsetX, offsetY)
        self:SetMeasurement(measurement, true)
    end

    return measurement
end

function TamrielOMeter:CalculateMapMeasurement()
    local adapter = self.adapter

    -- no need to take measurements more than once
    local mapId = adapter:GetCurrentMapIdentifier()
    if(mapId == 0 or self:GetMeasurement(mapId)) then return false, SET_MAP_RESULT_CURRENT_MAP_UNCHANGED end

    local offsetX, offsetY, scaleX, scaleY = adapter:GetUniversallyNormalizedMapInfo(mapId)
    local zoneId = adapter:GetCurrentZoneId()
    local mapIndex = adapter:GetCurrentMapIndex()

    local measurement = Measurement:New()
    measurement:SetId(mapId)
    measurement:SetMapIndex(mapIndex)
    measurement:SetZoneId(zoneId)
    measurement:SetScale(scaleX, scaleY)
    measurement:SetOffset(offsetX, offsetY)
    self:SetMeasurement(measurement, self.rootMaps[mapIndex] ~= nil)

    return true, SET_MAP_RESULT_CURRENT_MAP_UNCHANGED
end

function TamrielOMeter:FindRootMapMeasurementForCoordinates(x, y)
    logger:Debug("FindRootMapMeasurementForCoordinates(%f, %f)", x, y)
    for rootMapIndex, measurement in pairs(self.rootMaps) do
        if(not measurement) then
            measurement = self:TryCalculateRootMapMeasurement(rootMapIndex)
        end

        if(measurement and measurement:Contains(x, y)) then
            logger:Debug("Point is inside " .. self.adapter:GetFormattedMapName(rootMapIndex))
            return measurement
        end
    end
    logger:Warn("No matching root map found for coordinates (%f, %f)", x, y)
end

function TamrielOMeter:PushCurrentMap()
    return self.mapStack:Push()
end

function TamrielOMeter:PopCurrentMap()
    return self.mapStack:Pop()
end

local function getScaleMapId(self, mapId)
    local zoneId = self.adapter:GetPlayerZoneId()
    return mapId + zoneId * 100000, zoneId
end
local function getCurrentWorldSize(self, notMeasuring)
    local adapter = self.adapter
    SetMapToPlayerLocation()
    local mapId = adapter:GetCurrentMapIdentifier()
    if(mapId == 0) then return DEFAULT_TAMRIEL_SIZE, DEFAULT_TAMRIEL_SIZE end

    local scaleMapId, zoneId = getScaleMapId(self, mapId)
    local size = adapter:GetWorldSize(scaleMapId)
    if not size:IsValid() then
        -- This can happend, e.g. by porting
        -- no need to take measurements more than once

        -- get the player position on the current map
        local localX, localY = adapter:GetPlayerPosition()
        if (localX == 0 and localY == 0) then
            -- cannot take measurements while player position is not initialized
            return DEFAULT_TAMRIEL_SIZE, DEFAULT_TAMRIEL_SIZE
        end

        logger:Debug("Calculate current world size of ", mapId, " for zone ", zoneId)

        self:SetMeasuring(true)
        local waypointManager = self.waypointManager
        local scaleX, scaleY = DEFAULT_TAMRIEL_SIZE, DEFAULT_TAMRIEL_SIZE

        if notMeasuring then
            waypointManager.suppressCount = waypointManager.suppressCount + 1
            waypointManager.LMP:SuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
        end

        local wx1, wy1
        -- Make sure the waypoint is at a different location
        if mapId == 1747 then -- but not too far for blackreach
            wx1, wy1 = localX < 0.5 and (localX + 0.02) or (localX - 0.02), localY < 0.5 and (localY + 0.02) or (localY - 0.02)
        else
            wx1, wy1 = localX < 0.5 and 0.75 or 0.25, localY < 0.5 and 0.75 or 0.25
        end

        size:SetMapId(mapId)
        size:SetZoneId(zoneId)
        adapter:SetWorldSize(scaleMapId, size) -- Assume default scale
        waypointManager:SetPlayerWaypoint(wx1, wy1)
        -- The assumed scale may wrong. Lets see how wrong:
        local wpX1, wpY1 = waypointManager:GetPlayerWaypoint()
        -- correct scale, so that we get the values we want:
        local correctX, correctY = (wx1 - localX) / (wpX1 - localX), (wy1 - localY) / (wpY1 - localY)
        scaleX, scaleY = math.floor(correctX * scaleX * 0.01 + 0.4) * 100, math.floor(correctY * scaleY * 0.01 + 0.4) * 100

        size:SetSize(scaleX, scaleY)
        adapter:SetWorldSize(scaleMapId, size)
        return size, true
    end
    return size, false
end

function TamrielOMeter:GetCurrentWorldSize()
    local adapter = self.adapter
    local size

    if adapter:IsCurrentMapPlayerLocation() then
        local mapId = adapter:GetCurrentMapIdentifier()
        local scaleMapId = getScaleMapId(self, mapId)
        size = adapter:GetWorldSize(scaleMapId)
        if size:IsValid() then
            return size
        end
    end

    self:PushCurrentMap()
    local waypointManager = self.waypointManager
    local notMeasuring = not lib:IsMeasuring()
    if not notMeasuring then
        logger:Debug("Still measuring. No waypoint restore.")
    end
    local hasWaypoint = notMeasuring and waypointManager:HasPlayerWaypoint()
    if(hasWaypoint) then waypointManager:StorePlayerWaypoint() end

    size, wasMeasuring = getCurrentWorldSize(self, notMeasuring)

    self:PopCurrentMap()
    if notMeasuring and wasMeasuring then
        -- Until now, the waypoint was abused. Now the waypoint must be restored or removed again (not from Lua only).
        if(hasWaypoint) then
            waypointManager:RestorePlayerWaypoint()
        else
            waypointManager:RemovePlayerWaypoint()
        end
        waypointManager:ClearPlayerWaypoint()
    end
    return size
end

function TamrielOMeter:GetLocalDistanceInMeters(lx1, ly1, lx2, ly2)
    if not (lx1 or ly1 or lx2 or ly2) then return 0 end
    lx1, ly1 = lx1 - lx2, ly1 - ly2
    local worldSizeX, worldSizeY = self:GetWorldGlobalRatio()
    local measurement = self:GetCurrentMapMeasurement()
    return math.sqrt(lx1*lx1 * measurement.scaleX * worldSizeX + ly1*ly1 * measurement.scaleY * worldSizeY) * 0.01 * DEFAULT_TAMRIEL_SIZE
end

function TamrielOMeter:GetGlobalDistanceInMeters(gx1, gy1, gx2, gy2)
    if not (gx1 or gy1 or gx2 or gy2) then return 0 end
    gx1, gy1 = gx1 - gx2, gy1 - gy2
    local worldSize = self:GetWorldGlobalRatio() * DEFAULT_TAMRIEL_SIZE
    return math.sqrt(gx1*gx1 + gy1*gy1) * 0.01 * worldSize
end

local scaleIdToGlobalRatio = {}
function TamrielOMeter:GetWorldGlobalRatio()
    local adapter = self.adapter
    local mapId = adapter:GetCurrentMapIdentifier()
    local scaleMapId, zoneId = getScaleMapId(self, mapId)
    local scaleX = scaleIdToGlobalRatio[scaleMapId]
    if not scaleX then
        local size = self:GetCurrentWorldSize()
        scaleX, scaleY = size:GetSize()
        scaleX, scaleY = scaleX / DEFAULT_TAMRIEL_SIZE, scaleY / DEFAULT_TAMRIEL_SIZE
        local waypointManager = self.waypointManager
        if zoneId == 1161 then
            scaleX, scaleY = scaleX * 7, scaleY * 7
        end
        scaleIdToGlobalRatio[scaleMapId] = { scaleX, scaleY }
    else
        scaleX, scaleY = unpack(scaleX)
    end
    return scaleX, scaleY
end

function TamrielOMeter:GetGlobalWorldRatio()
    local scaleX, scaleY = self:GetWorldGlobalRatio()
    return 1 / scaleX, 1 / scaleY
end
