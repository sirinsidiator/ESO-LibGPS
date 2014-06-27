local lib = LibStub:NewLibrary("LibGPS", 1)

if not lib then
	return	-- already loaded and no upgrade necessary
end

local volume = 70
local mapMeasurements = {}

local function MuteUI()
	volume = GetSetting(Options_Audio_UISoundVolume.system, Options_Audio_UISoundVolume.settingId)
	SetSetting(Options_Audio_UISoundVolume.system, Options_Audio_UISoundVolume.settingId, 0)
end

local function UnmuteUI()
	SetSetting(Options_Audio_UISoundVolume.system, Options_Audio_UISoundVolume.settingId, volume)
end

function lib:ClearMapMeasurements()
	mapMeasurements = {}
end

function lib:GetCurrentMapMeasurements()
	local mapId = GetMapTileTexture()
	if(not mapMeasurements[mapId]) then
		if(GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON) then
			mapMeasurements[mapId] = {
				scaleX = 1,
				scaleY = 1,
				offsetX = 0,
				offsetY = 0,
				zoneIndex = GetCurrentMapIndex()
			}
		else
			MuteUI()
			zo_callLater(UnmuteUI, 10) -- can't call this during this function call or we will hear the ui sounds
			local oldX, oldY = GetMapPlayerWaypoint()
			local localX, localY = GetMapPlayerPosition("player")

			PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, 1, 1)

			while not (GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON) do
				if(MapZoomOut() ~= SET_MAP_RESULT_MAP_CHANGED) then break end
			end

			if(GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON) then
				local x1, y1 = GetMapPlayerPosition("player")
				local x2, y2 = GetMapPlayerWaypoint()
				local scaleX = (x2 - x1) / (1 - localX)
				local scaleY = (y2 - y1) / (1 - localY)
				local offsetX = x1 - localX * scaleX
				local offsetY = y1 - localY * scaleY
				mapMeasurements[mapId] = {
					scaleX = scaleX,
					scaleY = scaleY,
					offsetX = offsetX,
					offsetY = offsetY,
					zoneIndex = GetCurrentMapIndex()
				}
			end

			if(oldX ~= 0 and oldY ~= 0 and mapMeasurements[mapId]) then
				local measurements = mapMeasurements[mapId]
				oldX = oldX * measurements.scaleX + measurements.offsetX
				oldY = oldY * measurements.scaleY + measurements.offsetY
				PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, oldX, oldY)
			else
				RemovePlayerWaypoint()
			end
		end
	end
	return mapMeasurements[mapId]
end

function lib:LocalToGlobal(x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if(measurements) then
		x = x * measurements.scaleX + measurements.offsetX
		y = y * measurements.scaleY + measurements.offsetY
		return measurements.zoneIndex, x, y
	end
end

function lib:GlobalToLocal(zoneIndex, x, y)
	local measurements = lib:GetCurrentMapMeasurements()
	if(measurements and zoneIndex == measurements.zoneIndex) then
		x = (x - measurements.offsetX) / measurements.scaleX
		y = (y - measurements.offsetY) / measurements.scaleY
		return x, y
	end
end