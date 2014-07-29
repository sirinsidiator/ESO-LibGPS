local LIB_NAME = "LibGPS2"
local lib = LibStub:NewLibrary(LIB_NAME, VERSION_NUMBER)

if not lib then
	return	-- already loaded and no upgrade necessary
end

local DUMMY_PIN_TYPE = LIB_NAME .. "DummyPin"
local REPORT_LINK_TYPE = LIB_NAME .. "report"
local LOG_WARNING = "Warning"
local LOG_ERROR = "Error"
local LOG_NOTICE = "Notice"
local ERROR_SWITCH_TO_SUBZONE = 1
local WARNING_INVALID_MEASUREMENT = 2

local mapMeasurements = {}
local backupWpX, backupWpY = 0, 0
local isMuted = false
local mapPinManager = nil
local mapPingSound = SOUNDS.MAP_PING
local mapPingRemoveSound = SOUNDS.MAP_PING_REMOVE
local mutes = 0
local clipBoardControl = nil
local reports = {}

local function LogMessage(type, message, ...)
	if(type == LOG_NOTICE) then
		d(string.format("%s %s: %s.", LIB_NAME, type, message))
	else
		table.insert(reports, zo_strjoin(':', ...))
		local link = ("|Hignore:%s:%d|h[click here]|h"):format(REPORT_LINK_TYPE, #reports)
		d(string.format("%s %s: %s. Please %s to copy debug information to your clipboard and then report it to the author.", LIB_NAME, type, message, link))
	end
end

LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_CLICKED_EVENT, function (link, button, text, color, linkType, reportId)
	if(linkType == REPORT_LINK_TYPE) then
		if(not clipBoardControl) then
			clipBoardControl = WINDOW_MANAGER:CreateControl(LIB_NAME .. "ClipboardControl", GuiRoot, CT_EDITBOX)
			clipBoardControl:SetHidden(true)
			clipBoardControl:SetMaxInputChars(1000)
		end
		clipBoardControl:SetText(reports[tonumber(reportId)])
		clipBoardControl:CopyAllTextToClipboard()
		ZO_Alert(UI_ALERT_CATEGORY_ALERT, SOUNDS.RECIPE_LEARNED, "debug info copied to clipboard")
		return true
	end
end)

local function InterceptMapPinManager()
	if(mapPinManager) then return end
	ZO_WorldMap_AddCustomPin(DUMMY_PIN_TYPE, function(pinManager)
		mapPinManager = pinManager
		ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], false)
	end, nil, {level = 0, size = 0, texture = ""})
	ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], true)
	ZO_WorldMap_RefreshCustomPinsOfType(_G[DUMMY_PIN_TYPE])
end

local function UpdateWaypointPin()
	zo_callLater(function ()
		if(mapPinManager) then
			mapPinManager:RemovePins("pings", MAP_PIN_TYPE_PLAYER_WAYPOINT, "waypoint")

			local x, y = GetMapPlayerWaypoint()
			if(x ~= 0 and y ~= 0) then
				mapPinManager:CreatePin(MAP_PIN_TYPE_PLAYER_WAYPOINT, "waypoint", x, y)
			end
		else
			ZO_WorldMap_UpdateMap()
		end
	end, 20)
end

local function MuteMapPing()
	SOUNDS.MAP_PING = nil
	SOUNDS.MAP_PING_REMOVE = nil
	mutes = mutes + 1
end

local function UnmuteMapPing()
	if(mutes <= 0) then
		SOUNDS.MAP_PING = mapPingSound
		SOUNDS.MAP_PING_REMOVE = mapPingRemoveSound
		mutes = 0
	else
		mutes = mutes - 1
	end
end

local function HandleMapPingEvent(eventCode, pingEventType, pingType, pingTag, x, y)
	if(pingType == MAP_PIN_TYPE_PLAYER_WAYPOINT and pingTag == "waypoint") then
		-- reset the sounds once we have seen all of the events we caused ourselves
		if(not SOUNDS.MAP_PING) then UnmuteMapPing() end
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

local function RemoveWaypointSilently()
	MuteMapPing()
	RemovePlayerWaypoint()
end

local function GetMapInfoForReset()
	local isPlayerLocation = (GetMapName() == GetPlayerLocationName())
	local isZoneMap = (GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON)
	local isSubZoneMap = (GetMapType() == MAPTYPE_SUBZONE)
	local mapFloor, mapFloorCount = GetMapFloorInfo()
	return isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount
end

local function ResetToInitialMap(mapId, mapIndex, isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount)
	if(not SCENE_MANAGER:IsShowing("worldMap")) then return end -- no need to reset it when the map is not showing

	-- try to return to the initial map
	if(isPlayerLocation) then
		SetMapToPlayerLocation()
	elseif(isZoneMap) then
		SetMapToMapListIndex(mapIndex)
		if(mapId:find("eyevea")) then -- Eveyea is located on the Tamriel map, but not really a zone or sub zone
			ProcessMapClick(0.06224, 0.61272)
		end
	elseif(isSubZoneMap) then
		SetMapToMapListIndex(mapIndex)

		-- determine where on the zone map we have to click to get to the sub zone map
		local x, y
		if(mapId:find("porthunding")) then -- some maps do not work when we simply click in the middle (e.g. Port Hunding)
			x, y = 0.65757, 0.46926
		elseif(mapId:find("eldenroot")) then
			x, y = 0.56497, 0.53504
		else
			local subZone = mapMeasurements[mapId]
			local zone = mapMeasurements[GetMapTileTexture()]
			-- get global coordinates of sub zone center
			x = subZone.offsetX + subZone.scaleX / 2
			y = subZone.offsetY + subZone.scaleY / 2
			-- transform to local zone coordinates
			x = (x - zone.offsetX) / zone.scaleX
			y = (y - zone.offsetY) / zone.scaleY
		end

		if(WouldProcessMapClick(x, y)) then
			ProcessMapClick(x, y)
			if(mapFloorCount > 0) then -- some maps do have different floors (e.g. Elden Root)
				SetMapFloor(mapFloor)
			end
		else
			LogMessage(LOG_ERROR, "Could not switch to sub zone map", ERROR_SWITCH_TO_SUBZONE, GetPlayerLocationName(), mapIndex, x, y)
		end
	else
		CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
	end
end

EVENT_MANAGER:RegisterForEvent(LIB_NAME .. "_Init", EVENT_PLAYER_ACTIVATED, function()
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME .. "_Init", EVENT_PLAYER_ACTIVATED)

	InterceptMapPinManager()
end)

EVENT_MANAGER:RegisterForEvent(LIB_NAME .. "_UnmuteMapPing", EVENT_MAP_PING, HandleMapPingEvent)

EVENT_MANAGER:RegisterForEvent(LIB_NAME .. "_SaveWaypoint", EVENT_PLAYER_DEACTIVATED, function()
	SetMapToMapListIndex(1)
	backupWpX, backupWpY = GetMapPlayerWaypoint()
end)

EVENT_MANAGER:RegisterForEvent(LIB_NAME .. "_RestoreWaypoint", EVENT_PLAYER_ACTIVATED, function()
	local wpX, wpY = GetMapPlayerWaypoint()
	if(wpX == 0 and wpY == 0 and backupWpX ~= 0 and backupWpY ~= 0) then
		if(backupWpX < 0 or backupWpX > 1 or backupWpY < 0 or backupWpY > 1) then
			SetMapToMapListIndex(23) -- set to coldharbour
			local coldharbourId = GetMapTileTexture()
			lib:CalculateCurrentMapMeasurements()
			local m = mapMeasurements[coldharbourId]

			local waypointX = (backupWpX - m.offsetX) / m.scaleX
			local waypointY = (backupWpY - m.offsetY) / m.scaleY
			if(waypointX < 0 or waypointX > 1 or waypointY < 0 or waypointY > 1) then
				LogMessage(LOG_NOTICE, "Cannot restore backup waypoint because it was outside of the world map")
			else
				SetWaypointSilently(waypointX, waypointY)
				UpdateWaypointPin()
			end
		else
			SetMapToMapListIndex(1) -- set to tamriel
			SetWaypointSilently(backupWpX, backupWpY)
			UpdateWaypointPin()
		end
	end
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
	-- cosmic map cannot be measured (GetMapPlayerWaypoint returns 0,0)
	if(GetMapType() == MAPTYPE_COSMIC) then return end

	-- no need to take measurements more than once
	local mapId = GetMapTileTexture()
	if(mapMeasurements[mapId]) then return end

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

	-- check some facts about the current map, so we can reset it later
	local oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount = GetMapInfoForReset()

	-- save waypoint location
	local oldWaypointX, oldWaypointY = GetMapPlayerWaypoint()

	-- select the map corner farthest from the player position
	local wpX, wpY = 0.05, 0.05 -- on some maps we cannot set the waypoint to the map border (e.g. Aurdion)
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
			LogMessage(LOG_WARNING, "Current map measurement might be wrong", WARNING_INVALID_MEASUREMENT, m.mapId:sub(10, -7), mapIndex, m.pX, m.pY, m.wpX, m.wpY, x1, y1, x2, y2, offsetX, offsetY, scaleX, scaleY)
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

	-- reset or remove the waypoint
	if(oldWaypointX == 0 and oldWaypointY == 0 and backupWpX == 0 and backupWpY == 0) then
		RemoveWaypointSilently()
	else
		local m = mapMeasurements[mapId]
		local waypointX, waypointY
		-- because of a bug in eso the waypoint gets lost when entering or leaving some locations (e.g. Themond Mine in Daggerfall)
		if(oldWaypointX == 0 and oldWaypointY == 0 and backupWpX ~= 0 and backupWpY ~= 0) then
			waypointX, waypointY = backupWpX, backupWpY
		else
			-- tranform the waypoint to a global position
			waypointX = oldWaypointX * m.scaleX + m.offsetX
			waypointY = oldWaypointY * m.scaleY + m.offsetY
		end

		-- when the waypoint is outside of the Tamriel map we can try if it is in coldharbour
		if(waypointX < 0 or waypointX > 1 or waypointY < 0 or waypointY > 1) then
			RemoveWaypointSilently() -- remove waypoint so we don't end up in an infinite loop
			zo_callLater(function() -- we wait until after the current measurement is finished because the coldharbour map might not have been measured yet
				SetMapToMapListIndex(23) -- set to coldharbour
				local coldharbourId = GetMapTileTexture()
				lib:CalculateCurrentMapMeasurements()
				local m = mapMeasurements[coldharbourId]

				-- calculate waypoint coodinates within coldharbour
				waypointX = (waypointX - m.offsetX) / m.scaleX
				waypointY = (waypointY - m.offsetY) / m.scaleY
				if(waypointX < 0 or waypointX > 1 or waypointY < 0 or waypointY > 1) then
					LogMessage(LOG_NOTICE, "Cannot reset waypoint because it was outside of the world map")
				else
					SetWaypointSilently(waypointX, waypointY)
					UpdateWaypointPin() -- update the waypoint pin so it won't show up in the wrong location
				end

				ResetToInitialMap(mapId, mapIndex, oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount)
			end, 20)
		else
			SetWaypointSilently(waypointX, waypointY)
			UpdateWaypointPin() -- update the waypoint pin so it won't show up in the wrong location
		end
	end

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
