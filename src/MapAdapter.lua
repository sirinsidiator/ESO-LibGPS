-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LGPS = LibGPS
local internal = LGPS.internal
local original = internal.original
local logger = internal.logger

local TAMRIEL_MAP_INDEX = LGPS.internal.TAMRIEL_MAP_INDEX
local DUMMY_PIN_TYPE = "LibGPSDummyPin"
local MAP_PIN_TYPE_PLAYER_WAYPOINT = MAP_PIN_TYPE_PLAYER_WAYPOINT

local MapAdapter = ZO_Object:Subclass()
LGPS.class.MapAdapter = MapAdapter

function MapAdapter:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function MapAdapter:Initialize()
    self.LMP = LibStub("LibMapPing")
    self.stack = {}
    self.suppressCount = 0

    self.anchor = ZO_Anchor:New()
    self.panAndZoom = ZO_WorldMap_GetPanAndZoom()
    self.mapPinManager = ZO_WorldMap_GetPinManager()
    ZO_WorldMap_AddCustomPin(DUMMY_PIN_TYPE, function(pinManager) end , nil, { level = 0, size = 0, texture = "" })
    ZO_WorldMap_SetCustomPinEnabled(_G[DUMMY_PIN_TYPE], false)
end

function MapAdapter:PanToMapPosition(x, y)
    -- if we don't have access to the mapPinManager we cannot do anything
    if (not self.mapPinManager) then return end
    local mapPinManager = self.mapPinManager
    -- create dummy pin
    local pin = mapPinManager:CreatePin(_G[DUMMY_PIN_TYPE], "libgpsdummy", x, y)

    self.panAndZoom:PanToPin(pin)

    -- cleanup
    mapPinManager:RemovePins(DUMMY_PIN_TYPE)
end

local function FakeZO_WorldMap_IsMapChangingAllowed() return true end
local function FakeSetMapToMapListIndex() return SET_MAP_RESULT_MAP_CHANGED end
local FakeCALLBACK_MANAGER = { FireCallbacks = function() end }

function MapAdapter:SetPlayerChoseCurrentMap() -- TODO: investigate if there is a better way now
    -- replace the original functions
    local oldIsChangingAllowed = ZO_WorldMap_IsMapChangingAllowed
    ZO_WorldMap_IsMapChangingAllowed = FakeZO_WorldMap_IsMapChangingAllowed

    local oldSetMapToMapListIndex = SetMapToMapListIndex
    SetMapToMapListIndex = FakeSetMapToMapListIndex

    local oldCALLBACK_MANAGER = CALLBACK_MANAGER
    CALLBACK_MANAGER = FakeCALLBACK_MANAGER

    -- make our rigged call to set the player chosen flag
    ZO_WorldMap_SetMapByIndex()

    -- cleanup
    ZO_WorldMap_IsMapChangingAllowed = oldIsChangingAllowed
    SetMapToMapListIndex = oldSetMapToMapListIndex
    CALLBACK_MANAGER = oldCALLBACK_MANAGER
end

if(GetAPIVersion() >= 100025) then -- TODO remove
    function MapAdapter:SetCurrentZoom(zoom)
        return self.panAndZoom:SetCurrentNormalizedZoom(zoom)
    end

    function MapAdapter:GetCurrentZoom()
        return self.panAndZoom:GetCurrentNormalizedZoom()
    end
else
    function MapAdapter:SetCurrentZoom(zoom)
        return self.panAndZoom:SetCurrentZoom(zoom)
    end

    function MapAdapter:GetCurrentZoom()
        return self.panAndZoom:GetCurrentZoom()
    end
end

function MapAdapter:SetCurrentOffset(offsetX, offsetY)
    return self.panAndZoom:SetCurrentOffset(offsetX, offsetY)
end

-- There is no panAndZoom:GetCurrentOffset(), yet
local function CalculateContainerAnchorOffsets() -- TODO test and destroy
    local containerCenterX, containerCenterY = ZO_WorldMapContainer:GetCenter()
    local scrollCenterX, scrollCenterY = ZO_WorldMapScroll:GetCenter()
    return containerCenterX - scrollCenterX, containerCenterY - scrollCenterY
end

function MapAdapter:GetCurrentOffset()
    local anchor = self.anchor
    anchor:SetFromControlAnchor(ZO_WorldMapContainer, 0)
    return anchor:GetOffsetX(), anchor:GetOffsetY()
end

function MapAdapter:SetMeasurementWaypoint(x, y)
    -- this waypoint stays invisible for others
    self.suppressCount = self.suppressCount + 1
    self.LMP:SuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
    self.LMP:SetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
end

function MapAdapter:UnsuppressWaypoint()
    while self.suppressCount > 0 do
        self.LMP:UnsuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
        self.suppressCount = self.suppressCount - 1
    end
end

function MapAdapter:RefreshWaypointPin()
    self.LMP:RefreshMapPin(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function MapAdapter:GetPlayerPosition()
    return GetMapPlayerPosition("player")
end

function MapAdapter:GetPlayerWaypoint()
    return self.LMP:GetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function MapAdapter:SetPlayerWaypoint(x, y)
    self.LMP:SetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
end

function MapAdapter:HasPlayerWaypoint()
    return self.LMP:HasMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function MapAdapter:RemovePlayerWaypoint()
    self.LMP:RemoveMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function MapAdapter:GetReferencePoints()
    local x1, y1 = self:GetPlayerPosition()
    local x2, y2 = self:GetPlayerWaypoint()
    return x1, y1, x2, y2
end

function MapAdapter:GetCurrentMapIndex()
    return GetCurrentMapIndex()
end

function MapAdapter:GetCurrentZoneId()
    return GetZoneId(GetCurrentMapZoneIndex())
end

function MapAdapter:GetCurrentMapIdentifier()
    return GetMapTileTexture()
end

function MapAdapter:GetFormattedMapName(mapIndex)
    local name = GetMapInfo(mapIndex)
    return zo_strformat("<<C:1>>", name)
end

function MapAdapter:IsCurrentMapZoneMap()
    return GetMapType() == MAPTYPE_ZONE and GetMapContentType() ~= MAP_CONTENT_DUNGEON
end

function MapAdapter:IsCurrentMapCosmicMap()
    return GetMapType() == MAPTYPE_COSMIC
end

function MapAdapter:TryZoomOut()
    return MapZoomOut() == SET_MAP_RESULT_MAP_CHANGED
end

function MapAdapter:TrySwitchToWorldMap()
    return original.SetMapToMapListIndex(TAMRIEL_MAP_INDEX) ~= SET_MAP_RESULT_FAILED
end

function MapAdapter:RegisterPingHandler(callback)
    self.LMP:RegisterCallback("AfterPingAdded", callback)
    self.LMP:RegisterCallback("AfterPingRemoved", callback)
end
