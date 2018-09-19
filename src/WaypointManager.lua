local LGPS = LibGPS
local internal = LGPS.internal
local original = internal.original
local logger = internal.logger

local WaypointManager = ZO_Object:Subclass()
LGPS.class.WaypointManager = WaypointManager

function WaypointManager:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function WaypointManager:Initialize()
    self:Clear()
end

function WaypointManager:Store()
    self.x, self.y = internal.mapAdapter:GetPlayerWaypoint()
    self.id = internal.mapAdapter:GetCurrentMapIdentifier()
end

function WaypointManager:Clear()
    self.x, self.y = 0, 0
    self.id = nil
end

function WaypointManager:Restore()
    if(not self.id) then
        logger:Warn("Called Restore without calling Store.")
        return
    end

    local wasSet = false
    if (self.x ~= 0 or self.y ~= 0) then
        -- calculate waypoint position on the worldmap
        local measurement = internal.meter:GetMeasurement(self.id)
        if(not measurement) then
            logger:Warn("Cannot reset waypoint because there is no measurement for its map")
            self:Clear()
            internal.mapAdapter:RemovePlayerWaypoint()
            return
        end

        local x, y = measurement:ToGlobal(self.x, self.y)

        local rootMapMeasurement = internal.meter:FindRootMapMeasurementForCoordinates(x, y)
        if(rootMapMeasurement) then
            if(original.SetMapToMapListIndex(rootMapMeasurement:GetMapIndex()) ~= SET_MAP_RESULT_FAILED) then
                x, y = rootMapMeasurement:ToLocal(x, y)
                internal.mapAdapter:SetPlayerWaypoint(x, y)
                wasSet = true
            else
                logger:Info("Cannot reset waypoint because switch to target root map failed")
            end
        else
            logger:Info("Cannot reset waypoint because it was outside of our reach")
        end
    end

    self:Clear()

    if(wasSet) then
        logger:Debug("Waypoint was restored, request pin update")
        self.needWaypointRestore = true -- notify that we need to update the pin on the worldmap afterwards
    else
        internal.mapAdapter:RemovePlayerWaypoint()
    end
end

function WaypointManager:RefreshMapPinIfNeeded()
    if(self.needWaypointRestore) then
        internal.mapAdapter:RefreshWaypointPin()
        self.needWaypointRestore = false
    end
end
