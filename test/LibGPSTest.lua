TestLibGPS = {}

local maps = {
	world = { scaleX = 1, scaleY = 1, offsetX = 0, offsetY = 0, mapIndex = 1, type = MAPTYPE_WORLD, contentType = MAP_CONTENT_NONE, tileName = "world", parent = nil },

	zoneA = { scaleX = 0.5, scaleY = 0.5, offsetX = 0, offsetY = 0, mapIndex = 2, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_NONE, tileName = "zoneA", parent = "world" },
	dungeonA = { scaleX = 0.25, scaleY = 0.25, offsetX = 0, offsetY = 0, mapIndex = nil, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_DUNGEON, tileName = "dungeonA", parent = "zoneA" },
	subzoneA = { scaleX = 0.25, scaleY = 0.25, offsetX = 0.125, offsetY = 0.125, mapIndex = nil, type = MAPTYPE_SUBZONE, contentType = MAP_CONTENT_NONE, tileName = "subzoneA", parent = "zoneA" },
	dungeonC = { scaleX = 0.125, scaleY = 0.125, offsetX = 0.25, offsetY = 0.25, mapIndex = nil, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_DUNGEON, tileName = "dungeonC", parent = "subzoneA" },

	zoneB = { scaleX = 0.5, scaleY = 0.5, offsetX = 0.5, offsetY = 0.5, mapIndex = 3, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_NONE, tileName = "zoneB", parent = "world" },
	dungeonB = { scaleX = 0.25, scaleY = 0.25, offsetX = 0.75, offsetY = 0.75, mapIndex = nil, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_DUNGEON, tileName = "dungeonB", parent = "zoneB" }
}
local mapKeyByMapIndex = {}
for mapKey, data in pairs(maps) do
	if(data.mapIndex) then
		mapKeyByMapIndex[data.mapIndex] = mapKey
	end
end

local currentMap = maps.zoneA
local playerLocation = currentMap
local wpX, wpY, pX, pY = 0, 0, 0, 0
GetMapTileTexture = function() return currentMap.tileName end
GetMapName = function() return currentMap.tileName end
GetPlayerLocationName = function() return currentMap.tileName end
GetMapFloorInfo = function() return 2, 0 end
GetMapPlayerWaypoint = function() return (wpX - currentMap.offsetX) / currentMap.scaleX, (wpY - currentMap.offsetY) / currentMap.scaleY end
GetMapPlayerPosition = function() return (pX - currentMap.offsetX) / currentMap.scaleX, (pY - currentMap.offsetY) / currentMap.scaleY end
PingMap = function(pinType, mapType, x, y) wpX, wpY = (x * currentMap.scaleX) + currentMap.offsetX, (y * currentMap.scaleY) + currentMap.offsetY end
RemovePlayerWaypoint = function() wpX, wpY = 0, 0 end
MapZoomOut = function() if(currentMap.parent) then currentMap = maps[currentMap.parent] return SET_MAP_RESULT_MAP_CHANGED else return SET_MAP_RESULT_FAILED end end
SetMapToMapListIndex = function(index)
	local targetMap = maps[mapKeyByMapIndex[index]]
	if(targetMap) then
		if(targetMap == currentMap) then return SET_MAP_RESULT_CURRENT_MAP_UNCHANGED end
		currentMap = targetMap
		return SET_MAP_RESULT_MAP_CHANGED
	else return SET_MAP_RESULT_FAILED end
end
SetMapToPlayerLocation = function()
	if(currentMap ~= playerLocation) then
		currentMap = playerLocation
		return SET_MAP_RESULT_MAP_CHANGED
	end
	return SET_MAP_RESULT_CURRENT_MAP_UNCHANGED
end
GetCurrentMapIndex = function() return currentMap.mapIndex end
GetMapType = function() return currentMap.type end
GetMapContentType = function() return currentMap.contentType end

local gps = LibStub("LibGPS2")
function TestLibGPS:setUp()
	gps:ClearMapMeasurements()
	currentMap = maps.zoneA
	wpX, wpY, pX, pY = 0, 0, 0, 0
end

-- do some tests on our test setup
function TestLibGPS:testGetMapFunctionsGlobal()
	currentMap = maps.zoneA
	PingMap(nil, nil, 0.5, 0.5)
	assertEqualsDelta(wpX, 0.25, 1e-10)
	assertEqualsDelta(wpY, 0.25, 1e-10)
	local x, y = GetMapPlayerWaypoint()
	assertEqualsDelta(x, 0.5, 1e-10)
	assertEqualsDelta(y, 0.5, 1e-10)

	pX, pY = 0.25, 0.25
	x, y = GetMapPlayerPosition()
	assertEqualsDelta(x, 0.5, 1e-10)
	assertEqualsDelta(y, 0.5, 1e-10)

	assertEquals(GetMapType(), 2)
	assertEquals(GetMapContentType(), 0)
end

function TestLibGPS:testGetMapFunctionsLocal()
	currentMap = maps.dungeonB
	PingMap(nil, nil, 0.5, 0.5)
	assertEqualsDelta(wpX, 0.875, 1e-10)
	assertEqualsDelta(wpY, 0.875, 1e-10)
	local x, y = GetMapPlayerWaypoint()
	assertEqualsDelta(x, 0.5, 1e-10)
	assertEqualsDelta(y, 0.5, 1e-10)

	pX, pY = 0.5, 0.5
	x, y = GetMapPlayerPosition()
	assertEquals(x, -1)
	assertEquals(y, -1)

	assertEquals(GetMapType(), 2)
	assertEquals(GetMapContentType(), 2)
end

-- test the actual library
function TestLibGPS:testGetCurrentMapMeasurementsZoneA()
	currentMap = maps.zoneA
	pX, pY = 0.25, 0.25

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.zoneA

	local measurements = gps:GetCurrentMapMeasurements()
	assertEquals(measurements.mapIndex, 2)
	assertEqualsDelta(measurements.scaleX, 0.5, 1e-10)
	assertEqualsDelta(measurements.scaleY, 0.5, 1e-10)
	assertEqualsDelta(measurements.offsetX, 0, 1e-10)
	assertEqualsDelta(measurements.offsetY, 0, 1e-10)
end

function TestLibGPS:testGetCurrentMapMeasurementsDungeonA()
	currentMap = maps.dungeonA
	pX, pY = 0.125, 0.125

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonA

	local measurements = gps:GetCurrentMapMeasurements()
	assertEquals(measurements.mapIndex, 2)
	assertEqualsDelta(measurements.scaleX, 0.25, 1e-10)
	assertEqualsDelta(measurements.scaleY, 0.25, 1e-10)
	assertEqualsDelta(measurements.offsetX, 0, 1e-10)
	assertEqualsDelta(measurements.offsetY, 0, 1e-10)
end

function TestLibGPS:testLocalToGlobalOnZoneA()
	currentMap = maps.zoneA
	pX, pY = 0.25, 0.25

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.zoneA

	local x, y, mapIndex = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 2)
	assertEqualsDelta(x, 0.25, 1e-10)
	assertEqualsDelta(y, 0.25, 1e-10)
end

function TestLibGPS:testLocalToGlobalOnDungeonA()
	currentMap = maps.dungeonA
	pX, pY = 0.125, 0.125

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonA

	local x, y, mapIndex = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 2)
	assertEqualsDelta(x, 0.125, 1e-10)
	assertEqualsDelta(y, 0.125, 1e-10)
end

function TestLibGPS:testLocalToGlobalOnDungeonB()
	currentMap = maps.dungeonB
	wpX, wpY, pX, pY = 0, 0, 0.5, 0.5

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonB

	local x, y, mapIndex = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 3)
	assertEqualsDelta(x, 0.875, 1e-10)
	assertEqualsDelta(y, 0.875, 1e-10)
end

function TestLibGPS:testLocalToGlobalOnDungeonC()
	currentMap = maps.dungeonC
	wpX, wpY, pX, pY = 0, 0, 0.5, 0.5

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonC

	local x, y, mapIndex = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 2)
	assertEqualsDelta(x, 0.3125, 1e-10)
	assertEqualsDelta(y, 0.3125, 1e-10)
end

function TestLibGPS:testGlobalToLocalOnZoneA()
	currentMap = maps.zoneA
	pX, pY = 0.25, 0.25

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.zoneA

	local x, y = gps:GlobalToLocal(0.25, 0.25)
	assertEqualsDelta(x, 0.5, 1e-10)
	assertEqualsDelta(y, 0.5, 1e-10)
end

function TestLibGPS:testGlobalToLocalOnDungeonA()
	currentMap = maps.dungeonA
	pX, pY = 0.125, 0.125

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonA

	local x, y = gps:GlobalToLocal(0.25, 0.25)
	assertEqualsDelta(x, 1, 1e-10)
	assertEqualsDelta(y, 1, 1e-10)
end

function TestLibGPS:testGlobalToLocalOnDungeonBWrongMapIndex()
	currentMap = maps.dungeonB

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonB

	local x, y = gps:GlobalToLocal(0.25, 0.25)
	assertEquals(x, -2)
	assertEquals(y, -2)
end

function TestLibGPS:testCreateMeasurementsPlayerOnRightBottomMapBorder()
	currentMap = maps.dungeonA
	pX, pY = 0.25, 0.25

	gps:CalculateCurrentMapMeasurements()
	currentMap = maps.dungeonA

	local measurements = gps:GetCurrentMapMeasurements()
	assertEquals(measurements.mapIndex, 2)
	assertEqualsDelta(measurements.scaleX, 0.25, 1e-10)
	assertEqualsDelta(measurements.scaleY, 0.25, 1e-10)
	assertEqualsDelta(measurements.offsetX, 0, 1e-10)
	assertEqualsDelta(measurements.offsetY, 0, 1e-10)
end

function TestLibGPS:testErrorReport()
--2:glenumbra/daggerfall_base:2:0.50189214944839:0.67225408554077:0.05:0.05:0.061461199074984:0.39308640360832:0.047657199203968:0.37373840808868:0.046129843629428:0.37218373806166:0.030547111490796:0.03109340054043
	local pX, pY = 0.484044, 0.227339
	local wpX, wpY = 0.95, 0.95
	local x1, y1 = 0.06916, 0.369252
	local x2, y2 = 0.075150, 0.401722
	local scaleX = (x2 - x1) / (wpX - pX)
	local scaleY = (y2 - y1) / (wpY - pY)
	local offsetX = x1 - pX * scaleX
	local offsetY = y1 - pY * scaleY
	print(0.03109340054043 - 0.030547111490796)
	print(scaleX)
	print(scaleY)
end
