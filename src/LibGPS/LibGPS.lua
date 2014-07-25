local lib = LibStub:NewLibrary("LibGPS", VERSION_NUMBER)

if not lib then
	return	-- already loaded and no upgrade necessary
end

local mapMeasurements = {}
local backupWpX, backupWpY = 0, 0
local isMuted = false

local function TempMuteUI()
	if(isMuted) then return end
	isMuted = true
	local volume = GetSetting(Options_Audio_UISoundVolume.system, Options_Audio_UISoundVolume.settingId)
	SetSetting(Options_Audio_UISoundVolume.system, Options_Audio_UISoundVolume.settingId, 0)
	zo_callLater(function() -- cannot unmute synchronously or we will hear the UI sounds
		SetSetting(Options_Audio_UISoundVolume.system, Options_Audio_UISoundVolume.settingId, volume)
		isMuted = false
	end, 100)
end

function lib:ClearMapMeasurements()
	mapMeasurements = {}
end

function lib:ClearCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	mapMeasurements[mapId] = nil
end

local function GetMapInfoForReset()
	local isPlayerLocation = (GetMapName() == GetPlayerLocationName())
	local isZoneMap = (GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON)
	local isSubZoneMap = (GetMapType() == MAPTYPE_SUBZONE)
	local mapFloor, mapFloorCount = GetMapFloorInfo()
	return isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount
end

local function ResetToInitialMap(mapId, mapIndex, isPlayerLocation, isZoneMap, isSubZoneMap, mapFloor, mapFloorCount)
	-- try to return to the initial map
	if(isPlayerLocation) then
		SetMapToPlayerLocation()
	elseif(isZoneMap) then
		SetMapToMapListIndex(mapIndex)
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

		ProcessMapClick(x, y)
		if(mapFloorCount > 0) then -- some maps do have different floors (e.g. Elden Root)
			SetMapFloor(mapFloor)
		end
	else
		CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
	end
end

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

	-- check some facts about the current map, so we can reset it later
	local oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount = GetMapInfoForReset()

	-- get the player position on the current map
	local localX, localY = GetMapPlayerPosition("player")
	if(localX == 0 and localY == 0) then return end -- cannot take measurements while player position is not initialized

	TempMuteUI() -- temporarily mute the UI sounds so we can silently set waypoints

	-- save waypoint location
	local oldWaypointX, oldWaypointY = GetMapPlayerWaypoint()

	-- select the map corner farthest from the player position
	local wpX, wpY = 0.05, 0.05 -- on some maps we cannot set the waypoint to the map border (e.g. Aurdion)
	if(localX < 0.5) then wpX = 0.95 end
	if(localY < 0.5) then wpY = 0.95 end

	-- set measurement waypoint
	PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, wpX, wpY)

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
	if not (GetMapType() == MAPTYPE_WORLD) then d("LibGPS Error: could not switch to world map") return end -- failed to switch to the world map

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
		RemovePlayerWaypoint()
	else
		local m = mapMeasurements[mapId]
		local waypointX, waypointY
		-- because of a bug in eso the waypoint gets lost when entering or leaving some locations
		if(oldWaypointX == 0 and oldWaypointY == 0 and backupWpX ~= 0 and backupWpY ~= 0) then
			waypointX, waypointY = backupWpX, backupWpY
		else
			-- tranform the waypoint to a global position
			waypointX = oldWaypointX * m.scaleX + m.offsetX
			waypointY = oldWaypointY * m.scaleY + m.offsetY
		end

		-- we currently cannot reset the waypoint when it is outside of the Tamriel map
		if(waypointX < 0 or waypointX > 1 or waypointY < 0 or waypointY > 1) then
			RemovePlayerWaypoint() -- remove waypoint so we don't end up in an infinite loop
			zo_callLater(function()
				SetMapToMapListIndex(23) -- set to coldharbour
				local coldharbourId = GetMapTileTexture()
				lib:CalculateCurrentMapMeasurements()
				local m = mapMeasurements[coldharbourId]

				-- calculate waypoint coodinates within coldharbour
				waypointX = (waypointX - m.offsetX) / m.scaleX
				waypointY = (waypointY - m.offsetY) / m.scaleY
				if(waypointX < 0 or waypointX > 1 or waypointY < 0 or waypointY > 1) then
					d("LibGPS Error: cannot reset waypoint because it was outside of the world map")
				else
					PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, waypointX, waypointY)
					-- TODO: if RefreshMapPings ever gets exposed, call it directly
					zo_callLater(ZO_WorldMap_UpdateMap, 20) -- try to update the map so the waypoint won't show up in the wrong location
				end

				ResetToInitialMap(mapId, mapIndex, oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount)
			end, 20)
		else
			PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, waypointX, waypointY)
			zo_callLater(ZO_WorldMap_UpdateMap, 20) -- try to update the map so the waypoint won't show up in the wrong location
		end
	end

	ResetToInitialMap(mapId, mapIndex, oldMapIsPlayerLocation, oldMapIsZoneMap, oldMapIsSubZoneMap, oldMapFloor, oldMapFloorCount)
end

function lib:GetCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	if(not mapMeasurements[mapId]) then -- try to calculate the measurements if they are not yet available
		lib:CalculateCurrentMapMeasurements()
	end
	return mapMeasurements[mapId]
end

function lib:LocalToGlobal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if(measurements) then
		x = x * measurements.scaleX + measurements.offsetX
		y = y * measurements.scaleY + measurements.offsetY
		return x, y, measurements.mapIndex -- x and y on the world map and the zone index (if available)
	end
end

function lib:GlobalToLocal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if(measurements) then
		x = (x - measurements.offsetX) / measurements.scaleX
		y = (y - measurements.offsetY) / measurements.scaleY
		return x, y
	end
end

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

EVENT_MANAGER:RegisterForEvent("LibGPS_PlayerDeactivated", EVENT_PLAYER_DEACTIVATED , function()
	local x, y = GetMapPlayerWaypoint()
	if(x ~= 0 and y ~= 0) then
		backupWpX, backupWpY = lib:LocalToGlobal(x, y)
	else
		backupWpX, backupWpY = 0
	end
end)

EVENT_MANAGER:RegisterForEvent("LibGPS_PlayerActivated", EVENT_PLAYER_ACTIVATED , function()
	local x, y = GetMapPlayerWaypoint()
	if(x == 0 and y == 0 and backupWpX ~= 0 and backupWpY ~= 0) then
		TempMuteUI()
		x, y = lib:GlobalToLocal(backupWpX, backupWpY)
		PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
	end
end)