TestLibGPS = {}

local maps = {
	zoneA = { scaleX = 1, scaleY = 1, offsetX = 0, offsetY = 0, mapIndex = 1, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_NONE, tileName = "zoneA", parent = nil },
	dungeonA = { scaleX = 0.5, scaleY = 0.5, offsetX = 0, offsetY = 0, mapIndex = nil, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_DUNGEON, tileName = "dungeonA", parent = "zoneA" },
	subzoneA = { scaleX = 0.5, scaleY = 0.5, offsetX = 0.25, offsetY = 0.25, mapIndex = nil, type = MAPTYPE_SUBZONE, contentType = MAP_CONTENT_NONE, tileName = "subzoneA", parent = "zoneA" },
	dungeonC = { scaleX = 0.25, scaleY = 0.25, offsetX = 0.5, offsetY = 0.5, mapIndex = nil, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_DUNGEON, tileName = "dungeonC", parent = "subzoneA" },
	zoneB = { scaleX = 1, scaleY = 1, offsetX = 0, offsetY = 0, mapIndex = 2, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_NONE, tileName = "zoneB", parent = nil },
	dungeonB = { scaleX = 0.5, scaleY = 0.5, offsetX = 0.5, offsetY = 0.5, mapIndex = nil, type = MAPTYPE_ZONE, contentType = MAP_CONTENT_DUNGEON, tileName = "dungeonB", parent = "zoneB" }
}
local currentMap = maps.zoneA
local wpX, wpY, pX, pY = 0, 0, 0, 0
GetMapTileTexture = function() return currentMap.tileName end
GetMapPlayerWaypoint = function() return (wpX - currentMap.offsetX) / currentMap.scaleX, (wpY - currentMap.offsetY) / currentMap.scaleY end
GetMapPlayerPosition = function() return (pX - currentMap.offsetX) / currentMap.scaleX, (pY - currentMap.offsetY) / currentMap.scaleY end
PingMap = function(pinType, mapType, x, y) wpX, wpY = (x * currentMap.scaleX) + currentMap.offsetX, (y * currentMap.scaleY) + currentMap.offsetY end
RemovePlayerWaypoint = function() wpX, wpY = 0, 0 end
MapZoomOut = function() if(currentMap.parent) then currentMap = maps[currentMap.parent] return SET_MAP_RESULT_MAP_CHANGED else return SET_MAP_RESULT_FAILED end end
GetCurrentMapIndex = function() return currentMap.mapIndex end
GetMapType = function() return currentMap.type end
GetMapContentType = function() return currentMap.contentType end

local gps = LibStub("LibGPS")
function TestLibGPS:setUp()
	gps:ClearMapMeasurements()
	currentMap = maps.zoneA
	wpX, wpY, pX, pY = 0, 0, 0, 0
end

-- do some tests on our test setup
function TestLibGPS:testGetMapFunctionsGlobal()
	currentMap = maps.zoneA
	PingMap(nil, nil, 0.5, 0.5)
	assertEquals(wpX, 0.5)
	assertEquals(wpY, 0.5)
	local x, y = GetMapPlayerWaypoint()
	assertEquals(x, 0.5)
	assertEquals(y, 0.5)

	pX, pY = 0.5, 0.5
	x, y = GetMapPlayerPosition()
	assertEquals(x, 0.5)
	assertEquals(y, 0.5)

	assertEquals(GetMapType(), 2)
	assertEquals(GetMapContentType(), 0)
end

function TestLibGPS:testGetMapFunctionsLocal()
	currentMap = maps.dungeonB
	PingMap(nil, nil, 0.5, 0.5)
	assertEquals(wpX, 0.75)
	assertEquals(wpY, 0.75)
	local x, y = GetMapPlayerWaypoint()
	assertEquals(x, 0.5)
	assertEquals(y, 0.5)

	pX, pY = 0.5, 0.5
	x, y = GetMapPlayerPosition()
	assertEquals(x, 0)
	assertEquals(y, 0)

	assertEquals(GetMapType(), 2)
	assertEquals(GetMapContentType(), 2)
end

-- test the actual library
function TestLibGPS:testGetCurrentMapMeasurementsZoneA()
	currentMap = maps.zoneA

	local measurements = gps:GetCurrentMapMeasurements()
	assertEquals(measurements.zoneIndex, 1)
	assertEquals(measurements.scaleX, 1)
	assertEquals(measurements.scaleY, 1)
	assertEquals(measurements.offsetX, 0)
	assertEquals(measurements.offsetY, 0)
end

function TestLibGPS:testGetCurrentMapMeasurementsDungeonA()
	currentMap = maps.dungeonA

	local measurements = gps:GetCurrentMapMeasurements()
	assertEquals(measurements.zoneIndex, 1)
	assertEquals(measurements.scaleX, 0.5)
	assertEquals(measurements.scaleY, 0.5)
	assertEquals(measurements.offsetX, 0)
	assertEquals(measurements.offsetY, 0)
end

function TestLibGPS:testLocalToGlobalOnZoneA()
	currentMap = maps.zoneA

	local mapIndex, x, y = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 1)
	assertEquals(x, 0.5)
	assertEquals(y, 0.5)
end

function TestLibGPS:testLocalToGlobalOnDungeonA()
	currentMap = maps.dungeonA

	local mapIndex, x, y = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 1)
	assertEquals(x, 0.25)
	assertEquals(y, 0.25)
end

function TestLibGPS:testLocalToGlobalOnDungeonB()
	currentMap = maps.dungeonB
	wpX, wpY, pX, pY = 0, 0, 0.5, 0.5

	local mapIndex, x, y = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 2)
	assertEquals(x, 0.75)
	assertEquals(y, 0.75)
end

function TestLibGPS:testLocalToGlobalOnDungeonC()
	currentMap = maps.dungeonC
	wpX, wpY, pX, pY = 0, 0, 0.5, 0.5

	local mapIndex, x, y = gps:LocalToGlobal(0.5, 0.5)
	assertEquals(mapIndex, 1)
	assertEquals(x, 0.625)
	assertEquals(y, 0.625)
end

function TestLibGPS:testGlobalToLocalOnZoneA()
	currentMap = maps.zoneA

	local x, y = gps:GlobalToLocal(1, 0.5, 0.5)
	assertEquals(x, 0.5)
	assertEquals(y, 0.5)
end

function TestLibGPS:testGlobalToLocalOnDungeonA()
	currentMap = maps.dungeonA

	local x, y = gps:GlobalToLocal(1, 0.5, 0.5)
	assertEquals(x, 1)
	assertEquals(y, 1)
end

function TestLibGPS:testGlobalToLocalOnDungeonBWrongMapIndex()
	currentMap = maps.dungeonB

	local x, y = gps:GlobalToLocal(1, 0.5, 0.5)
	assertIsNil(x)
	assertIsNil(y)
end