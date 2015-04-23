local LIB_NAME = "LibGPS2"
local lib = LibStub:NewLibrary(LIB_NAME, 3)

if not lib then
	return	-- already loaded and no upgrade necessary
end

local DUMMY_PIN_TYPE = LIB_NAME .. "DummyPin"
local LIB_IDENTIFIER_INIT = LIB_NAME .. "_Init"
local LIB_IDENTIFIER_UNMUTE = LIB_NAME .. "_UnmuteMapPing"
local LIB_IDENTIFIER_RESTORE = LIB_NAME .. "_Restore"
local LIB_EVENT_STATE_CHANGED = "OnLibGPS2MeasurementChanged"

local LOG_WARNING = "Warning"
local LOG_NOTICE = "Notice"

local mapMeasurements = {}
local mapPinManager = nil
local mapPingSound = SOUNDS.MAP_PING
local mapPingRemoveSound = SOUNDS.MAP_PING_REMOVE
local mutes = 0
local needWaypointRestore = false

local function LogMessage(type, message, ...)
    d(zo_strjoin(" ", LIB_NAME, type, message, ...))
end

local function UpdateWaypointPin()
	if(mapPinManager) then
		mapPinManager:RemovePins("pings", MAP_PIN_TYPE_PLAYER_WAYPOINT, "waypoint")

		local x, y = GetMapPlayerWaypoint()
		if(x ~= 0 and y ~= 0) then
			mapPinManager:CreatePin(MAP_PIN_TYPE_PLAYER_WAYPOINT, "waypoint", x, y)
		end
	else
		ZO_WorldMap_UpdateMap()
	end
end

local function MuteMapPing()
	SOUNDS.MAP_PING = nil
	SOUNDS.MAP_PING_REMOVE = nil
	mutes = mutes + 1
end

local function UnmuteMapPing()
  local function Restore()
    EVENT_MANAGER:UnregisterForUpdate(LIB_IDENTIFIER_RESTORE)
    SOUNDS.MAP_PING = mapPingSound
    SOUNDS.MAP_PING_REMOVE = mapPingRemoveSound
    CALLBACK_MANAGER:FireCallbacks(LIB_EVENT_STATE_CHANGED, false)
  end
    local wasMuted = mutes > 0
	mutes = mutes - 1
	if(mutes <= 0) then
		mutes = 0
        if wasMuted then
            if needWaypointRestore then
                d("do restore")
                UpdateWaypointPin()
                needWaypointRestore = false
            end
            EVENT_MANAGER:RegisterForUpdate(LIB_IDENTIFIER_RESTORE, 100, Restore)
        end
    end
end

local function HandleMapPingEvent(eventCode, pingEventType, pingType, pingTag, x, y, isPingOwner)
  local isWaypoint = (pingType == MAP_PIN_TYPE_PLAYER_WAYPOINT and pingTag == "waypoint")
  if mutes <= 0 or not isWaypoint then
    -- This is from worldmap.lua
    if(pingEventType == PING_EVENT_ADDED) then
      if isPingOwner then
          PlaySound(SOUNDS.MAP_PING)
      end
      mapPinManager:RemovePins("pings", pingType, pingTag)
      mapPinManager:CreatePin(pingType, pingTag, x, y)
    elseif(pingEventType == PING_EVENT_REMOVED) then
      if isPingOwner then
          PlaySound(SOUNDS.MAP_PING_REMOVE)
      end
      mapPinManager:RemovePins("pings", pingType, pingTag)
    end
  elseif isWaypoint then
	-- reset the sounds once we have seen all of the events we caused ourselves
	UnmuteMapPing()
  end
end

local function SetWaypointSilently(x, y)
	-- if a waypoint already exists, it will first be removed so we need to mute twice
	local wpX, wpY = GetMapPlayerWaypoint()
	if(wpX ~= 0 and wpY ~= 0) then
		MuteMapPing()
	end
	MuteMapPing()
	PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
end

local function GetMapInfoForReset()
	local isPlayerLocation = (GetMapName() == GetPlayerLocationName())
	local isZoneMap = (GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON)
	local isSubZoneMap = (GetMapType() == MAPTYPE_SUBZONE)
	local mapFloor, mapFloorCount = GetMapFloorInfo()
	return isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount
end

local function ResetToInitialMap(mapId, mapIndex, isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount)
    local needUpdate = false
	-- try to return to the initial map
	if(isPlayerLocation) then
    d("isPlayerLocation")
		needUpdate = SetMapToPlayerLocation() == SET_MAP_RESULT_MAP_CHANGED
	elseif(isZoneMap) then
    d("isZoneMap")
		needUpdate = SetMapToMapListIndex(mapIndex) == SET_MAP_RESULT_MAP_CHANGED
		if(mapId:find("eyevea")) then -- Eveyea is located on the Tamriel map, but not really a zone or sub zone
			ProcessMapClick(0.06224, 0.61272)
		end
	elseif(isSubZoneMap) then
    d("isSubZoneMap")
		needUpdate = SetMapToMapListIndex(mapIndex) == SET_MAP_RESULT_MAP_CHANGED

		-- determine where on the zone map we have to click to get to the sub zone map
		local x, y
		--if(mapId:find("porthunding")) then -- some maps do not work when we simply click in the middle (e.g. Port Hunding)
		--	x, y = 0.65757, 0.46926
		--elseif(mapId:find("eldenroot")) then
		--	x, y = 0.56497, 0.53504
		--else
			local subZone = mapMeasurements[mapId]
			local zone = mapMeasurements[GetMapTileTexture()]
			-- get global coordinates of sub zone center
			x = subZone.offsetX + subZone.scaleX / 2
			y = subZone.offsetY + subZone.scaleY / 2
			-- transform to local zone coordinates
			x = (x - zone.offsetX) / zone.scaleX
			y = (y - zone.offsetY) / zone.scaleY
		--end

		assert(WouldProcessMapClick(x, y), zo_strjoin(nil, "Could not switch to sub zone map \"", GetPlayerLocationName(), "\" mapIndex=", mapIndex, " at ", x, ", ", y))
		needUpdate = ProcessMapClick(x, y) == SET_MAP_RESULT_MAP_CHANGED or needUpdate
	end
    d("mapFloorCount", mapFloorCount)
	if(mapFloorCount > 0) then -- some maps do have different floors (e.g. Elden Root)
		needUpdate = SetMapFloor(mapFloor) == SET_MAP_RESULT_MAP_CHANGED or needUpdate
	end
    if needUpdate and not SCENE_MANAGER:IsShowing("worldMap") then
    d("needUpdate")
        CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged", false)
    end
end

-- Unregister handler from older libGPS
EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER_INIT, EVENT_PLAYER_ACTIVATED)

EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER_INIT, EVENT_PLAYER_ACTIVATED, function()
    local function InterceptMapPinManager()
        if(mapPinManager) then return end
        ZO_WorldMap_AddCustomPin(DUMMY_PIN_TYPE, function(pinManager)
            mapPinManager = pinManager
            ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], false)
        end, nil, {level = 0, size = 0, texture = ""})
        ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], true)
        ZO_WorldMap_RefreshCustomPinsOfType(_G[DUMMY_PIN_TYPE])
    end

	EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER_INIT, EVENT_PLAYER_ACTIVATED)

	InterceptMapPinManager()

    -- Unregister handler from older libGPS
    EVENT_MANAGER:UnregisterForEvent("LibGPS2_SaveWaypoint", EVENT_PLAYER_DEACTIVATED)
    EVENT_MANAGER:UnregisterForEvent("LibGPS2_RestoreWaypoint", EVENT_PLAYER_ACTIVATED)

    -- Unregister handler from older libGPS, otherwise the wrong handler is called
    EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER_UNMUTE, EVENT_MAP_PING)
    EVENT_MANAGER:UnregisterForEvent("ZO_WorldMap", EVENT_MAP_PING)

    EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER_UNMUTE, EVENT_MAP_PING, HandleMapPingEvent)
    -- Try get a cache before user starts to look around
    lib:CalculateCurrentMapMeasurements()
end)

-- ---------------------- public functions ----------------------

--- Removes all cached measurement values.
function lib:ClearMapMeasurements()
	mapMeasurements = {}
end

--- Removes the cached measurement values for the map that is currently active.
function lib:ClearCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	mapMeasurements[mapId] = nil
end

--- Calculates the measurements for the current map and all parent maps.
--- This method does nothing if there is already a cached measurement for the active map.
function lib:CalculateCurrentMapMeasurements()
  local function Measure(mapId, localX, localY)
    d("Measure", mapId, localX, localY)
    -- select the map corner farthest from the player position
	local wpX, wpY = 0.05, 0.05 -- on some maps we cannot set the waypoint to the map border (e.g. Aurdion)
    -- Opposite corner:
	if(localX < 0.5) then wpX = 0.95 end
	if(localY < 0.5) then wpY = 0.95 end

	-- set measurement waypoint
	SetWaypointSilently(wpX, wpY)

	-- add local points to seen maps
	local measurementPositions = {}
	table.insert(measurementPositions, {mapId = mapId, pX = localX, pY = localY, wpX = wpX, wpY = wpY })

	-- switch to zone map in order to get the mapIndex for the current location
	while not (GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON) do
		if(MapZoomOut() ~= SET_MAP_RESULT_MAP_CHANGED) then break end
		-- add all maps we come through to seen maps
		local x1, y1 = GetMapPlayerPosition("player")
		local x2, y2 = GetMapPlayerWaypoint()

		table.insert(measurementPositions, {mapId = GetMapTileTexture(), pX = x1, pY = y1, wpX = x2, wpY = y2 })
	end

	-- some non-zone maps like Eyevea zoom directly to the Tamriel map
	local mapIndex = GetCurrentMapIndex() or 1

	-- switch to world map so we can calculate the global map scale and offset
	SetMapToMapListIndex(1)
	if not (GetMapType() == MAPTYPE_WORLD) then LogMessage(LOG_NOTICE, "Could not switch to world map") return end -- failed to switch to the world map

	-- get the two reference points on the world map
	local x1, y1 = GetMapPlayerPosition("player")
	local x2, y2 = GetMapPlayerWaypoint()

	-- calculate scale and offset for all maps that we saw
	for _, m in ipairs(measurementPositions) do
		if(mapMeasurements[m.mapId]) then break end
		local scaleX = (x2 - x1) / (m.wpX - m.pX)
		local scaleY = (y2 - y1) / (m.wpY - m.pY)
		local offsetX = x1 - m.pX * scaleX
		local offsetY = y1 - m.pY * scaleY
		if(math.abs(scaleX - scaleY) > 1e-3) then
			LogMessage(LOG_WARNING, "Current map measurement might be wrong", m.mapId:sub(10, -7), mapIndex, m.pX, m.pY, m.wpX, m.wpY, x1, y1, x2, y2, offsetX, offsetY, scaleX, scaleY)
		end

		-- store measurements
		mapMeasurements[m.mapId] = {
			scaleX = scaleX,
			scaleY = scaleY,
			offsetX = offsetX,
			offsetY = offsetY,
			mapIndex = mapIndex
		}
	end
    return mapIndex
  end

	-- cosmic map cannot be measured (GetMapPlayerWaypoint returns 0,0)
	if(GetMapType() == MAPTYPE_COSMIC) then return end

	-- no need to take measurements more than once
	local mapId = GetMapTileTexture()
	if(mapMeasurements[mapId]) then d("cache2") return end

	-- no need to measure the world map
	if(GetMapType() == MAPTYPE_WORLD) then
		mapMeasurements[mapId] = {
			scaleX = 1,
			scaleY = 1,
			offsetX = 0,
			offsetY = 0,
			mapIndex = GetCurrentMapIndex()
		}
		return
	end

	-- get the player position on the current map
	local localX, localY = GetMapPlayerPosition("player")
	if(localX == 0 and localY == 0) then return end -- cannot take measurements while player position is not initialized

    ZO_WorldMap:StopMovingOrResizing()

d("CalculateCurrentMapMeasurements")
    CALLBACK_MANAGER:FireCallbacks(LIB_EVENT_STATE_CHANGED, true)

	-- check some facts about the current map, so we can reset it later
	local oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount = GetMapInfoForReset()

	-- save waypoint location
	local oldWaypointX, oldWaypointY = GetMapPlayerWaypoint()

    local mapIndex = Measure(mapId, localX, localY)

    -- Until now, the waypoint was abused. Now the waypoint must be restored or removed again (not from LUA only).
    -- Not necessarily on the map we are coming from. Therefore the waypoint is re-set at global or coldhabour level.
    if(oldWaypointX ~= 0 or oldWaypointY ~= 0) then
    d("restore waypoint")
        needWaypointRestore = true
        local measurements = mapMeasurements[mapId]
		local x = oldWaypointX * measurements.scaleX + measurements.offsetX
		local y = oldWaypointY * measurements.scaleY + measurements.offsetY
        -- setting a ping "twice" does not raise two events
        if(x > 0 and x < 1 and y > 0 and y < 1) then
        	PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
        else
    		-- when the waypoint is outside of the Tamriel map we can try if it is in coldharbour
            local coldharbourIndex = 23
			SetMapToMapListIndex(coldharbourIndex) -- set to coldharbour
			local coldharbourId = GetMapTileTexture()
            if not mapMeasurements[coldharbourId] then -- coldharbour measured?
                mutes = mutes - 1 -- another SetWaypointSilently without event
                -- measure only: no backup, no restore
                assert(Measure(coldharbourId, GetMapPlayerPosition("player")) == coldharbourIndex, "coldharbour is not map index 23?!?")
                SetMapToMapListIndex(coldharbourIndex) -- set to coldharbour
            end
			measurements = mapMeasurements[coldharbourId]

			-- calculate waypoint coodinates within coldharbour
			x = (x - measurements.offsetX) / measurements.scaleX
			y = (y - measurements.offsetY) / measurements.scaleY
			assert(not (x < 0 or x > 1 or y < 0 or y > 1), "Cannot reset waypoint because it was outside of the world map")
            PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
        end
    else
    d("no waypoint")
        -- setting and removing causes two events
        mutes = mutes + 1
        RemovePlayerWaypoint()
    end

    -- Go to initial map including coldhabour
	ResetToInitialMap(mapId, mapIndex, oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount)
end

--- Returns a table with the measurement values for the active map or nil if the measurements could not be calculated for some reason.
--- The table contains scaleX, scaleY, offsetX, offsetY and mapIndex.
--- scaleX and scaleY are the dimensions of the active map on the Tamriel map.
--- offsetX and offsetY are the offset of the top left corner on the Tamriel map.
--- mapIndex is the mapIndex of the parent zone of the current map.
function lib:GetCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	if(not mapMeasurements[mapId]) then -- try to calculate the measurements if they are not yet available
		lib:CalculateCurrentMapMeasurements()
	end
	return mapMeasurements[mapId]
end

--- Converts the given map coordinates on the current map into coordinates on the Tamriel map.
--- Returns x and y on the world map and the mapIndex of the parent zone
--- or nil if the measurements of the active map are not available.
function lib:LocalToGlobal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if(measurements) then
		x = x * measurements.scaleX + measurements.offsetX
		y = y * measurements.scaleY + measurements.offsetY
		return x, y, measurements.mapIndex
	end
end

--- Converts the given global coordinates into a position on the active map.
--- Returns x and y on the current map or nil if the measurements of the active map are not available.
function lib:GlobalToLocal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if(measurements) then
		x = (x - measurements.offsetX) / measurements.scaleX
		y = (y - measurements.offsetY) / measurements.scaleY
		return x, y
	end
end

--- Converts the given map coordinates on the specified zone map into coordinates on the Tamriel map.
--- This method is useful if you want to convert global positions from the old LibGPS version into the new format.
--- Returns x and y on the world map and the mapIndex of the parent zone
--- or nil if the measurements of the zone map are not available.
function lib:ZoneToGlobal(mapIndex, x, y)
	local mapId = GetMapTileTexture()
	local measurements = lib:GetCurrentMapMeasurements()
	local oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount = GetMapInfoForReset()

	SetMapToMapListIndex(mapIndex)
	lib:CalculateCurrentMapMeasurements()
	x, y, mapIndex = lib:LocalToGlobal(x, y)

	ResetToInitialMap(mapId, measurements.mapIndex, oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount)
	return x, y, mapIndex
end

--- This function zooms and pans to the specified position on the active map.
function lib:PanToMapPosition(x, y)
	-- if we don't have access to the mapPinManager we cannot do anything
	if(not mapPinManager) then return end

	-- create dummy pin
	local pin = mapPinManager:CreatePin(_G[DUMMY_PIN_TYPE], "libgpsdummy", x, y)

	-- replace GetPlayerPin to return our dummy pin
	local getPlayerPin = mapPinManager.GetPlayerPin
	mapPinManager.GetPlayerPin = function() return pin end

	-- let the map pan to our dummy pin
	ZO_WorldMap_PanToPlayer()

	-- cleanup
	mapPinManager.GetPlayerPin = getPlayerPin
	mapPinManager:RemovePins(DUMMY_PIN_TYPE)
end

--- This function sets the current map as player chosen so it won't snap back to the previous map.
function lib:SetPlayerChoseCurrentMap()
	-- replace the original functions
	local oldIsChangingAllowed = ZO_WorldMap_IsMapChangingAllowed
	local oldSetMapToMapListIndex = SetMapToMapListIndex
	ZO_WorldMap_IsMapChangingAllowed = function() return true end
	SetMapToMapListIndex = function() return SET_MAP_RESULT_MAP_CHANGED end

	-- make our rigged call to set the player chosen flag
	ZO_WorldMap_SetMapByIndex()

	-- cleanup
	ZO_WorldMap_IsMapChangingAllowed = oldIsChangingAllowed
	SetMapToMapListIndex = oldSetMapToMapListIndex
end

--- Repeatedly calls ProcessMapClick on the given global position starting on the Tamriel map until nothing more would happen.
--- Returns SET_MAP_RESULT_FAILED, SET_MAP_RESULT_MAP_CHANGED or SET_MAP_RESULT_CURRENT_MAP_UNCHANGED depending on the result of the API calls.
function lib:MapZoomInMax(x, y)
	local result = SetMapToMapListIndex(1)

	if(result ~= SET_MAP_RESULT_FAILED) then
		local localX, localY = x, y

		while WouldProcessMapClick(localX, localY) do
			result = ProcessMapClick(localX, localY)
			if(result == SET_MAP_RESULT_FAILED) then break end
			localX, localY = lib:GlobalToLocal(x, y)
		end
	end

	return result
end
