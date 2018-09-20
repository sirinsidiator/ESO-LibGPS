-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LGPS = LibGPS
local internal = LGPS.internal
local original = internal.original
local logger = internal.logger
local Measurement = LGPS.class.Measurement
local TAMRIEL_MAP_INDEX = LGPS.internal.TAMRIEL_MAP_INDEX
local mabs = math.abs

local POSITION_MIN = 0.085
local POSITION_MAX = 0.915

local TamrielOMeter = ZO_Object:Subclass()
LGPS.class.TamrielOMeter = TamrielOMeter

function TamrielOMeter:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function TamrielOMeter:Initialize()
    self.measurements = {}
    self.savedMeasurements = {}
    self.rootMaps = {}
    self.measuring = false
end

function TamrielOMeter:GetMeasurement(id)
    if(not self.measurements[id] and self.savedMeasurements[id]) then
        local measurement = Measurement:New()
        measurement:Deserialize(id, self.savedMeasurements[id])
        self.measurements[id] = measurement
    end
    return self.measurements[id]
end

function TamrielOMeter:SetMeasurement(measurement, isRootMap)
    self.measurements[measurement:GetId()] = measurement
    self.savedMeasurements[measurement:GetId()] = measurement:Serialize()
    if(isRootMap) then
        self.rootMaps[measurement:GetMapIndex()] = measurement
    end
end

function TamrielOMeter:RegisterRootMap(mapIndex)
    logger:Debug("Register root map " .. GetMapNameByIndex(mapIndex))
    self.rootMaps[mapIndex] = false
end

function TamrielOMeter:GetRootMapMeasurement(mapIndex)
    return self.rootMaps[mapIndex]
end

function TamrielOMeter:CalculateMeasurementsInternal(mapId, localX, localY)
    local adapter = internal.mapAdapter

    -- select the map corner farthest from the player position
    local wpX, wpY = POSITION_MIN, POSITION_MIN
    -- on some maps we cannot set the waypoint to the map border (e.g. Aurdion)
    -- Opposite corner:
    if(localX < 0.5) then wpX = POSITION_MAX end
    if(localY < 0.5) then wpY = POSITION_MAX end

    adapter:SetMeasurementWaypoint(wpX, wpY)

    -- add local points to seen maps
    local measurementPositions = {}
    measurementPositions[#measurementPositions + 1] = { mapId = mapId, pX = localX, pY = localY, wpX = wpX, wpY = wpY, rootMap = false }

    -- switch to zone map in order to get the mapIndex for the current location
    local x1, y1, x2, y2
    while not adapter:IsCurrentMapZoneMap() do
        if(not adapter:TryZoomOut()) then break end
        -- collect measurements for all maps we come through on our way to the zone map
        x1, y1, x2, y2 = adapter:GetReferencePoints()
        measurementPositions[#measurementPositions + 1] = { mapId = adapter:GetCurrentMapIdentifier(), pX = x1, pY = y1, wpX = x2, wpY = y2, rootMap = false }
    end

    -- some non-zone maps like Eyevea zoom directly to the Tamriel map
    local mapIndex = adapter:GetCurrentMapIndex()
    measurementPositions[#measurementPositions].rootMap = (self.rootMaps[mapIndex] ~= nil)
    if(mapIndex == nil) then mapIndex = TAMRIEL_MAP_INDEX end
    local zoneId = adapter:GetCurrentZoneId()

    -- switch to world map so we can calculate the global map scale and offset
    if(not adapter:TrySwitchToWorldMap()) then
        -- failed to switch to the world map
        logger:Warn("Could not switch to world map")
        return
    end

    -- get the two reference points on the world map
    x1, y1, x2, y2 = adapter:GetReferencePoints()

    -- calculate scale and offset for all maps that we saw
    local scaleX, scaleY, offsetX, offsetY
    for i = 1, #measurementPositions do
        local pos = measurementPositions[i]
        if(self:GetMeasurement(pos.mapId)) then break end -- we always go up in the hierarchy so we can stop once a measurement already exists
        logger:Debug("Store map measurement for " .. pos.mapId:sub(10, -7))
        scaleX = (x2 - x1) / (pos.wpX - pos.pX)
        scaleY = (y2 - y1) / (pos.wpY - pos.pY)
        offsetX = x1 - pos.pX * scaleX
        offsetY = y1 - pos.pY * scaleY
        if(mabs(scaleX - scaleY) > 1e-3) then
            logger:Warn(zo_strjoin(" ", "Current map measurement might be wrong", pos.mapId:sub(10, -7), mapIndex, pos.pX, pos.pY, pos.wpX, pos.wpY, x1, y1, x2, y2, offsetX, offsetY, scaleX, scaleY))
        end

        -- store measurements
        local measurement = self:GetMeasurement(pos.mapId) or Measurement:New()
        measurement:SetId(pos.mapId)
        measurement:SetMapIndex(mapIndex)
        measurement:SetZoneId(zoneId)
        measurement:SetScale(scaleX, scaleY)
        measurement:SetOffset(offsetX, offsetY)
        self:SetMeasurement(measurement, pos.rootMap)
    end

    return mapIndex
end

function TamrielOMeter:InitializeSaveData()
    local saveData = LibGPS_Data

    if(not saveData or saveData.version ~= GetAPIVersion()) then
        saveData = {
            version = GetAPIVersion(),
            measurements = {}
        }
    end

    for id, data in pairs(self.savedMeasurements) do
        saveData.measurements[id] = data
    end
    self.savedMeasurements = saveData

    LibGPS_Data = saveData
end

function TamrielOMeter:Reset()
    logger:Info("Removing all measurements")
    ZO_ClearTable(self.measurements)
    ZO_ClearTable(self.savedMeasurements)

    local tamrielMeasurement = self.rootMaps[TAMRIEL_MAP_INDEX]
    for rootMapIndex, measurement in pairs(self.rootMaps) do
        self.rootMaps[rootMapIndex] = false
    end
    self:SetMeasurement(tamrielMeasurement, true)
end

function TamrielOMeter:ClearCurrentMapMeasurements()
    local mapId = internal.mapAdapter:GetCurrentMapIdentifier()
    local measurement = self:GetMeasurement(mapId)

    if(measurement and measurement.mapIndex ~= TAMRIEL_MAP_INDEX) then
        logger:Info("Removing current map measurements")
        self.measurements[measurement:GetId()] = nil
        self.savedMeasurements[measurement:GetId()] = nil
        self.rootMaps[measurement.mapIndex] = false
    end
end

function TamrielOMeter:GetCurrentMapMeasurements()
    local mapId = internal.mapAdapter:GetCurrentMapIdentifier()
    local measurement = self:GetMeasurement(mapId)

    if (not measurement) then
        -- try to calculate the measurements if they are not yet available
        self:CalculateMapMeasurements()
    end

    return self.measurements[mapId]
end

function TamrielOMeter:TryCalculateRootMapMeasurement(rootMapIndex)
    -- switch to the map
    if(original.SetMapToMapListIndex(rootMapIndex) == SET_MAP_RESULT_FAILED) then
        logger:Warn(string.format("Could not switch to root map with index %d", rootMapIndex))
        return
    end

    local rootMapId = internal.mapAdapter:GetCurrentMapIdentifier()
    local measurement = self:GetMeasurement(rootMapId)
    if(not measurement) then
        -- calculate the measurements of map without worrying about the waypoint
        local mapIndex = self:CalculateMeasurementsInternal(rootMapId, internal.mapAdapter:GetPlayerPosition())
        measurement = self.measurements[rootMapId]

        if(mapIndex ~= rootMapIndex) then
            local name = internal.mapAdapter:GetFormattedMapName(rootMapIndex)
            logger:Warn(string.foramt("CalculateMeasurementsInternal returned different index while measuring %s map. expected: %d, actual: %d", name, rootMapIndex, mapIndex))

            if(not measurement) then
                logger:Warn(string.foramt("Failed to measure %s map.", name))
                return
            end
        end
    end

    return measurement
end

function TamrielOMeter:CalculateMapMeasurements(returnToInitialMap)
    local adapter = internal.mapAdapter

    -- cosmic map cannot be measured (GetMapPlayerWaypoint returns 0,0)
    if(adapter:IsCurrentMapCosmicMap()) then return false, SET_MAP_RESULT_CURRENT_MAP_UNCHANGED end

    -- no need to take measurements more than once
    local mapId = adapter:GetCurrentMapIdentifier()
    if(mapId == "" or self:GetMeasurement(mapId)) then return false, SET_MAP_RESULT_CURRENT_MAP_UNCHANGED end

    -- get the player position on the current map
    local localX, localY = adapter:GetPlayerPosition()
    if (localX == 0 and localY == 0) then
        -- cannot take measurements while player position is not initialized
        return false, SET_MAP_RESULT_CURRENT_MAP_UNCHANGED
    end

    logger:Debug("CalculateMapMeasurements for " .. mapId)

    returnToInitialMap = (returnToInitialMap ~= false)

    self:SetMeasuring(true)

    -- check some facts about the current map, so we can reset it later
    -- local oldMapIsZoneMap, oldMapFloor, oldMapFloorCount
    if(returnToInitialMap) then
        internal.mapStack:Push()
    end

    local hasWaypoint = adapter:HasPlayerWaypoint()
    if(hasWaypoint) then internal.waypointManager:Store() end

    local mapIndex = self:CalculateMeasurementsInternal(mapId, localX, localY)

    -- Until now, the waypoint was abused. Now the waypoint must be restored or removed again (not from Lua only).
    if(hasWaypoint) then
        internal.waypointManager:Restore()
    else
        adapter:RemovePlayerWaypoint()
    end

    if(returnToInitialMap) then
        local result = internal.mapStack:Pop()
        return true, result
    end

    return true, (mapId == adapter:GetCurrentMapIdentifier()) and SET_MAP_RESULT_CURRENT_MAP_UNCHANGED or SET_MAP_RESULT_MAP_CHANGED
end

function TamrielOMeter:SetMeasuring(measuring)
    local changed = (self.measuring ~= measuring)
    self.measuring = measuring
    if(changed) then
        CALLBACK_MANAGER:FireCallbacks(LGPS.LIB_EVENT_STATE_CHANGED, measuring)
    end
end

function TamrielOMeter:IsMeasuring()
    return self.measuring
end

function TamrielOMeter:FindRootMapMeasurementForCoordinates(x, y)
    logger:Debug("FindRootMapMeasurementForCoordinates(" .. x .. ", " .. y .. ")")
    for rootMapIndex, measurement in pairs(self.rootMaps) do
        logger:Debug(GetMapNameByIndex(rootMapIndex))
        if(not measurement) then
            logger:Debug("no measurement found")
            measurement = self:TryCalculateRootMapMeasurement(rootMapIndex)
        end

        logger:Debug("measurement found: " .. tostring(measurement ~= nil))
        if(measurement and measurement:Contains(x, y)) then
            logger:Debug("was inside")
            return measurement
        end
    end
end
