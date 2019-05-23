-- LibGPS3 & its files © sirinsidiator                          --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local EVENT_MANAGER = EVENT_MANAGER
local lib = LibGPS3
local logger = lib.internal.logger

local MAP_PIN_TYPE_PLAYER_WAYPOINT = MAP_PIN_TYPE_PLAYER_WAYPOINT
local MAP_TYPE_LOCATION_CENTERED = MAP_TYPE_LOCATION_CENTERED
local SET_MAP_RESULT_FAILED = SET_MAP_RESULT_FAILED
local LIB_IDENTIFIER_FINALIZE = "LibGPS3_Finalize"

local WaypointManager = ZO_Object:Subclass()
lib.internal.class.WaypointManager = WaypointManager

function WaypointManager:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function WaypointManager:Initialize(adapter, meter)
    self.adapter = adapter
    self.meter = meter
    self.LMP = LibStub("LibMapPing")
    self.suppressCount = 0
    self:ClearPlayerWaypoint()

    local function FinalizeMeasurement()
        EVENT_MANAGER:UnregisterForUpdate(LIB_IDENTIFIER_FINALIZE)
        self:UnsuppressWaypoint()
        meter:SetMeasuring(false)
    end

    local function HandlePingEvent(pingType, pingTag, x, y, isPingOwner)
        if(not isPingOwner or pingType ~= MAP_PIN_TYPE_PLAYER_WAYPOINT or not meter:IsMeasuring()) then return end
        -- we delay our handler until all events have been fired and so that other addons can react to it first in case they use IsMeasuring
        EVENT_MANAGER:UnregisterForUpdate(LIB_IDENTIFIER_FINALIZE)
        EVENT_MANAGER:RegisterForUpdate(LIB_IDENTIFIER_FINALIZE, 0, FinalizeMeasurement)
    end
    self.LMP:RegisterCallback("AfterPingAdded", HandlePingEvent)
    self.LMP:RegisterCallback("AfterPingRemoved", HandlePingEvent)
end

function WaypointManager:GetPlayerWaypoint()
    return self.LMP:GetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function WaypointManager:SetPlayerWaypoint(x, y)
    self.LMP:SetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
end

function WaypointManager:HasPlayerWaypoint()
    return self.LMP:HasMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function WaypointManager:RemovePlayerWaypoint()
    self.LMP:RemoveMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
end

function WaypointManager:SetMeasurementWaypoint(x, y)
    -- this waypoint stays invisible for others
    self.suppressCount = self.suppressCount + 1
    self.LMP:SuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
    self:SetPlayerWaypoint(x, y)
end

function WaypointManager:UnsuppressWaypoint()
    while self.suppressCount > 0 do
        self.LMP:UnsuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
        self.suppressCount = self.suppressCount - 1
    end
    if(self.needWaypointRestore) then
        self.LMP:RefreshMapPin(MAP_PIN_TYPE_PLAYER_WAYPOINT)
        self.needWaypointRestore = false
    end
end

function WaypointManager:StorePlayerWaypoint()
    self.x, self.y = self:GetPlayerWaypoint()
    self.id = self.adapter:GetCurrentMapIdentifier()
end

function WaypointManager:ClearPlayerWaypoint()
    self.x, self.y = 0, 0
    self.id = nil
end

function WaypointManager:RestorePlayerWaypoint()
    if(not self.id) then
        logger:Warn("Called Restore without calling Store.")
        return
    end

    local wasSet = false
    if (self.x ~= 0 or self.y ~= 0) then
        -- calculate waypoint position on the worldmap
        local measurement = self.meter:GetMeasurement(self.id)
        if(not measurement) then
            logger:Warn("Cannot reset waypoint because there is no measurement for its map")
            self:Clear()
            self:RemovePlayerWaypoint()
            return
        end

        local x, y = measurement:ToGlobal(self.x, self.y)

        local rootMapMeasurement = self.meter:FindRootMapMeasurementForCoordinates(x, y)
        if(rootMapMeasurement) then
            if(self.adapter:SetMapToMapListIndexWithoutMeasuring(rootMapMeasurement:GetMapIndex()) ~= SET_MAP_RESULT_FAILED) then
                x, y = rootMapMeasurement:ToLocal(x, y)
                self:SetPlayerWaypoint(x, y)
                wasSet = true
            else
                logger:Info("Cannot reset waypoint because switch to target root map failed")
            end
        else
            logger:Info("Cannot reset waypoint because it was outside of our reach")
        end
    end

    self:ClearPlayerWaypoint()

    if(wasSet) then
        logger:Debug("Waypoint was restored, request pin update")
        self.needWaypointRestore = true -- notify that we need to update the pin on the worldmap afterwards
    else
        self:RemovePlayerWaypoint()
    end
end
