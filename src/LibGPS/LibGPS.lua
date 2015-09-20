-- LibGPS2 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LIB_NAME = "LibGPS2"
local lib = LibStub:NewLibrary(LIB_NAME, 999) -- only for test purposes. releases will get a smaller number

if not lib then
	return
	-- already loaded and no upgrade necessary
end

local DUMMY_PIN_TYPE = LIB_NAME .. "DummyPin"
local LIB_IDENTIFIER_INIT = LIB_NAME .. "_Init"
local LIB_IDENTIFIER_UNMUTE = LIB_NAME .. "_UnmuteMapPing"
local LIB_IDENTIFIER_RESTORE = LIB_NAME .. "_Restore"
lib.LIB_EVENT_STATE_CHANGED = "OnLibGPS2MeasurementChanged"

local LOG_WARNING = "Warning"
local LOG_NOTICE = "Notice"
local LOG_DEBUG = "Debug"

local mapMeasurements = { }
local mapPinManager = nil
local mapPingSound = SOUNDS.MAP_PING
local mapPingRemoveSound = SOUNDS.MAP_PING_REMOVE
local mutes = 0
local needWaypointRestore = false
local orgSetMapToMapListIndex = nil
local orgSetMapToPlayerLocation = nil
local orgSetMapFloor = nil

lib.zoneIsPlayerLocation = {
	-- Imperial Sewer
	[390] = true,
}

-- lib.debugMode = 1

local function LogMessage(type, message, ...)
	if not lib.debugMode then return end
	df("[%s] %s: %s", LIB_NAME, type, zo_strjoin(" ", message, ...))
end

local function BoolString(b)
	return b and "true" or "false"
end

local function UpdateWaypointPin()
	if (mapPinManager) then
		mapPinManager:RemovePins("pings", MAP_PIN_TYPE_PLAYER_WAYPOINT, "waypoint")

		local x, y = GetMapPlayerWaypoint()
		if (x ~= 0 and y ~= 0) then
			LogMessage(LOG_DEBUG, "CreatePin", x, y)
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

local function RestoreMapPing()
	EVENT_MANAGER:UnregisterForUpdate(LIB_IDENTIFIER_RESTORE)
	SOUNDS.MAP_PING = mapPingSound
	SOUNDS.MAP_PING_REMOVE = mapPingRemoveSound
	CALLBACK_MANAGER:FireCallbacks(lib.LIB_EVENT_STATE_CHANGED, false)
end

local function UnmuteMapPing()
	local wasMuted = mutes > 0
	mutes = mutes - 1
	if (mutes <= 0) then
		mutes = 0
		if wasMuted then
			if needWaypointRestore then
				UpdateWaypointPin()
				needWaypointRestore = false
			end
			-- The WaypointIt handler, may called next, uses a muted sound as an indicator.
			-- Therefore restoring sound is delayed
			EVENT_MANAGER:RegisterForUpdate(LIB_IDENTIFIER_RESTORE, 100, RestoreMapPing)
		end
	end
end

local function HandleMapPingEvent(eventCode, pingEventType, pingType, pingTag, x, y, isPingOwner)
	local isWaypoint =(pingType == MAP_PIN_TYPE_PLAYER_WAYPOINT and pingTag == "waypoint")
	LogMessage(LOG_DEBUG, zo_strjoin(" ", "isWaypoint", isWaypoint, "mute", mutes, pingEventType == PING_EVENT_ADDED and "add" or "remove"))
	if mutes <= 0 or not isWaypoint then
		-- This is from worldmap.lua
		if (pingEventType == PING_EVENT_ADDED) then
			if isPingOwner then
				PlaySound(SOUNDS.MAP_PING)
			end
			mapPinManager:RemovePins("pings", pingType, pingTag)
			mapPinManager:CreatePin(pingType, pingTag, x, y)
		elseif (pingEventType == PING_EVENT_REMOVED) then
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
	if (wpX ~= 0 and wpY ~= 0) then
		MuteMapPing()
	end
	MuteMapPing()
	PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
end

local function GetMapInfoForReset()
	-- For the floors of Elden Root contentType is "MAP_CONTENT_DUNGEON", if navigating in. Not usable.
	-- The language-specific encoding "^..." of GetMapName() and GetPlayerLocationName() can differ and must be stripped off.
	-- The output of GetMapName() and GetPlayerLocationName() differs and is not reliable in all languages: e.g. Gil-Var-Tall Abandon Cave ~= Gil-Var-Tall
	local contentType, mapType, zoneIndex = GetMapContentType(), GetMapType(), GetCurrentMapZoneIndex()
	local format, str = zo_strformat, "<<!A:1>>"
	if (lib.debugMode) then
		LogMessage(LOG_DEBUG, "GetMapInfoForReset\r\n", zoneIndex, mapType, contentType, "\r\nSubZone:", BoolString(mapType == MAPTYPE_SUBZONE), "Dungeon:", BoolString(contentType == MAP_CONTENT_DUNGEON), "\r\n", GetZoneNameByIndex(zoneIndex), GetUnitZone("player"), "\r\n", format(str, GetMapName()), format(str, GetPlayerLocationName()))
	end
	local isPlayerLocation
	if (mapType ~= MAPTYPE_SUBZONE) then
		isPlayerLocation = zoneIndex and GetZoneNameByIndex(zoneIndex) == GetUnitZone("player")
		LogMessage(LOG_DEBUG, "isPlayerLocation by zone name")
	else
		if (not lib.zoneIsPlayerLocation[zoneIndex] and contentType ~= MAP_CONTENT_DUNGEON) then
			-- playerLocation is part of mapName: Gil-Var-Delle Abandon Cave <= Gil-Var-Delle
			-- mapName is part of playerLocation: Elden Root => Wayshrine of Elden Root
			local mapName, playerLocation = format(str, GetMapName()), format(str, GetPlayerLocationName())
			isPlayerLocation =(mapName:find(playerLocation, 1, true) or playerLocation:find(mapName, 1, true)) ~= nil
			LogMessage(LOG_DEBUG, "isPlayerLocation by location name")
		else
			isPlayerLocation = true
			LogMessage(LOG_DEBUG, "isPlayerLocation forced")
		end
	end
	local isZoneMap =(mapType == MAPTYPE_ZONE and contentType ~= MAP_CONTENT_DUNGEON)
	local isSubZoneMap =(mapType == MAPTYPE_SUBZONE)
	local mapFloor, mapFloorCount = GetMapFloorInfo()
	if (lib.debugMode) then
		LogMessage(LOG_DEBUG, "isPlayerLocation:", BoolString(isPlayerLocation), "isZoneMap:", BoolString(isZoneMap), "isSubZoneMap:", BoolString(isSubZoneMap), "floor:", mapFloor, "/", mapFloorCount)
	end
	return isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount
end

local function ResetToInitialMap(mapId, mapIndex, isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount)
	local needUpdate = false
	-- try to return to the initial map
	if (isZoneMap) then
		needUpdate = orgSetMapToMapListIndex(mapIndex) == SET_MAP_RESULT_MAP_CHANGED
		if (mapId:find("eyevea")) then
			-- Eveyea is located on the Tamriel map, but not really a zone or sub zone
			ProcessMapClick(0.06224, 0.61272)
		end
	elseif (isPlayerLocation) then
		needUpdate = orgSetMapToPlayerLocation() == SET_MAP_RESULT_MAP_CHANGED
	elseif (isSubZoneMap) then
		needUpdate = orgSetMapToMapListIndex(mapIndex) == SET_MAP_RESULT_MAP_CHANGED

		-- determine where on the zone map we have to click to get to the sub zone map
		local x, y
		local subZone = mapMeasurements[mapId]
		local zone = mapMeasurements[GetMapTileTexture()]
		-- get global coordinates of sub zone center
		x = subZone.offsetX + subZone.scaleX / 2
		y = subZone.offsetY + subZone.scaleY / 2
		-- transform to local zone coordinates
		x =(x - zone.offsetX) / zone.scaleX
		y =(y - zone.offsetY) / zone.scaleY

		assert(WouldProcessMapClick(x, y), zo_strjoin(nil, "Could not switch to sub zone map \"", GetPlayerLocationName(), "\" mapIndex=", mapIndex, " at ", x, ", ", y))
		needUpdate = ProcessMapClick(x, y) == SET_MAP_RESULT_MAP_CHANGED or needUpdate
	end
	if (mapFloorCount > 0) then
		-- some maps do have different floors (e.g. Elden Root)
		needUpdate = orgSetMapFloor(mapFloor) == SET_MAP_RESULT_MAP_CHANGED or needUpdate
	end
	return needUpdate
end


local function CalculateMeasurements(mapId, localX, localY)
	-- select the map corner farthest from the player position
	local wpX, wpY = 0.085, 0.085
	-- on some maps we cannot set the waypoint to the map border (e.g. Aurdion)
	-- Opposite corner:
	if (localX < 0.5) then wpX = 0.915 end
	if (localY < 0.5) then wpY = 0.915 end

	-- set measurement waypoint
	SetWaypointSilently(wpX, wpY)

	-- add local points to seen maps
	local measurementPositions = { }
	table.insert(measurementPositions, { mapId = mapId, pX = localX, pY = localY, wpX = wpX, wpY = wpY })

	-- switch to zone map in order to get the mapIndex for the current location
	while not(GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON) do
		if (MapZoomOut() ~= SET_MAP_RESULT_MAP_CHANGED) then break end
		-- add all maps we come through to seen maps
		local x1, y1 = GetMapPlayerPosition("player")
		local x2, y2 = GetMapPlayerWaypoint()

		table.insert(measurementPositions, { mapId = GetMapTileTexture(), pX = x1, pY = y1, wpX = x2, wpY = y2 })
	end

	-- some non-zone maps like Eyevea zoom directly to the Tamriel map
	local mapIndex = GetCurrentMapIndex() or 1

	-- switch to world map so we can calculate the global map scale and offset
	if orgSetMapToMapListIndex(1) == SET_MAP_RESULT_FAILED then
		-- failed to switch to the world map
		LogMessage(LOG_NOTICE, "Could not switch to world map")
		return
	end

	-- get the two reference points on the world map
	local x1, y1 = GetMapPlayerPosition("player")
	local x2, y2 = GetMapPlayerWaypoint()

	-- calculate scale and offset for all maps that we saw
	for _, m in ipairs(measurementPositions) do
		if (mapMeasurements[m.mapId]) then break end
		local scaleX =(x2 - x1) /(m.wpX - m.pX)
		local scaleY =(y2 - y1) /(m.wpY - m.pY)
		local offsetX = x1 - m.pX * scaleX
		local offsetY = y1 - m.pY * scaleY
		if (math.abs(scaleX - scaleY) > 1e-3) then
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

local function InterceptMapPinManager()
	if (mapPinManager) then return end
	ZO_WorldMap_AddCustomPin(DUMMY_PIN_TYPE, function(pinManager)
		mapPinManager = pinManager
		ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], false)
	end , nil, { level = 0, size = 0, texture = "" })
	ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], true)
	ZO_WorldMap_RefreshCustomPinsOfType(_G[DUMMY_PIN_TYPE])
end

local function HookSetMapToMapListIndex()
	orgSetMapToMapListIndex = SetMapToMapListIndex
	local function NewSetMapToMapListIndex(mapIndex)
		local result = orgSetMapToMapListIndex(mapIndex)
		if result ~= SET_MAP_RESULT_MAP_FAILED then
			-- To change or not to change, that's the question
			if lib:CalculateMapMeasurements(false) == true then
				LogMessage(LOG_DEBUG, "SetMapToMapListIndex")
				result = SET_MAP_RESULT_MAP_CHANGED
				orgSetMapToMapListIndex(mapIndex)
			end
		end
		-- All stuff is done before anyone triggers an "OnWorldMapChanged" event due to this result
		return result
	end
	SetMapToMapListIndex = NewSetMapToMapListIndex
end

local function HookSetMapToQuestCondition()
	local orgSetMapToQuestCondition = SetMapToQuestCondition
	local function NewSetMapToQuestCondition(...)
		local result = orgSetMapToQuestCondition(...)
		if result ~= SET_MAP_RESULT_MAP_FAILED then
			-- To change or not to change, that's the question
			if lib:CalculateMapMeasurements(false) == true then
				LogMessage(LOG_DEBUG, "SetMapToQuestCondition")
				result = SET_MAP_RESULT_MAP_CHANGED
				orgSetMapToQuestCondition(...)
			end
		end
		-- All stuff is done before anyone triggers an "OnWorldMapChanged" event due to this result
		return result
	end
	SetMapToQuestCondition = NewSetMapToQuestCondition
end

local function HookSetMapToPlayerLocation()
	orgSetMapToPlayerLocation = SetMapToPlayerLocation
	local function NewSetMapToPlayerLocation(...)
		local result = orgSetMapToPlayerLocation(...)
		if result ~= SET_MAP_RESULT_MAP_FAILED then
			-- To change or not to change, that's the question
			if lib:CalculateMapMeasurements(false) == true then
				LogMessage(LOG_DEBUG, "SetMapToPlayerLocation")
				result = SET_MAP_RESULT_MAP_CHANGED
				orgSetMapToPlayerLocation(...)
			end
		end
		-- All stuff is done before anyone triggers an "OnWorldMapChanged" event due to this result
		return result
	end
	SetMapToPlayerLocation = NewSetMapToPlayerLocation
end

local function HookSetMapToQuestZone()
	local orgSetMapToQuestZone = SetMapToQuestZone
	local function NewSetMapToQuestZone(...)
		local result = orgSetMapToQuestZone(...)
		if result ~= SET_MAP_RESULT_MAP_FAILED then
			-- To change or not to change, that's the question
			if lib:CalculateMapMeasurements(false) == true then
				LogMessage(LOG_DEBUG, "SetMapToQuestZone")
				result = SET_MAP_RESULT_MAP_CHANGED
				orgSetMapToQuestZone(...)
			end
		end
		-- All stuff is done before anyone triggers an "OnWorldMapChanged" event due to this result
		return result
	end
	SetMapToQuestZone = NewSetMapToQuestZone
end

-- There are floors marked as "dungeon". e.g. Elder Root floors
-- But in fact, they ARE reachable by map navigation from outside, if SetMapFloor does not fail.
local function HookSetMapFloor()
	local function IsFloor() return MAP_CONTENT_NONE end

	orgSetMapFloor = SetMapFloor
	local function NewSetMapFloor(...)
		local result = orgSetMapFloor(...)
		if result ~= SET_MAP_RESULT_MAP_FAILED then
			local orgGetMapContentType = GetMapContentType
			GetMapContentType = IsFloor
			if lib:CalculateMapMeasurements(true) == true then
				LogMessage(LOG_DEBUG, "SetMapFloor")
				result = SET_MAP_RESULT_MAP_CHANGED
			end
			GetMapContentType = orgGetMapContentType
		end
		return result
	end
	SetMapFloor = NewSetMapFloor
end

-- Unregister handler from older libGPS
EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER_INIT, EVENT_PLAYER_ACTIVATED)

EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER_INIT, EVENT_PLAYER_ACTIVATED, function()
	EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER_INIT, EVENT_PLAYER_ACTIVATED)

	InterceptMapPinManager()

	-- Unregister handler from older libGPS
	EVENT_MANAGER:UnregisterForEvent("LibGPS2_SaveWaypoint", EVENT_PLAYER_DEACTIVATED)
	EVENT_MANAGER:UnregisterForEvent("LibGPS2_RestoreWaypoint", EVENT_PLAYER_ACTIVATED)

	-- Unregister handler from older libGPS, otherwise the wrong handler is called
	EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER_UNMUTE, EVENT_MAP_PING)
	EVENT_MANAGER:UnregisterForEvent("ZO_WorldMap", EVENT_MAP_PING)

	EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER_UNMUTE, EVENT_MAP_PING, HandleMapPingEvent)

	HookSetMapToMapListIndex()
	HookSetMapToQuestCondition()
	HookSetMapToPlayerLocation()
	HookSetMapToQuestZone()
	HookSetMapFloor()
end )

------------------------ public functions ----------------------

--- Removes all cached measurement values.
function lib:ClearMapMeasurements()
	mapMeasurements = { }
end

--- Removes the cached measurement values for the map that is currently active.
function lib:ClearCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	mapMeasurements[mapId] = nil
end

--- Returns a table with the measurement values for the active map or nil if the measurements could not be calculated for some reason.
--- The table contains scaleX, scaleY, offsetX, offsetY and mapIndex.
--- scaleX and scaleY are the dimensions of the active map on the Tamriel map.
--- offsetX and offsetY are the offset of the top left corner on the Tamriel map.
--- mapIndex is the mapIndex of the parent zone of the current map.
function lib:GetCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	if (not mapMeasurements[mapId]) then
		-- try to calculate the measurements if they are not yet available
		lib:CalculateMapMeasurements()
	end
	return mapMeasurements[mapId]
end

--- Calculates the measurements for the current map and all parent maps.
--- This method does nothing if there is already a cached measurement for the active map.
function lib:CalculateMapMeasurements(returnToInitialMap)
	-- cosmic map cannot be measured (GetMapPlayerWaypoint returns 0,0)
	if (GetMapType() == MAPTYPE_COSMIC) then return end

	-- no need to take measurements more than once
	local mapId = GetMapTileTexture()
	if (mapMeasurements[mapId]) then return end

	-- no need to measure the world map
	if (GetCurrentMapIndex() == 1) then
		mapMeasurements[mapId] = {
			scaleX = 1,
			scaleY = 1,
			offsetX = 0,
			offsetY = 0,
			mapIndex = 1
		}
		return
	end

	-- get the player position on the current map
	local localX, localY = GetMapPlayerPosition("player")
	if (localX == 0 and localY == 0) then
		-- cannot take measurements while player position is not initialized
		return
	end

	assert(orgSetMapToMapListIndex ~= nil, "CalculateMapMeasurements called before or during player activation.")

	returnToInitialMap = returnToInitialMap ~= false

	CALLBACK_MANAGER:FireCallbacks(lib.LIB_EVENT_STATE_CHANGED, true)

	-- check some facts about the current map, so we can reset it later
	local oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount
	if returnToInitialMap then
		oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount = GetMapInfoForReset()
	end

	-- save waypoint location
	local oldWaypointX, oldWaypointY = GetMapPlayerWaypoint()

	local mapIndex = CalculateMeasurements(mapId, localX, localY)

	-- Until now, the waypoint was abused. Now the waypoint must be restored or removed again (not from Lua only).
	-- Not necessarily on the map we are coming from. Therefore the waypoint is re-set at global or coldhabour level.
	if (oldWaypointX ~= 0 or oldWaypointY ~= 0) then
		needWaypointRestore = true
		local measurements = mapMeasurements[mapId]
		local x = oldWaypointX * measurements.scaleX + measurements.offsetX
		local y = oldWaypointY * measurements.scaleY + measurements.offsetY
		-- setting a ping "twice" does not raise two events
		if (x > 0 and x < 1 and y > 0 and y < 1) then
			SetWaypointSilently(x, y)
		else
			-- when the waypoint is outside of the Tamriel map we can try if it is in coldharbour
			local coldharbourIndex = 23
			-- set to coldharbour
			orgSetMapToMapListIndex(coldharbourIndex)
			local coldharbourId = GetMapTileTexture()
			-- coldharbour measured?
			if not mapMeasurements[coldharbourId] then
				-- another SetWaypointSilently without event
				-- measure only: no backup, no restore
				if (CalculateMeasurements(coldharbourId, GetMapPlayerPosition("player")) ~= coldharbourIndex) then LogMessage(LOG_WARNING, "coldharbour is not map index 23?!?") end
				-- set to coldharbour
				orgSetMapToMapListIndex(coldharbourIndex)
			end
			measurements = mapMeasurements[coldharbourId]

			-- calculate waypoint coodinates within coldharbour
			x =(x - measurements.offsetX) / measurements.scaleX
			y =(y - measurements.offsetY) / measurements.scaleY
			if not(x < 0 or x > 1 or y < 0 or y > 1) then
				SetWaypointSilently(x, y)
			else
				LogMessage(LOG_DEBUG, "Cannot reset waypoint because it was outside of the world map")
			end
		end
	else
		-- setting and removing causes two events
		MuteMapPing()
		RemovePlayerWaypoint()
	end

	if (returnToInitialMap) then
		-- Go to initial map including coldhabour
		return ResetToInitialMap(mapId, mapIndex, oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount)
	else
		return true
	end
end

--- Converts the given map coordinates on the current map into coordinates on the Tamriel map.
--- Returns x and y on the world map and the mapIndex of the parent zone
--- or nil if the measurements of the active map are not available.
function lib:LocalToGlobal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if (measurements) then
		x = x * measurements.scaleX + measurements.offsetX
		y = y * measurements.scaleY + measurements.offsetY
		return x, y, measurements.mapIndex
	end
end

--- Converts the given global coordinates into a position on the active map.
--- Returns x and y on the current map or nil if the measurements of the active map are not available.
function lib:GlobalToLocal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if (measurements) then
		x =(x - measurements.offsetX) / measurements.scaleX
		y =(y - measurements.offsetY) / measurements.scaleY
		return x, y
	end
end

--- Converts the given map coordinates on the specified zone map into coordinates on the Tamriel map.
--- This method is useful if you want to convert global positions from the old LibGPS version into the new format.
--- Returns x and y on the world map and the mapIndex of the parent zone
--- or nil if the measurements of the zone map are not available.
function lib:ZoneToGlobal(mapIndex, x, y)
	lib:GetCurrentMapMeasurements()
	-- measurement done in here:
	SetMapToMapListIndex(mapIndex)
	x, y, mapIndex = lib:LocalToGlobal(x, y)
	return x, y, mapIndex
end

--- This function zooms and pans to the specified position on the active map.
function lib:PanToMapPosition(x, y)
	-- if we don't have access to the mapPinManager we cannot do anything
	if (not mapPinManager) then return end

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

	if (result ~= SET_MAP_RESULT_FAILED) then
		local localX, localY = x, y

		while WouldProcessMapClick(localX, localY) do
			result = ProcessMapClick(localX, localY)
			if (result == SET_MAP_RESULT_FAILED) then break end
			localX, localY = lib:GlobalToLocal(x, y)
		end
	end

	return result
end

SLASH_COMMANDS["/libgpsdebug"] = function(value)
	lib.debugMode =(tonumber(value) == 1)
	df("[LibGPS2] debug mode %s", lib.debugMode and "enabled" or "disabled")
end
