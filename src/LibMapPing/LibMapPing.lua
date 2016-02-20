local LIB_IDENTIFIER = "LibMapPing"
local lib = LibStub:NewLibrary(LIB_IDENTIFIER, 2)

if not lib then
	return	-- already loaded and no upgrade necessary
end

local function Log(message, ...)
	df("[%s] %s", LIB_IDENTIFIER, message:format(...))
end

local MAP_PIN_TYPE_PLAYER_WAYPOINT = MAP_PIN_TYPE_PLAYER_WAYPOINT
local MAP_PIN_TYPE_PING = MAP_PIN_TYPE_PING
local MAP_PIN_TYPE_RALLY_POINT = MAP_PIN_TYPE_RALLY_POINT

local MAP_PIN_TAG_PLAYER_WAYPOINT = "waypoint"
local MAP_PIN_TAG_RALLY_POINT = "rally"
local PING_CATEGORY = "pings"

local MAP_PIN_TAG = {
	[MAP_PIN_TYPE_PLAYER_WAYPOINT] = MAP_PIN_TAG_PLAYER_WAYPOINT,
	--[MAP_PIN_TYPE_PING] = group pings have individual tags for each member
	[MAP_PIN_TYPE_RALLY_POINT] = MAP_PIN_TAG_RALLY_POINT,
}

local originalPingMap, originalRemovePlayerWaypoint, originalRemoveRallyPoint
local GET_MAP_PING_FUNCTION = {} -- is initialized in Load()
local REMOVE_MAP_PING_FUNCTION = {} -- also initialized in Load()

lib.MAP_PING_NOT_SET = 0
lib.MAP_PING_NOT_SET_PENDING = 1
lib.MAP_PING_SET_PENDING = 2
lib.MAP_PING_SET = 3

lib.mutePing = {}
lib.suppressPing = {}
lib.pingState = {}
lib.cm = lib.cm or ZO_CallbackObject:New()
local g_mapPinManager = lib.mapPinManager

local function GetPingTagFromType(pingType)
	return MAP_PIN_TAG[pingType] or GetGroupUnitTagByIndex(GetGroupIndexByUnitTag("player"))
end

local function GetKey(pingType, pingTag)
	pingTag = pingTag or GetPingTagFromType(pingType)
	return string.format("%d_%s", pingType, pingTag)
end

local function CustomPingMap(pingType, mapType, x, y)
	local key = GetKey(pingType)
	lib.pingState[key] = lib.MAP_PING_SET_PENDING
	originalPingMap(pingType, mapType, x, y)
end

local function CustomGetMapPlayerWaypoint()
	if(lib:IsPingSuppressed(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_PIN_TAG_PLAYER_WAYPOINT)) then
		return 0, 0
	end
	return GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_PLAYER_WAYPOINT]()
end

local function CustomGetMapPing(pingTag)
	if(lib:IsPingSuppressed(MAP_PIN_TYPE_PING, pingTag)) then
		return 0, 0
	end
	return GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_PING](pingTag)
end

local function CustomGetMapRallyPoint()
	if(lib:IsPingSuppressed(MAP_PIN_TYPE_RALLY_POINT, MAP_PIN_TAG_RALLY_POINT)) then
		return 0, 0
	end
	return GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_RALLY_POINT]()
end

local function CustomRemovePlayerWaypoint()
	local key = GetKey(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_PIN_TAG_PLAYER_WAYPOINT)
	lib.pingState[key] = lib.MAP_PING_NOT_SET_PENDING
	originalRemovePlayerWaypoint()
end

local function CustomRemoveMapPing()
	-- there is no such function for group pings, but we can set it to 0, 0 which effectively hides it
	PingMap(MAP_PIN_TYPE_PING, MAP_TYPE_LOCATION_CENTERED, 0, 0)
end

local function CustomRemoveRallyPoint()
	local key = GetKey(MAP_PIN_TYPE_RALLY_POINT, MAP_PIN_TAG_RALLY_POINT)
	lib.pingState[key] = lib.MAP_PING_NOT_SET_PENDING
	originalRemoveRallyPoint()
end

--- Wrapper for PingMap. See PingMap for a description
function lib:SetMapPing(pingType, mapType, x, y)
	PingMap(pingType, mapType, x, y)
end

--- Wrapper for the different ping removal functions.
--- For waypoints and rally points it calls their respective removal function
--- For group pings it just sets the position to 0, 0 as there is no function to clear them
function lib:RemoveMapPing(pingType)
	if(REMOVE_MAP_PING_FUNCTION[pingType]) then
		REMOVE_MAP_PING_FUNCTION[pingType]()
	end
end

--- Wrapper for the different get ping functions. Returns coordinates regardless of their suppression state.
--- The API functions are replaced with modified functions that return 0, 0 when the ping type is suppressed.
function lib:GetMapPing(pingType, pingTag)
	local x, y = 0, 0
	if(GET_MAP_PING_FUNCTION[pingType]) then
		x, y = GET_MAP_PING_FUNCTION[pingType](pingTag)
	end
	return x, y
end

--- Returns lib.MAP_PING_NOT_SET, lib.MAP_PING_NOT_SET_PENDING, lib.MAP_PING_SET_PENDING or lib.MAP_PING_SET
--- lib.MAP_PING_NOT_SET - there is no ping
--- lib.MAP_PING_NOT_SET_PENDING - the ping has been removed, but EVENT_MAP_PING has not been processed
--- lib.MAP_PING_SET_PENDING - a ping was added, but EVENT_MAP_PING has not been processed
--- lib.MAP_PING_SET - there is a ping
function lib:GetMapPingState(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	return lib.pingState[key] or lib.MAP_PING_NOT_SET
end

--- Returns true if ping state is lib.MAP_PING_SET_PENDING or lib.MAP_PING_SET
function lib:HasMapPing(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	local state = lib.pingState[key]
	return state == lib.MAP_PING_SET_PENDING or state == lib.MAP_PING_SET
end

--- Refreshes the pin icon for the pingType on the worldmap
function lib:RefreshMapPin(pingType, pingTag)
	if(not g_mapPinManager) then
		Log("PinManager not available. Using ZO_WorldMap_UpdateMap instead.")
		ZO_WorldMap_UpdateMap()
		return true
	end

	pingTag = pingTag or GetPingTagFromType(pingType)
	g_mapPinManager:RemovePins(PING_CATEGORY, pingType, pingTag)

	local x, y = lib:GetMapPing(pingType, pingTag)
	if(lib:IsPositionOnMap(x, y)) then
		g_mapPinManager:CreatePin(pingType, pingTag, x, y)
		return true
	end
	return false
end

--- Returns true if the normalized position is within the map
function lib:IsPositionOnMap(x, y)
	return not (x < 0 or y < 0 or x > 1 or y > 1 or (x == 0 and y == 0))
end

--- Mutes the map ping of the specified type, so it does not make a sound when it is set
function lib:MutePing(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	local mute = lib.mutePing[key] or 0
	lib.mutePing[key] = mute + 1
end

--- Unmutes the map ping of the specified type
function lib:UnmutePing(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	local mute = (lib.mutePing[key] or 0) - 1
	if(mute < 0) then mute = 0 end
	lib.mutePing[key] = mute
end

--- Returns true if the map ping has been muted
function lib:IsPingMuted(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	return lib.mutePing[key] and lib.mutePing[key] > 0
end

--- Suppresses the map ping of the specified type, so that it neither makes a sound nor shows up on the map
--- This also makes the API functions return 0, 0 for that ping
--- In order to access the actual coordinates lib:GetMapPing has to be used
function lib:SuppressPing(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	local suppress = lib.suppressPing[key] or 0
	lib.suppressPing[key] = suppress + 1
end

--- Unsuppresses the map ping so it shows up again
function lib:UnsuppressPing(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	local suppress = (lib.suppressPing[key] or 0) - 1
	if(suppress < 0) then suppress = 0 end
	lib.suppressPing[key] = suppress
end

--- Returns true if the map ping has been suppressed
function lib:IsPingSuppressed(pingType, pingTag)
	local key = GetKey(pingType, pingTag)
	return lib.suppressPing[key] and lib.suppressPing[key] > 0
end

local function InterceptMapPinManager()
	if (g_mapPinManager) then return end
	local orgRefreshCustomPins = ZO_WorldMapPins.RefreshCustomPins
	function ZO_WorldMapPins:RefreshCustomPins()
		g_mapPinManager = self
		lib.mapPinManager = self
	end
	ZO_WorldMap_RefreshCustomPinsOfType()
	ZO_WorldMapPins.RefreshCustomPins = orgRefreshCustomPins
end

-- TODO keep an eye on worldmap.lua for changes
local function HandleMapPing(eventCode, pingEventType, pingType, pingTag, x, y, isPingOwner)
	if(pingEventType == PING_EVENT_ADDED) then
		lib.cm:FireCallbacks("BeforePingAdded", pingType, pingTag, x, y, isPingOwner)
		lib.pingState[GetKey(pingType, pingTag)] = lib.MAP_PING_SET
		g_mapPinManager:RemovePins(PING_CATEGORY, pingType, pingTag)
		if(not lib:IsPingSuppressed(pingType, pingTag)) then
			g_mapPinManager:CreatePin(pingType, pingTag, x, y)
			if(isPingOwner and not lib:IsPingMuted(pingType, pingTag)) then
				PlaySound(SOUNDS.MAP_PING)
			end
		end
		lib.cm:FireCallbacks("AfterPingAdded", pingType, pingTag, x, y, isPingOwner)
	elseif(pingEventType == PING_EVENT_REMOVED) then
		lib.cm:FireCallbacks("BeforePingRemoved", pingType, pingTag, x, y, isPingOwner)
		lib.pingState[GetKey(pingType, pingTag)] = lib.MAP_PING_NOT_SET
		g_mapPinManager:RemovePins(PING_CATEGORY, pingType, pingTag)
		if (isPingOwner and not lib:IsPingSuppressed(pingType, pingTag) and not lib:IsPingMuted(pingType, pingTag)) then
			PlaySound(SOUNDS.MAP_PING_REMOVE)
		end
		lib.cm:FireCallbacks("AfterPingRemoved", pingType, pingTag, x, y, isPingOwner)
	end
end

--- Register to callbacks from the library
--- Valid events are BeforePingAdded, AfterPingAdded, BeforePingRemoved and AfterPingRemoved
--- These are fired at certain points during handling EVENT_MAP_PING
function lib:RegisterCallback(eventName, callback)
	lib.cm:RegisterCallback(eventName, callback)
end

--- Unregister from callbacks. See lib:RegisterCallback
function lib:UnregisterCallback(eventName, callback)
	lib.cm:UnregisterCallback(eventName, callback)
end

local function Unload()
	EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER, EVENT_ADD_ON_LOADED)
	EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER, EVENT_MAP_PING)
	PingMap = originalPingMap
	GetMapPlayerWaypoint = GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_PLAYER_WAYPOINT]
	GetMapPing = GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_PING]
	GetMapRallyPoint = GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_RALLY_POINT]
	RemovePlayerWaypoint = originalRemovePlayerWaypoint
	RemoveRallyPoint = originalRemoveRallyPoint
end

local function Load()
	InterceptMapPinManager()

	originalPingMap = PingMap
	PingMap = CustomPingMap

	GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_PLAYER_WAYPOINT] = GetMapPlayerWaypoint
	GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_PING] = GetMapPing
	GET_MAP_PING_FUNCTION[MAP_PIN_TYPE_RALLY_POINT] = GetMapRallyPoint
	GetMapPlayerWaypoint = CustomGetMapPlayerWaypoint
	GetMapPing = CustomGetMapPing
	GetMapRallyPoint = CustomGetMapRallyPoint

	-- we want to use the altered versions in the library in order to set the correct ping state
	-- so we need to also save the originals
	originalRemovePlayerWaypoint = RemovePlayerWaypoint
	originalRemoveRallyPoint = RemoveRallyPoint
	RemovePlayerWaypoint = CustomRemovePlayerWaypoint
	RemoveRallyPoint = CustomRemoveRallyPoint
	REMOVE_MAP_PING_FUNCTION[MAP_PIN_TYPE_PLAYER_WAYPOINT] = CustomRemovePlayerWaypoint
	REMOVE_MAP_PING_FUNCTION[MAP_PIN_TYPE_PING] = CustomRemoveMapPing -- has no real api equivalent
	REMOVE_MAP_PING_FUNCTION[MAP_PIN_TYPE_RALLY_POINT] = CustomRemoveRallyPoint

	EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER, EVENT_ADD_ON_LOADED, function(_, addonName)
		if(addonName == "ZO_Ingame") then
			EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER, EVENT_ADD_ON_LOADED)
			-- don't let worldmap do anything as we manage it instead
			EVENT_MANAGER:UnregisterForEvent("ZO_WorldMap", EVENT_MAP_PING)
			EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER, EVENT_MAP_PING, HandleMapPing)
		end
	end)

	lib.Unload = Unload
end

if(lib.Unload) then lib.Unload() end
Load()
